extends Node

## Owns the profile database (user://data/profiles_data.json) and the
## per-profile backup of Riot Client files (user://profiles/<dir>/).
##
## Session save/restore only touches the filesystem; killing processes and
## orchestration belong to the caller (ProfileGridController).
##
## Thread-safety: session save/restore run on a worker thread while the UI
## thread may add/rename/delete profiles. All reads and writes of _profiles
## are guarded by _profiles_lock; file copies use temp-then-rename swaps so
## a failed or interrupted copy never destroys the previous good backup.

signal profiles_updated

## Riot Client files that carry login/session state and must be swapped
## per profile. NOTE: "lockfile" is intentionally excluded — it is transient
## and restoring a stale one breaks the client.
const FILES_TO_SWITCH: Array[Dictionary] = [
	{
		"id": "private_settings",
		"filename": "RiotGamesPrivateSettings.yaml",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Data/RiotGamesPrivateSettings.yaml",
	},
	{
		"id": "sessions_dir",
		"filename": "Sessions",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Data/Sessions",
		"is_dir": true,
	},
	{
		"id": "riot_client_settings",
		"filename": "RiotClientSettings.yaml",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Config/RiotClientSettings.yaml",
	},
	{
		"id": "client_config",
		"filename": "client.config.yaml",
		"base": "install_dir",
		"rel_path": "Config/client.config.yaml",
	},
	{
		"id": "client_settings",
		"filename": "client.settings.yaml",
		"base": "install_dir",
		"rel_path": "Config/client.settings.yaml",
	},
]

const DIR_TMP_SUFFIX := "_tmp"
const FILE_TMP_SUFFIX := ".tmp"

var _profiles: Array = []
var _profiles_lock := Mutex.new()


#region Public API — profile database

## Loads profiles from disk into the cache and notifies listeners.
## If the file is corrupt, it is backed up (never silently destroyed) before
## starting fresh.
func load_profiles_data() -> Array:
	_profiles_lock.lock()
	var data = JsonFile.load_data(AppPaths.PROFILES_FILE)
	if data is Dictionary and data.get("profiles") is Array:
		_profiles = data["profiles"]
		_normalize_profiles()
	else:
		_profiles = []
		if FileAccess.file_exists(AppPaths.PROFILES_FILE):
			var corrupt_backup := AppPaths.PROFILES_FILE + ".corrupt.bak"
			printerr("ProfileManager: profiles file is invalid; backing it up to '%s' before resetting." % corrupt_backup)
			if DirAccess.copy_absolute(AppPaths.PROFILES_FILE, corrupt_backup) != OK:
				printerr("ProfileManager: Failed to back up the corrupt profiles file!")
		JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": []})
	var result: Array = _profiles.duplicate()
	_profiles_lock.unlock()
	profiles_updated.emit()
	print("ProfileManager: %d profile(s) loaded." % result.size())
	return result


func get_profiles() -> Array:
	_profiles_lock.lock()
	var copy: Array = _profiles.duplicate()
	_profiles_lock.unlock()
	return copy


func get_profile_count() -> int:
	_profiles_lock.lock()
	var count := _profiles.size()
	_profiles_lock.unlock()
	return count


func has_profile(profile_name: String) -> bool:
	_profiles_lock.lock()
	var found := not _find_profile_unsafe(profile_name).is_empty()
	_profiles_lock.unlock()
	return found


## Creates the profile directory and registers the profile. Returns true on success.
func add_profile(profile_name: String, background_path: String, has_custom_name: bool = true, description: String = "") -> bool:
	if profile_name.is_empty():
		printerr("ProfileManager: Profile name cannot be empty.")
		return false

	_profiles_lock.lock()
	if not _find_profile_unsafe(profile_name).is_empty():
		_profiles_lock.unlock()
		printerr("ProfileManager: Profile '%s' already exists." % profile_name)
		return false

	# Resolve a directory name that no other profile or on-disk folder uses,
	# so two names like "A B" and "A_B" can never share (and corrupt) a session.
	var directory_name := _resolve_unique_directory_name(_sanitize_directory_name(profile_name))
	var profile_dir := AppPaths.PROFILES_DIR.path_join(directory_name)
	if DirAccess.make_dir_recursive_absolute(profile_dir) != OK:
		_profiles_lock.unlock()
		printerr("ProfileManager: Failed to create profile directory: ", profile_dir)
		return false

	var new_profile := {
		"profile_name": profile_name,
		"custom_background_image": background_path,
		"first_time_opened": false,
		"directory_name": directory_name,
		"has_custom_name": has_custom_name,
		"description": description.strip_edges(),
	}
	_profiles.append(new_profile)
	if not _save_profiles_file():
		_profiles.erase(new_profile)
		_profiles_lock.unlock()
		# Best effort: remove the now-orphaned directory so no data is leaked.
		DirAccess.remove_absolute(profile_dir)
		return false
	_profiles_lock.unlock()

	# Seed the newly created profile folder with shared game settings if enabled (outside mutex lock)
	_seed_shared_settings_for_new_profile(profile_dir)

	profiles_updated.emit()
	print("ProfileManager: Profile '%s' successfully added." % profile_name)
	return true


## Removes the profile from the database and deletes its files. Returns true on success.
func delete_profile(profile_name: String) -> bool:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	if profile.is_empty():
		_profiles_lock.unlock()
		printerr("ProfileManager: Profile '%s' not found." % profile_name)
		return false

	var index := _profiles.find(profile)
	_profiles.remove_at(index)
	if not _save_profiles_file():
		_profiles.insert(index, profile) # Roll back the cache so it matches the file.
		_profiles_lock.unlock()
		return false
	_profiles_lock.unlock()

	profiles_updated.emit()

	var profile_dir := AppPaths.PROFILES_DIR.path_join(profile.get("directory_name", ""))
	if DirAccess.dir_exists_absolute(profile_dir):
		if _remove_dir_recursive(profile_dir) != OK:
			printerr("ProfileManager: Failed to fully delete directory: ", profile_dir)

	var background_path: String = profile.get("custom_background_image", "")
	if background_path.begins_with(AppPaths.BACKGROUNDS_DIR) and FileAccess.file_exists(background_path):
		DirAccess.remove_absolute(background_path)

	# If the deleted profile was the shared settings source, clear the configuration
	var deleted_dir: String = profile.get("directory_name", "")
	var current_source_dir: String = ConfigManager.get_value("SharedSettingsSourceDirectory", "")
	var current_source_name: String = ConfigManager.get_value("SharedSettingsSourceProfile", "")
	if (not deleted_dir.is_empty() and deleted_dir == current_source_dir) or current_source_name == profile_name:
		ConfigManager.set_value_and_save("SharedSettingsSourceDirectory", "")
		ConfigManager.set_value_and_save("SharedSettingsSourceProfile", "")
		print("ProfileManager: Cleared Source Profile configuration because profile '%s' was deleted." % profile_name)

	print("ProfileManager: Profile '%s' deleted." % profile_name)
	return true


## Deletes all profiles, clears all profile directories, and deletes custom background images.
## The database file is cleared first; only when that succeeds are directories removed.
func delete_all_profiles() -> bool:
	print("ProfileManager: Deleting all profiles...")
	_profiles_lock.lock()
	var saved: bool = JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": []})
	if not saved:
		_profiles_lock.unlock()
		printerr("ProfileManager: Failed to clear profiles file; aborting deletion.")
		return false
	_profiles.clear()
	_profiles_lock.unlock()

	ConfigManager.set_value_and_save("SharedSettingsSourceDirectory", "")
	ConfigManager.set_value_and_save("SharedSettingsSourceProfile", "")

	if DirAccess.dir_exists_absolute(AppPaths.PROFILES_DIR):
		_remove_dir_contents(AppPaths.PROFILES_DIR)

	if DirAccess.dir_exists_absolute(AppPaths.BACKGROUNDS_DIR):
		_remove_dir_contents(AppPaths.BACKGROUNDS_DIR)

	if DirAccess.dir_exists_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR):
		_remove_dir_contents(AppPaths.SHARED_GAME_SETTINGS_DIR)

	profiles_updated.emit()
	print("ProfileManager: All profiles successfully deleted.")
	return true


func _remove_dir_contents(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := dir_path.path_join(file_name)
			if dir.current_is_dir():
				_remove_dir_recursive(full_path)
			else:
				DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Returns true if the profile has not been opened yet (needs manual login).
func is_first_time_opened(profile_name: String) -> bool:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	var first_time: bool = profile.is_empty() or not profile.get("first_time_opened", false)
	_profiles_lock.unlock()
	return first_time


## Persists that the profile has been launched at least once.
## Silent: does not emit profiles_updated (avoids rebuilding the UI mid-launch).
func mark_profile_opened(profile_name: String) -> void:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	if not profile.is_empty() and not profile.get("first_time_opened", false):
		profile["first_time_opened"] = true
		_save_profiles_file()
	_profiles_lock.unlock()


## Reorders the in-memory profiles list to match ordered_names and saves to disk.
## Silent: does not emit profiles_updated so the caller can manage UI nodes directly without rebuilding the UI.
func reorder_profiles(ordered_names: Array) -> bool:
	_profiles_lock.lock()
	var old_profiles: Array = _profiles.duplicate()

	var name_to_profile: Dictionary = {}
	for profile in _profiles:
		if profile is Dictionary:
			name_to_profile[profile.get("profile_name", "")] = profile

	var new_profiles: Array = []
	for p_name in ordered_names:
		if name_to_profile.has(p_name):
			new_profiles.append(name_to_profile[p_name])
			name_to_profile.erase(p_name)

	# Append any profiles that weren't specified in ordered_names (safety fallback)
	for remaining_profile in name_to_profile.values():
		new_profiles.append(remaining_profile)

	_profiles = new_profiles
	if not _save_profiles_file():
		_profiles = old_profiles
		_profiles_lock.unlock()
		return false
	_profiles_lock.unlock()

	print("ProfileManager: Profiles reordered and saved successfully (%d profiles)." % _profiles.size())
	return true


## Returns the profile dictionary by name, or an empty Dictionary if not found.
func get_profile(profile_name: String) -> Dictionary:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	var result := profile.duplicate() if not profile.is_empty() else {}
	_profiles_lock.unlock()
	return result


## Returns the absolute directory path for a profile, or "" if not found.
func get_profile_dir(profile_name: String) -> String:
	_profiles_lock.lock()
	var result := _get_profile_dir_unsafe(profile_name)
	_profiles_lock.unlock()
	return result


## Back-compat alias for get_profile_dir (used by controllers).
func _get_profile_dir(profile_name: String) -> String:
	_profiles_lock.lock()
	var result := _get_profile_dir_unsafe(profile_name)
	_profiles_lock.unlock()
	return result


## Updates an existing profile's name, background image, and/or directory on disk safely.
## The directory rename is rolled back when the database save fails, so the
## profile data and its session folder can never become detached.
## Emits `profiles_updated` and returns true on success.
func update_profile(
	old_name: String,
	new_name: String,
	new_background_path: String = "",
	rename_directory: bool = true,
	has_custom_name: Variant = null,
	description: String = ""
) -> bool:
	var trimmed_new_name := new_name.strip_edges()
	if trimmed_new_name.is_empty():
		printerr("ProfileManager: New profile name cannot be empty.")
		return false

	_profiles_lock.lock()
	var profile := _find_profile_unsafe(old_name)
	if profile.is_empty():
		_profiles_lock.unlock()
		printerr("ProfileManager: Profile '%s' not found for update." % old_name)
		return false

	# If changing name, ensure new name is unique
	if trimmed_new_name != old_name and not _find_profile_unsafe(trimmed_new_name).is_empty():
		_profiles_lock.unlock()
		printerr("ProfileManager: Profile '%s' already exists." % trimmed_new_name)
		return false

	var old_dir_name: String = profile.get("directory_name", "")
	var target_dir_name := old_dir_name
	var old_bg_path: String = profile.get("custom_background_image", "")
	var old_has_custom: Variant = profile.get("has_custom_name", true)
	var old_description: String = profile.get("description", "")
	var dir_renamed := false

	# 1. Rename directory on disk if requested and name changed
	if rename_directory and trimmed_new_name != old_name:
		var proposed_dir := _sanitize_directory_name(trimmed_new_name)
		if proposed_dir != old_dir_name:
			if not _rename_profile_directory(old_dir_name, proposed_dir):
				_profiles_lock.unlock()
				printerr("ProfileManager: Failed to rename profile directory from '%s' to '%s'." % [old_dir_name, proposed_dir])
				return false
			target_dir_name = proposed_dir
			dir_renamed = true

	# 2. Update name and metadata
	profile["profile_name"] = trimmed_new_name
	profile["directory_name"] = target_dir_name
	if not new_background_path.is_empty() and new_background_path != old_bg_path:
		profile["custom_background_image"] = new_background_path
	if has_custom_name != null:
		profile["has_custom_name"] = bool(has_custom_name)
	profile["description"] = description.strip_edges()

	# 3. Persist profiles_data.json — roll everything back on failure.
	if not _save_profiles_file():
		profile["profile_name"] = old_name
		profile["directory_name"] = old_dir_name
		profile["custom_background_image"] = old_bg_path
		profile["has_custom_name"] = old_has_custom
		profile["description"] = old_description
		if dir_renamed:
			_rename_profile_directory(target_dir_name, old_dir_name)
		_profiles_lock.unlock()
		printerr("ProfileManager: Failed to save profiles file after update.")
		return false
	_profiles_lock.unlock()

	# 4. Post-save side effects (no rollback needed)
	if not new_background_path.is_empty() and new_background_path != old_bg_path:
		_cleanup_orphaned_background(old_bg_path, old_name)

	# 5. Keep configs.json in sync (SharedSettingsSourceDirectory and legacy SharedSettingsSourceProfile)
	var current_source_dir: String = ConfigManager.get_value("SharedSettingsSourceDirectory", "")
	var current_shared_source: String = ConfigManager.get_value("SharedSettingsSourceProfile", "")
	if current_source_dir == old_dir_name or current_shared_source == old_name:
		ConfigManager.set_value_and_save("SharedSettingsSourceDirectory", target_dir_name)
		ConfigManager.set_value_and_save("SharedSettingsSourceProfile", trimmed_new_name)

	profiles_updated.emit()
	print("ProfileManager: Profile '%s' successfully updated to '%s'." % [old_name, trimmed_new_name])
	return true

#endregion

#region Public API — session backup/restore

## Copies the current Riot Client files into the profile's backup folder.
## Each item is copied to a temp location and swapped in only after the full
## copy succeeds, so a failed save never destroys the previous good backup.
## Returns true only if every existing source was copied successfully.
func save_profile_session(profile_name: String, riot_install_dir: String) -> bool:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	var profile_dir := _get_profile_dir_unsafe(profile_name)
	_profiles_lock.unlock()
	if profile.is_empty():
		return false

	# The directory must exist before any copy starts (normalized on load,
	# but keep the guard for profiles created by older versions).
	if not DirAccess.dir_exists_absolute(profile_dir):
		if DirAccess.make_dir_recursive_absolute(profile_dir) != OK:
			printerr("ProfileManager: Failed to create profile directory: ", profile_dir)
			return false

	print("ProfileManager: Saving session for '%s'..." % profile_name)
	var all_success := true
	for file_def in FILES_TO_SWITCH:
		var source_path := _resolve_path(file_def, riot_install_dir)
		if source_path.is_empty():
			continue
		var dest_path := profile_dir.path_join(file_def["filename"])
		if file_def.get("is_dir", false):
			if not DirAccess.dir_exists_absolute(source_path):
				continue
			if _copy_dir_atomic(source_path, dest_path) != OK:
				printerr("ProfileManager: Failed to back up directory '%s'." % file_def["filename"])
				all_success = false
		else:
			if not FileAccess.file_exists(source_path):
				continue
			if _copy_file_atomic(source_path, dest_path) != OK:
				printerr("ProfileManager: Failed to back up '%s'." % file_def["filename"])
				all_success = false
	return all_success


## Writes the profile's backed-up files over the live Riot Client files.
## Files the profile never backed up are removed from the client so no
## stale session data survives. Every replacement is temp-then-rename, so
## a failed restore leaves the live client files intact.
## Returns true only if every restore succeeded.
func restore_profile_session(profile_name: String, riot_install_dir: String) -> bool:
	_profiles_lock.lock()
	var profile := _find_profile_unsafe(profile_name)
	var profile_dir := _get_profile_dir_unsafe(profile_name)
	_profiles_lock.unlock()
	if profile.is_empty():
		return false

	print("ProfileManager: Restoring session for '%s'..." % profile_name)
	var all_success := true
	for file_def in FILES_TO_SWITCH:
		var dest_path := _resolve_path(file_def, riot_install_dir)
		if dest_path.is_empty():
			continue
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		var source_path := profile_dir.path_join(file_def["filename"])
		if file_def.get("is_dir", false):
			if DirAccess.dir_exists_absolute(source_path):
				if _copy_dir_atomic(source_path, dest_path) != OK:
					printerr("ProfileManager: Failed to restore directory '%s'." % file_def["filename"])
					all_success = false
			elif DirAccess.dir_exists_absolute(dest_path):
				if _remove_dir_recursive(dest_path) != OK:
					printerr("ProfileManager: Failed to clear stale directory '%s'." % file_def["filename"])
					all_success = false
		else:
			if FileAccess.file_exists(source_path):
				if _copy_file_atomic(source_path, dest_path) != OK:
					printerr("ProfileManager: Failed to restore '%s'." % file_def["filename"])
					all_success = false
			elif FileAccess.file_exists(dest_path):
				if DirAccess.remove_absolute(dest_path) != OK:
					printerr("ProfileManager: Failed to clear stale file '%s'." % file_def["filename"])
					all_success = false
	return all_success

#endregion

#region Internal helpers — profile database (assumes _profiles_lock is held)

func _find_profile_unsafe(profile_name: String) -> Dictionary:
	for profile: Dictionary in _profiles:
		if profile.get("profile_name") == profile_name:
			return profile
	return {}


func _get_profile_dir_unsafe(profile_name: String) -> String:
	var profile := _find_profile_unsafe(profile_name)
	if profile.is_empty():
		printerr("ProfileManager: Profile '%s' not found." % profile_name)
		return ""
	return AppPaths.PROFILES_DIR.path_join(profile.get("directory_name", ""))


## Fills in missing fields for profiles written by older versions and
## drops invalid entries. Saves the file only when something changed.
func _normalize_profiles() -> void:
	var changed := false
	var normalized: Array = []
	for entry in _profiles:
		if not entry is Dictionary:
			changed = true
			continue
		var profile: Dictionary = entry
		if str(profile.get("directory_name", "")).is_empty():
			profile["directory_name"] = _sanitize_directory_name(str(profile.get("profile_name", "profile")))
			changed = true
		if not profile.has("first_time_opened"):
			profile["first_time_opened"] = false
			changed = true
		if not profile.has("custom_background_image"):
			profile["custom_background_image"] = ""
			changed = true
		if not profile.has("has_custom_name"):
			profile["has_custom_name"] = true
			changed = true
		if not profile.has("description"):
			profile["description"] = ""
			changed = true
		normalized.append(profile)
	if changed:
		_profiles = normalized
		JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": _profiles})
		print("ProfileManager: Normalized profile data (missing fields filled in).")


func _sanitize_directory_name(profile_name: String) -> String:
	var sanitized := profile_name.validate_filename().replace(" ", "_")
	if sanitized.is_empty():
		sanitized = "profile_%d" % Time.get_unix_time_from_system()
	return sanitized


## Returns a directory name based on [param base_name] that neither another
## profile nor an existing on-disk folder already uses.
func _resolve_unique_directory_name(base_name: String) -> String:
	var candidate := base_name
	var suffix := 2
	while _directory_name_in_use(candidate):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1
	return candidate


func _directory_name_in_use(dir_name: String) -> bool:
	for p: Dictionary in _profiles:
		if p.get("directory_name", "") == dir_name:
			return true
	return DirAccess.dir_exists_absolute(AppPaths.PROFILES_DIR.path_join(dir_name))


func _seed_shared_settings_for_new_profile(target_dir: String) -> void:
	var sync_enabled := bool(ConfigManager.get_value("SyncGameSettings", false))
	if not sync_enabled:
		return
	if LeagueSettingsSync.has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
		LeagueSettingsSync.restore_shared_settings_to_dir(target_dir)


func _save_profiles_file() -> bool:
	if JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": _profiles}):
		return true
	printerr("ProfileManager: Failed to save profiles file.")
	return false

#endregion

#region Internal helpers — atomic file/dir copies

## Copies a file to a temp sibling and swaps it into place only after the
## copy fully succeeded. The previous destination survives any failure.
func _copy_file_atomic(source_path: String, dest_path: String) -> Error:
	var tmp_path := dest_path + FILE_TMP_SUFFIX
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path) # Clean up leftovers from an interrupted run.

	if DirAccess.copy_absolute(source_path, tmp_path) != OK:
		printerr("ProfileManager: Failed to copy '%s'." % source_path)
		return FAILED

	if FileAccess.file_exists(dest_path):
		var remove_error := DirAccess.remove_absolute(dest_path)
		if remove_error != OK:
			printerr("ProfileManager: Failed to replace '%s'. Error: %s" % [dest_path, remove_error])
			return remove_error

	var rename_error := _rename_with_retry(tmp_path, dest_path)
	if rename_error != OK:
		# Fallback: plain copy (dest is complete only if the copy finishes).
		if DirAccess.copy_absolute(tmp_path, dest_path) == OK:
			DirAccess.remove_absolute(tmp_path)
			return OK
	return rename_error


## Copies a directory to a temp sibling and swaps it into place only after
## the copy fully succeeded. The previous destination survives any failure.
func _copy_dir_atomic(source_path: String, dest_path: String) -> Error:
	var tmp_path := dest_path + DIR_TMP_SUFFIX
	if DirAccess.dir_exists_absolute(tmp_path):
		_remove_dir_recursive(tmp_path)

	if _copy_dir_recursive(source_path, tmp_path) != OK:
		printerr("ProfileManager: Failed to copy directory '%s'." % source_path)
		_remove_dir_recursive(tmp_path)
		return FAILED

	if DirAccess.dir_exists_absolute(dest_path):
		var remove_error := _remove_dir_recursive(dest_path)
		if remove_error != OK:
			printerr("ProfileManager: Failed to replace directory '%s'." % dest_path)
			return remove_error

	var rename_error := _rename_with_retry(tmp_path, dest_path)
	if rename_error != OK:
		if _copy_dir_recursive(tmp_path, dest_path) == OK:
			_remove_dir_recursive(tmp_path)
			return OK
	return rename_error


func _rename_with_retry(old_path: String, new_path: String) -> Error:
	for attempt in 3:
		var err := DirAccess.rename_absolute(old_path, new_path)
		if err == OK:
			return OK
		OS.delay_msec(100)
	printerr("ProfileManager: Rename '%s' -> '%s' failed after retries." % [old_path, new_path])
	return FAILED


## Resolves a FILES_TO_SWITCH entry to an absolute path, or "" when its
## base directory is unavailable.
func _resolve_path(file_def: Dictionary, riot_install_dir: String) -> String:
	match file_def["base"]:
		"local_app_data":
			var local_app_data := OS.get_environment("LOCALAPPDATA")
			if local_app_data.is_empty():
				return ""
			return local_app_data.path_join(file_def["rel_path"])
		"install_dir":
			if riot_install_dir.is_empty():
				return ""
			return riot_install_dir.path_join(file_def["rel_path"])
	return ""


func _copy_dir_recursive(source_path: String, dest_path: String) -> Error:
	var dir := DirAccess.open(source_path)
	if not dir:
		return DirAccess.get_open_error()

	var err := DirAccess.make_dir_recursive_absolute(dest_path)
	if err != OK:
		return err

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var source_full := source_path.path_join(entry)
			var dest_full := dest_path.path_join(entry)
			var sub_err: Error = _copy_dir_recursive(source_full, dest_full) if dir.current_is_dir() else DirAccess.copy_absolute(source_full, dest_full)
			if sub_err != OK:
				dir.list_dir_end()
				return sub_err
		entry = dir.get_next()
	dir.list_dir_end()
	return OK


func _remove_dir_recursive(path: String) -> Error:
	var dir := DirAccess.open(path)
	if not dir:
		return OK if not DirAccess.dir_exists_absolute(path) else DirAccess.get_open_error()

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			var err: Error = _remove_dir_recursive(entry_path) if dir.current_is_dir() else DirAccess.remove_absolute(entry_path)
			if err != OK:
				dir.list_dir_end()
				printerr("ProfileManager: Failed to remove '%s'. Error: %s" % [entry_path, err])
				return err
		entry = dir.get_next()
	dir.list_dir_end()

	# Retry the final removal: the OS can hold a brief lock on the directory.
	for attempt in 3:
		var err := DirAccess.remove_absolute(path)
		if err == OK or not DirAccess.dir_exists_absolute(path):
			return OK
		OS.delay_msec(100)

	printerr("ProfileManager: Failed to remove directory '%s' after retries." % path)
	return FAILED


## Windows-safe directory rename with retry loop and recursive copy/delete fallback.
func _rename_profile_directory(old_dir_name: String, new_dir_name: String) -> bool:
	if old_dir_name.is_empty() or new_dir_name.is_empty() or old_dir_name == new_dir_name:
		return true

	var old_path := AppPaths.PROFILES_DIR.path_join(old_dir_name)
	var new_path := AppPaths.PROFILES_DIR.path_join(new_dir_name)

	# If old directory doesn't exist yet, simply create the new one
	if not DirAccess.dir_exists_absolute(old_path):
		return DirAccess.make_dir_recursive_absolute(new_path) == OK

	# If destination already exists unexpectedly, abort to prevent overwriting
	if DirAccess.dir_exists_absolute(new_path):
		printerr("ProfileManager: Target directory '%s' already exists." % new_path)
		return false

	# Attempt atomic rename with retry (handles transient OS locks)
	for attempt in 3:
		var err := DirAccess.rename_absolute(old_path, new_path)
		if err == OK:
			return true
		OS.delay_msec(100)

	# Fallback: recursive copy + recursive delete
	print("ProfileManager: Atomic rename failed; falling back to recursive copy/delete for '%s' -> '%s'..." % [old_dir_name, new_dir_name])
	if _copy_dir_recursive(old_path, new_path) == OK:
		_remove_dir_recursive(old_path)
		return true

	# If copy failed, clean up any partial target folder
	if DirAccess.dir_exists_absolute(new_path):
		_remove_dir_recursive(new_path)
	return false


## Removes old custom background if no other profile references it.
func _cleanup_orphaned_background(old_bg_path: String, excluding_profile_name: String) -> void:
	if not old_bg_path.begins_with(AppPaths.BACKGROUNDS_DIR) or not FileAccess.file_exists(old_bg_path):
		return

	for p: Dictionary in _profiles:
		if p.get("profile_name") != excluding_profile_name and p.get("custom_background_image") == old_bg_path:
			return # Still in use by another profile

	DirAccess.remove_absolute(old_bg_path)

#endregion
