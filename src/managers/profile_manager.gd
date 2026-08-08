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

#endregion
