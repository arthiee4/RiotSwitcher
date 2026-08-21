extends Node

## Owns the profile database (user://data/profiles_data.json) and the
## per-profile backup of Riot Client files (user://profiles/<dir>/).
##
## Session save/restore only touches the filesystem; killing processes and
## orchestration belong to the caller (ProfileGridController).

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

var _profiles: Array = []


#region Public API — profile database

## Loads profiles from disk into the cache and notifies listeners.
func load_profiles_data() -> Array:
	var data = JsonFile.load_data(AppPaths.PROFILES_FILE)
	if data is Dictionary and data.get("profiles") is Array:
		_profiles = data["profiles"]
	else:
		_profiles = []
		JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": []})
	profiles_updated.emit()
	print("ProfileManager: %d profile(s) loaded." % _profiles.size())
	return _profiles


func get_profiles() -> Array:
	return _profiles


func get_profile_count() -> int:
	return _profiles.size()


func has_profile(profile_name: String) -> bool:
	return not _find_profile(profile_name).is_empty()


## Creates the profile directory and registers the profile. Returns true on success.
func add_profile(profile_name: String, background_path: String, has_custom_name: bool = true) -> bool:
	if profile_name.is_empty():
		printerr("ProfileManager: Profile name cannot be empty.")
		return false
	if has_profile(profile_name):
		printerr("ProfileManager: Profile '%s' already exists." % profile_name)
		return false

	var directory_name := _sanitize_directory_name(profile_name)
	var profile_dir := AppPaths.PROFILES_DIR.path_join(directory_name)
	if DirAccess.make_dir_recursive_absolute(profile_dir) != OK:
		printerr("ProfileManager: Failed to create profile directory: ", profile_dir)
		return false

	# Seed the newly created profile folder with shared game settings if enabled
	_seed_shared_settings_for_new_profile(profile_dir)

	var new_profile := {
		"profile_name": profile_name,
		"custom_background_image": background_path,
		"first_time_opened": false,
		"directory_name": directory_name,
		"has_custom_name": has_custom_name,
	}
	_profiles.append(new_profile)
	if not _save_profiles_file():
		_profiles.erase(new_profile)
		return false

	profiles_updated.emit()
	print("ProfileManager: Profile '%s' added." % profile_name)
	return true


## Removes the profile from the database and deletes its files. Returns true on success.
func delete_profile(profile_name: String) -> bool:
	var profile := _find_profile(profile_name)
	if profile.is_empty():
		printerr("ProfileManager: Profile '%s' not found." % profile_name)
		return false

	_profiles.erase(profile)
	if not _save_profiles_file():
		_profiles.append(profile) # Roll back the cache so it matches the file.
		return false

	profiles_updated.emit()

	var profile_dir := AppPaths.PROFILES_DIR.path_join(profile.get("directory_name", ""))
	if DirAccess.dir_exists_absolute(profile_dir):
		if _remove_dir_recursive(profile_dir) != OK:
			printerr("ProfileManager: Failed to fully delete directory: ", profile_dir)

	var background_path: String = profile.get("custom_background_image", "")
	if background_path.begins_with(AppPaths.BACKGROUNDS_DIR) and FileAccess.file_exists(background_path):
		DirAccess.remove_absolute(background_path)

	print("ProfileManager: Profile '%s' deleted." % profile_name)
	return true


## Deletes all profiles, clears all profile directories, and deletes custom background images.
func delete_all_profiles() -> bool:
	print("ProfileManager: Deleting all profiles...")
	_profiles.clear()
	_save_profiles_file()

	if DirAccess.dir_exists_absolute(AppPaths.PROFILES_DIR):
		_remove_dir_contents(AppPaths.PROFILES_DIR)

	if DirAccess.dir_exists_absolute(AppPaths.BACKGROUNDS_DIR):
		_remove_dir_contents(AppPaths.BACKGROUNDS_DIR)

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
	var profile := _find_profile(profile_name)
	if profile.is_empty():
		return true
	return not profile.get("first_time_opened", false)


## Persists that the profile has been launched at least once.
## Silent: does not emit profiles_updated (avoids rebuilding the UI mid-launch).
func mark_profile_opened(profile_name: String) -> void:
	var profile := _find_profile(profile_name)
	if profile.is_empty() or profile.get("first_time_opened", false):
		return
	profile["first_time_opened"] = true
	_save_profiles_file()


## Reorders the in-memory profiles list to match ordered_names and saves to disk.
## Silent: does not emit profiles_updated so the caller can manage UI nodes directly without rebuilding the UI.
func reorder_profiles(ordered_names: Array) -> bool:
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
	var saved := _save_profiles_file()
	if saved:
		print("ProfileManager: Profiles reordered and saved successfully (%d profiles)." % _profiles.size())
	return saved


## Returns the profile dictionary by name, or an empty Dictionary if not found.
func get_profile(profile_name: String) -> Dictionary:
	return _find_profile(profile_name)


## Returns the absolute directory path for a profile, or "" if not found.
func get_profile_dir(profile_name: String) -> String:
	return _get_profile_dir(profile_name)


## Updates an existing profile's name, background image, and/or directory on disk safely.
## Emits `profiles_updated` and returns true on success.
func update_profile(
	old_name: String,
	new_name: String,
	new_background_path: String = "",
	rename_directory: bool = true,
	has_custom_name: Variant = null
) -> bool:
	var profile := _find_profile(old_name)
	if profile.is_empty():
		printerr("ProfileManager: Profile '%s' not found for update." % old_name)
		return false

	var trimmed_new_name := new_name.strip_edges()
	if trimmed_new_name.is_empty():
		printerr("ProfileManager: New profile name cannot be empty.")
		return false

	# If changing name, ensure new name is unique
	if trimmed_new_name != old_name and has_profile(trimmed_new_name):
		printerr("ProfileManager: Profile '%s' already exists." % trimmed_new_name)
		return false

	var old_dir_name: String = profile.get("directory_name", "")
	var target_dir_name := old_dir_name
	var old_bg_path: String = profile.get("custom_background_image", "")

	# 1. Rename directory on disk if requested and name changed
	if rename_directory and trimmed_new_name != old_name:
		var proposed_dir := _sanitize_directory_name(trimmed_new_name)
		if proposed_dir != old_dir_name:
			if not _rename_profile_directory(old_dir_name, proposed_dir):
				printerr("ProfileManager: Failed to rename profile directory from '%s' to '%s'." % [old_dir_name, proposed_dir])
				return false
			target_dir_name = proposed_dir

	# 2. Update background image & clean up orphaned old custom background
	if not new_background_path.is_empty() and new_background_path != old_bg_path:
		_cleanup_orphaned_background(old_bg_path, old_name)
		profile["custom_background_image"] = new_background_path

	# 3. Update name and metadata
	profile["profile_name"] = trimmed_new_name
	profile["directory_name"] = target_dir_name
	if has_custom_name != null:
		profile["has_custom_name"] = bool(has_custom_name)

	# 4. Keep configs.json in sync (SharedSettingsSourceProfile)
	var current_shared_source: String = ConfigManager.get_value("SharedSettingsSourceProfile", "")
	if current_shared_source == old_name:
		ConfigManager.set_value_and_save("SharedSettingsSourceProfile", trimmed_new_name)

	# 5. Persist profiles_data.json
	if not _save_profiles_file():
		printerr("ProfileManager: Failed to save profiles file after update.")
		return false

	profiles_updated.emit()
	print("ProfileManager: Profile '%s' successfully updated to '%s'." % [old_name, trimmed_new_name])
	return true

#endregion

#region Public API — session backup/restore

## Copies the current Riot Client files into the profile's backup folder.
## Returns true only if every existing source was copied successfully.
func save_profile_session(profile_name: String, riot_install_dir: String) -> bool:
	var profile_dir := _get_profile_dir(profile_name)
	if profile_dir.is_empty():
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
			if DirAccess.dir_exists_absolute(dest_path):
				_remove_dir_recursive(dest_path)
			if _copy_dir_recursive(source_path, dest_path) != OK:
				printerr("ProfileManager: Failed to back up directory '%s'." % file_def["filename"])
				all_success = false
		else:
			if not FileAccess.file_exists(source_path):
				continue
			if DirAccess.copy_absolute(source_path, dest_path) != OK:
				printerr("ProfileManager: Failed to back up '%s'." % file_def["filename"])
				all_success = false
	return all_success


## Writes the profile's backed-up files over the live Riot Client files.
## Files the profile never backed up are removed from the client so no
## stale session data survives. Returns true only if every restore succeeded.
func restore_profile_session(profile_name: String, riot_install_dir: String) -> bool:
	var profile_dir := _get_profile_dir(profile_name)
	if profile_dir.is_empty():
		return false

	print("ProfileManager: Restoring session for '%s'..." % profile_name)
	var all_success := true
	for file_def in FILES_TO_SWITCH:
		var dest_path := _resolve_path(file_def, riot_install_dir)
		if dest_path.is_empty():
			continue
		var source_path := profile_dir.path_join(file_def["filename"])
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		if file_def.get("is_dir", false):
			if DirAccess.dir_exists_absolute(dest_path):
				_remove_dir_recursive(dest_path)
			if DirAccess.dir_exists_absolute(source_path):
				if _copy_dir_recursive(source_path, dest_path) != OK:
					printerr("ProfileManager: Failed to restore directory '%s'." % file_def["filename"])
					all_success = false
		else:
			if FileAccess.file_exists(source_path):
				if DirAccess.copy_absolute(source_path, dest_path) != OK:
					printerr("ProfileManager: Failed to restore '%s'." % file_def["filename"])
					all_success = false
			elif FileAccess.file_exists(dest_path):
				DirAccess.remove_absolute(dest_path)
	return all_success

#endregion

#region Internal helpers

func _find_profile(profile_name: String) -> Dictionary:
	for profile: Dictionary in _profiles:
		if profile.get("profile_name") == profile_name:
			return profile
	return {}


func _get_profile_dir(profile_name: String) -> String:
	var profile := _find_profile(profile_name)
	if profile.is_empty():
		printerr("ProfileManager: Profile '%s' not found." % profile_name)
		return ""
	return AppPaths.PROFILES_DIR.path_join(profile.get("directory_name", ""))


func _sanitize_directory_name(profile_name: String) -> String:
	var sanitized := profile_name.validate_filename().replace(" ", "_")
	if sanitized.is_empty():
		sanitized = "profile_%d" % Time.get_unix_time_from_system()
	return sanitized


func _seed_shared_settings_for_new_profile(target_dir: String) -> void:
	var sync_enabled := bool(ConfigManager.get_value("SyncGameSettings", false))
	if not sync_enabled:
		return
	LeagueSettingsSync.restore_shared_settings_to_dir(target_dir)


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


func _save_profiles_file() -> bool:
	if JsonFile.save_data(AppPaths.PROFILES_FILE, {"profiles": _profiles}):
		return true
	printerr("ProfileManager: Failed to save profiles file.")
	return false


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
