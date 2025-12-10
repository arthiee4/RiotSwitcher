extends Node # Or just RefCounted if no node features needed

const PROFILES_PATH = "res://Data/profiles_data.json"
const PROFILE_DIR_BASE = "user://profiles/"
const CUSTOM_BG_DIR = "user://UserBackground/" # Needed for deleting associated background

const FILES_TO_SWITCH = [
	{
		"id": "private_settings",
		"filename": "RiotGamesPrivateSettings.yaml",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Data/RiotGamesPrivateSettings.yaml"
	},
	{
		"id": "sessions_dir",
		"filename": "Sessions",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Data/Sessions",
		"is_dir": true
	},
	{
		"id": "riot_client_settings",
		"filename": "RiotClientSettings.yaml",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Config/RiotClientSettings.yaml"
	},
	{
		"id": "lockfile",
		"filename": "lockfile",
		"base": "local_app_data",
		"rel_path": "Riot Games/Riot Client/Config/lockfile"
	},
	{
		"id": "client_config",
		"filename": "client.config.yaml",
		"base": "install_dir",
		"rel_path": "Config/client.config.yaml"
	},
	{
		"id": "client_settings",
		"filename": "client.settings.yaml",
		"base": "install_dir",
		"rel_path": "Config/client.settings.yaml"
	}
]

signal profiles_updated # Emitted after load, add, delete

# Maybe keep a local copy of profile data to avoid repeated file reads
var _profiles_data: Array = [] # Array of profile Dictionaries

func _ready():
	# Optionally load profiles on ready if this node is in the scene tree
	# load_profiles_data() 
	pass # Avoid loading automatically if instantiated manually

# --- Public API ---

# Loads profile data from JSON and updates the internal cache.
# Returns the loaded array.
func load_profiles_data() -> Array:
	var data = _load_json_data(PROFILES_PATH)
	if data and data.has("profiles") and data["profiles"] is Array:
		_profiles_data = data["profiles"]
		print("ProfileManager: Loaded %d profiles." % _profiles_data.size())
	else:
		_profiles_data = []
		# Create the file with an empty structure if it doesn't exist or is invalid
		if data == null or not (data is Dictionary and data.has("profiles")):
			print("ProfileManager: No profiles found or invalid format. Creating/resetting file.")
			_save_json_data(PROFILES_PATH, {"profiles": []})
		else:
			print("ProfileManager: No profiles found in existing file.")
	emit_signal("profiles_updated")
	return _profiles_data

# Returns the currently cached profile data.
func get_profiles() -> Array:
	return _profiles_data

# Returns the count of currently cached profiles.
func get_profile_count() -> int:
	return _profiles_data.size()

# Adds a new profile: creates directory, saves data to JSON, updates cache.
# Returns true on success, false on failure.
func add_profile(profile_name: String, background_path: String) -> bool:
	print("[ProfileManager] Attempting to add profile: ", profile_name)
	if profile_name.is_empty():
		printerr("ProfileManager: Profile name cannot be empty.")
		return false
		
	# Check for duplicate profile names before proceeding
	for p in _profiles_data:
		if p.get("profile_name") == profile_name:
			printerr("ProfileManager: Profile with name '%s' already exists." % profile_name)
			return false

	# 1. Create profile directory
	var sanitized_profile_name = profile_name.validate_filename().replace(" ", "_")
	print("[ProfileManager] Sanitized profile name: ", sanitized_profile_name)
	if sanitized_profile_name.is_empty():
		sanitized_profile_name = "profile_" + str(Time.get_unix_time_from_system())
		print("ProfileManager: Sanitized profile name was empty, using fallback: ", sanitized_profile_name)
		
	var profile_dir_path = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
	print("[ProfileManager] Attempting to create directory at: ", profile_dir_path)
	var err = DirAccess.make_dir_recursive_absolute(profile_dir_path)
	print("[ProfileManager] DirAccess.make_dir_recursive_absolute result code: ", err, " (OK = 0)")
	if err != OK:
		printerr("ProfileManager: Failed to create profile directory: ", profile_dir_path, ". Error Code: ", err)
		return false

	print("[ProfileManager] Directory should be created successfully.")
	# 2. Prepare data
	var new_profile_data = {
		"profile_name": profile_name,
		"custom_background_image": background_path, # Path provided by caller
		"first_time_opened": false, # Default value
		"directory_name": sanitized_profile_name # Store for easier lookup
	}

	# 3. Append to JSON
	if not _append_to_json_array(PROFILES_PATH, "profiles", new_profile_data):
		printerr("ProfileManager: Failed to save profile data to JSON!")
		# Attempt to clean up created directory? Optional, could leave empty dir.
		# _remove_dir_recursive(profile_dir_path) 
		return false

	# 4. Update internal cache and notify
	_profiles_data.append(new_profile_data) # Update cache directly
	emit_signal("profiles_updated")
	print("ProfileManager: Added profile '%s' with directory '%s'" % [profile_name, sanitized_profile_name])
	return true

# Deletes a profile: removes from JSON, deletes directory and custom bg, updates cache.
# Returns true if the deletion process was successful (JSON updated), false otherwise.
func delete_profile(profile_name_to_delete: String) -> bool:
	var profile_found_in_json = false
	var custom_bg_path_to_delete = ""
	var sanitized_profile_name = ""
	var data = _load_json_data(PROFILES_PATH) # Reload fresh data for deletion robustness

	if not data or not data.has("profiles") or not data["profiles"] is Array:
		printerr("ProfileManager: Could not load, parse, or find 'profiles' array in JSON for deletion.")
		return false # JSON issue

	var profiles_array = data["profiles"]
	var original_size = profiles_array.size()

	for i in range(profiles_array.size() - 1, -1, -1): # Iterate backwards for safe removal
		var profile_entry = profiles_array[i]
		if profile_entry is Dictionary and profile_entry.get("profile_name") == profile_name_to_delete:
			var bg_path = profile_entry.get("custom_background_image", "")
			# Only mark user-specific backgrounds for deletion
			if bg_path.begins_with(CUSTOM_BG_DIR):
				custom_bg_path_to_delete = bg_path
			
			# Get sanitized name from entry if available, otherwise generate it
			sanitized_profile_name = profile_entry.get("directory_name",
				profile_name_to_delete.validate_filename().replace(" ", "_"))
			
			profiles_array.remove_at(i)
			profile_found_in_json = true
			print("ProfileManager: Found profile '%s' in JSON for deletion." % profile_name_to_delete)
			break # Assume unique names, stop searching
	
	if not profile_found_in_json:
		printerr("ProfileManager: Profile '%s' not found in JSON data for deletion." % profile_name_to_delete)
		return false # Profile not found is a failure condition for deletion

	# --- Save updated JSON ---
	if not _save_json_data(PROFILES_PATH, data):
		printerr("ProfileManager: CRITICAL - Failed to save JSON after removing profile entry for '%s'!" % profile_name_to_delete)
		return false # Do not proceed with file deletion if JSON save failed

	print("ProfileManager: Successfully saved JSON after removing profile entry for '%s'." % profile_name_to_delete)
	
	# --- Update internal cache and notify ---
	# Instead of full reload, just remove from local cache if found (more efficient)
	var deleted_from_cache = false
	for i in range(_profiles_data.size() - 1, -1, -1):
		if _profiles_data[i].get("profile_name") == profile_name_to_delete:
			_profiles_data.remove_at(i)
			deleted_from_cache = true
			break
	if deleted_from_cache:
		emit_signal("profiles_updated")
	else:
		 # This case should ideally not happen if JSON save was successful
		printerr("ProfileManager: Profile '%s' was removed from JSON but not found in cache. Resyncing." % profile_name_to_delete)
		load_profiles_data() # Force resync if inconsistency detected


	# --- Delete Files/Dirs (Proceed even if some sub-steps fail, log errors) ---
	var deletion_errors = false

	# Delete Profile Directory
	if not sanitized_profile_name.is_empty():
		var profile_dir_path = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
		if DirAccess.dir_exists_absolute(profile_dir_path):
			print("ProfileManager: Attempting to delete directory: ", profile_dir_path)
			var remove_err = _remove_dir_recursive(profile_dir_path)
			if remove_err != OK:
				printerr("ProfileManager: Failed to recursively delete profile directory '%s'. Error: %s" % [profile_dir_path, remove_err])
				deletion_errors = true
			else:
				print("ProfileManager: Successfully deleted profile directory: ", profile_dir_path)
		else:
			print("ProfileManager: Profile directory not found for deletion (already gone?): ", profile_dir_path)
	else:
		printerr("ProfileManager: Cannot delete profile directory: Invalid or missing sanitized name for '%s'" % profile_name_to_delete)
		deletion_errors = true # Treat missing name as error


	# Delete Custom Background Image
	if not custom_bg_path_to_delete.is_empty():
		if FileAccess.file_exists(custom_bg_path_to_delete):
			print("ProfileManager: Attempting to delete custom background: ", custom_bg_path_to_delete)
			var remove_err = DirAccess.remove_absolute(custom_bg_path_to_delete)
			if remove_err == OK:
				print("ProfileManager: Successfully deleted custom background image: ", custom_bg_path_to_delete)
			else:
				printerr("ProfileManager: Failed to delete custom background image '%s'. Error: %s" % [custom_bg_path_to_delete, remove_err])
				deletion_errors = true # Log error, but don't stop
		else:
			print("ProfileManager: Custom background image not found for deletion (already gone?): ", custom_bg_path_to_delete)
			
	if deletion_errors:
		print("ProfileManager: Deletion process for '%s' completed with errors (see logs)." % profile_name_to_delete)
	else:
		print("ProfileManager: Deletion process for '%s' completed successfully." % profile_name_to_delete)
		
	# Return true because JSON was updated, even if file cleanup had issues
	return true

# Kills Riot Client processes to ensure files can be swapped safely.
func kill_riot_processes() -> void:
	print("ProfileManager: Killing Riot Client processes...")
	OS.execute("taskkill", ["/F", "/IM", "RiotClientServices.exe", "/T"])
	OS.execute("taskkill", ["/F", "/IM", "LeagueClient.exe", "/T"])
	OS.execute("taskkill", ["/F", "/IM", "Valorant.exe", "/T"])
	OS.delay_msec(500)

# Saves the current environment settings/credentials to the profile.
func save_profile(profile_name: String, riot_install_dir: String) -> bool:
	var profile_entry = null
	for p in _profiles_data:
		if p.get("profile_name") == profile_name:
			profile_entry = p
			break
			
	if not profile_entry:
		printerr("ProfileManager: Cannot save profile, not found: ", profile_name)
		return false

	var sanitized_profile_name = profile_entry.get("directory_name")
	if not sanitized_profile_name: return false
	
	var profile_dir = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
	var local_app_data = OS.get_environment("LOCALAPPDATA")
	
	print("ProfileManager: Saving profile data for '%s'..." % profile_name)
	
	var all_success = true
	
	for file_def in FILES_TO_SWITCH:
		var source_path = ""
		if file_def["base"] == "local_app_data":
			if local_app_data.is_empty(): continue
			source_path = local_app_data.path_join(file_def["rel_path"])
		elif file_def["base"] == "install_dir":
			if riot_install_dir.is_empty(): continue
			source_path = riot_install_dir.path_join(file_def["rel_path"])
			
		var dest_path = profile_dir.path_join(file_def["filename"])
		var is_dir = file_def.get("is_dir", false)
		
		if is_dir:
			if DirAccess.dir_exists_absolute(source_path):
				# For directories, we remove the old backup first to ensure clean state
				if DirAccess.dir_exists_absolute(dest_path):
					_remove_dir_recursive(dest_path)
					
				var copy_err = _copy_dir_recursive(source_path, dest_path)
				if copy_err != OK:
					printerr("ProfileManager: Failed to backup directory '%s' to '%s'. Error: %s" % [file_def["filename"], dest_path, copy_err])
					all_success = false
				else:
					print("ProfileManager: Backed up directory '%s'." % file_def["filename"])
			else:
				print("ProfileManager: Source directory '%s' not found (%s), skipping backup." % [file_def["filename"], source_path])
				
		else:
			if FileAccess.file_exists(source_path):
				var copy_err = DirAccess.copy_absolute(source_path, dest_path)
				if copy_err != OK:
					printerr("ProfileManager: Failed to backup '%s' to '%s'. Error: %s" % [file_def["filename"], dest_path, copy_err])
					all_success = false
				else:
					print("ProfileManager: Backed up '%s'." % file_def["filename"])
			else:
				print("ProfileManager: Source file '%s' not found (%s), skipping backup." % [file_def["filename"], source_path])
			
	return all_success

# Restores saved settings from the profile directory, or deletes current Riot settings if none saved.
# Returns true if the operation (restore or delete) was successful, false otherwise.
# Restores the profile settings, overwriting the environment.
func restore_profile(profile_name: String, riot_install_dir: String) -> bool:
	kill_riot_processes()

	var profile_entry = null
	for p in _profiles_data:
		if p.get("profile_name") == profile_name:
			profile_entry = p
			break
			
	if not profile_entry: return false
	
	var sanitized_profile_name = profile_entry.get("directory_name")
	var profile_dir = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
	var local_app_data = OS.get_environment("LOCALAPPDATA")
	
	print("ProfileManager: Restoring profile data for '%s'..." % profile_name)
	
	for file_def in FILES_TO_SWITCH:
		var dest_base = ""
		if file_def["base"] == "local_app_data":
			dest_base = local_app_data
		elif file_def["base"] == "install_dir":
			dest_base = riot_install_dir
			
		if dest_base.is_empty(): continue
		
		var dest_path = dest_base.path_join(file_def["rel_path"])
		var source_path = profile_dir.path_join(file_def["filename"])
		var is_dir = file_def.get("is_dir", false)
		
		# Ensure parent dir exists
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		
		if is_dir:
			if DirAccess.dir_exists_absolute(source_path):
				# Remove existing destination directory to avoid mixing old/new sessions
				if DirAccess.dir_exists_absolute(dest_path):
					_remove_dir_recursive(dest_path)
				
				var copy_err = _copy_dir_recursive(source_path, dest_path)
				if copy_err != OK:
					printerr("ProfileManager: Failed to restore directory '%s' to '%s'. Error: %s" % [file_def["filename"], dest_path, copy_err])
				else:
					print("ProfileManager: Restored directory '%s'." % file_def["filename"])
			else:
				# Profile missing this dir, remove from env to be safe?
				if DirAccess.dir_exists_absolute(dest_path):
					print("ProfileManager: Profile misses '%s', removing existing one from client." % file_def["filename"])
					_remove_dir_recursive(dest_path)
		else:
			if FileAccess.file_exists(source_path):
				var copy_err = DirAccess.copy_absolute(source_path, dest_path)
				if copy_err != OK:
					printerr("ProfileManager: Failed to restore '%s' to '%s'. Error: %s" % [file_def["filename"], dest_path, copy_err])
				else:
					print("ProfileManager: Restored '%s'." % file_def["filename"])
			else:
				if FileAccess.file_exists(dest_path):
					print("ProfileManager: Profile misses '%s', removing existing one from client." % file_def["filename"])
					DirAccess.remove_absolute(dest_path)
				
	return true

# Helper to recursively copy a directory
func _copy_dir_recursive(source_path: String, dest_path: String) -> Error:
	var dir = DirAccess.open(source_path)
	if not dir:
		return DirAccess.get_open_error()
		
	var err = DirAccess.make_dir_recursive_absolute(dest_path)
	if err != OK: return err
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var src_full = source_path.path_join(file_name)
			var dest_full = dest_path.path_join(file_name)
			
			if dir.current_is_dir():
				var sub_err = _copy_dir_recursive(src_full, dest_full)
				if sub_err != OK: return sub_err
			else:
				var sub_err = DirAccess.copy_absolute(src_full, dest_full)
				if sub_err != OK: return sub_err
				
		file_name = dir.get_next()
		
	return OK


# --- Internal Helpers (Copied & adapted from main.gd) ---

# Utility to load and parse JSON data from a file.
# Returns the parsed data (usually a Dictionary) or null on error.
func _load_json_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		# Don't treat as error, might be first run. Return null.
		#print("ProfileManager: JSON file not found at: ", path) 
		return null
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("ProfileManager: Could not open JSON file for reading: ", path, " Error: ", FileAccess.get_open_error())
		return null
		
	var json_string = file.get_as_text()
	# Close file immediately after reading
	# file.close() # Not needed in Godot 4 for FileAccess.open

	if json_string.is_empty() and FileAccess.get_open_error() == OK:
		# File exists but is empty, return an empty dictionary or null?
		# Returning null signals potential issue or first run better.
		#print("ProfileManager: JSON file is empty: ", path)
		return null

	var json_parser = JSON.new()
	var error = json_parser.parse(json_string)
	if error != OK:
		printerr("ProfileManager: Error parsing JSON (code: %s) in %s: %s at line %s" %
			[error, path.get_file(), json_parser.get_error_message(), json_parser.get_error_line()])
		return null
		
	return json_parser.get_data()

# Utility to save data to a JSON file.
# Returns true on success, false on failure.
func _save_json_data(path: String, data: Variant) -> bool:
	var json_string = JSON.stringify(data, "\t") # Use tabs for indentation
	
	# Ensure directory exists before writing
	var dir_path = path.get_base_dir()
	var dir_err = DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_err != OK:
		printerr("ProfileManager: Failed to ensure directory exists for saving JSON: '%s'. Error: %s" % [dir_path, dir_err])
		return false
		
	var save_file = FileAccess.open(path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(json_string)
		# save_file.close() # Not needed in Godot 4
		if FileAccess.get_open_error() == OK:
			 #print("ProfileManager: JSON data saved successfully to: ", path) 
			return true
		else:
			printerr("ProfileManager: Error writing JSON data to '%s'. Error code: %s" % [path, FileAccess.get_open_error()])
			return false
	else:
		printerr("ProfileManager: Error opening JSON file for writing: '%s'. Error code: %s" % [path, FileAccess.get_open_error()])
		return false

# Utility to append a value to an array within a JSON file.
# Assumes the root of the JSON is a Dictionary.
# Returns true on success, false on failure.
func _append_to_json_array(path: String, array_key: String, new_value) -> bool:
	var data = _load_json_data(path)
	
	# If file didn't exist or was invalid/empty, start fresh
	if data == null: data = {}
	
	# Ensure data is a dictionary
	if not data is Dictionary:
		printerr("ProfileManager: Cannot append to JSON array: Root is not a Dictionary in ", path)
		# Overwrite with a valid structure? Or just fail? Failing is safer.
		return false
		
	# Ensure the target key exists and is an array
	if not data.has(array_key) or not data[array_key] is Array:
		# If key exists but isn't array, log error? Overwrite?
		# Overwriting is simpler for this use case.
		#if data.has(array_key): 
		#    printerr("ProfileManager: Overwriting non-array value at key '%s' in %s" % [array_key, path])
		data[array_key] = [] # Create/reset the array
		
	data[array_key].append(new_value)
	
	return _save_json_data(path, data)

# Recursively removes a directory and all its contents.
# Returns OK on success, or the first Error code encountered.
func _remove_dir_recursive(path: String) -> Error:
	var dir = DirAccess.open(path)
	if not dir:
		# If the directory doesn't exist, it's already "removed".
		if not DirAccess.dir_exists_absolute(path):
			 #print("ProfileManager: Recursive remove: Directory already gone: ", path)
			return OK
		printerr("ProfileManager: Recursive remove: Could not open directory: ", path, ". Error: ", DirAccess.get_open_error())
		return DirAccess.get_open_error()

	#print("ProfileManager: Recursive remove: Processing directory: ", path)
	var error: Error = OK # Track errors within the loop

	var current_item = dir.get_next()
	while current_item != "":
		if current_item == "." or current_item == "..":
			current_item = dir.get_next()
			continue

		var item_path = path.path_join(current_item)
		
		if dir.current_is_dir():
			#print("ProfileManager: Recursive remove: Entering subdirectory: ", item_path)
			error = _remove_dir_recursive(item_path)
		else:
			#print("ProfileManager: Recursive remove: Removing file: ", item_path)
			error = DirAccess.remove_absolute(item_path)
			# Optional short delay after file removal, maybe helps with OS locks?
			# if error == OK: OS.delay_msec(5) 

		if error != OK:
			printerr("ProfileManager: Recursive remove: Failed to remove item '%s'. Error: %s" % [item_path, error])
			# dir = null # Ensure DirAccess object is released before returning
			return error # Stop and return the first error encountered

		current_item = dir.get_next()

	# Finished iterating contents, release handle before removing the directory itself
	dir = null

	# Attempt to remove the now-empty directory with retries
	var max_retries = 3
	var retry_delay_ms = 100
	var final_remove_err: Error = FAILED

	for i in range(max_retries):
		final_remove_err = DirAccess.remove_absolute(path)
		if final_remove_err == OK:
			#print("ProfileManager: Recursive remove: Successfully removed final directory: ", path)
			break # Success
		elif not DirAccess.dir_exists_absolute(path):
			#print("ProfileManager: Recursive remove: Final directory disappeared before removal: ", path)
			final_remove_err = OK # Consider it success
			break
		else:
			printerr("ProfileManager: Recursive remove: Attempt %s failed to remove final directory '%s'. Error: %s" % [i + 1, path, final_remove_err])
			if i < max_retries - 1: # Don't delay after the last attempt
				OS.delay_msec(retry_delay_ms)

	if final_remove_err != OK:
		printerr("ProfileManager: Recursive remove: Failed to remove final directory '%s' after %s attempts. Final Error: %s" % [path, max_retries, final_remove_err])
		
	return final_remove_err
