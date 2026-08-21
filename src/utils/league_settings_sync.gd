class_name LeagueSettingsSync
extends RefCounted

## Shares League of Legends game settings (hotkeys, video, audio, interface, smartcast)
## across every profile by keeping a single, validated, cryptographic master snapshot.
##
## Single Authority Rule:
## The profile designated as the Source Profile is the SOLE authority for shared settings.
## If the source profile is missing, corrupted, or unvalidated, apply operations are aborted.

enum ApplyResult {
	SUCCESS,
	SYNC_DISABLED,
	SOURCE_NOT_CONFIGURED,
	SOURCE_MISSING,
	SNAPSHOT_MISSING,
	SNAPSHOT_CORRUPT,
	HASH_MISMATCH,
	TARGET_UNLOCK_FAILED,
	DEPLOY_FAILED,
	DEPLOY_VERIFICATION_FAILED,
}

enum CaptureResult {
	SUCCESS,
	SOURCE_NOT_FOUND,
	INVALID_SOURCE_FILES,
	CORRUPT_PERSISTED_SETTINGS,
	STAGING_FAILED,
	METADATA_WRITE_FAILED,
}

const CONFIG_KEY_ENABLED := "SyncGameSettings"
const CONFIG_KEY_SOURCE_DIR := "SharedSettingsSourceDirectory"
const CONFIG_KEY_SOURCE_NAME_LEGACY := "SharedSettingsSourceProfile"
const CONFIG_KEY_READONLY := "EnforceReadOnlySettings"

const SHARED_FILES: Array[String] = [
	"game.cfg",
	"PersistedSettings.json",
	"input.ini",
	"ItemSets.json",
]

const SHARED_DIRS: Array[String] = [
	"Champions",
]

const METADATA_FILENAME := "metadata.json"
const SCHEMA_VERSION := 2

const RIOT_INSTALLS_JSON := "C:/ProgramData/Riot Games/RiotClientInstalls.json"
const RIOT_METADATA_YAML := "C:/ProgramData/Riot Games/Metadata/league_of_legends.live/league_of_legends.live.product_settings.yaml"

const REG_KEYS: Array[String] = [
	"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live",
	"HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live",
	"HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live",
]

static var _io_mutex := Mutex.new()


#region Public API — Source Resolution & Identification

## Resolves the configured source profile with deterministic directory_name lookup and legacy migration.
## Returns a Dictionary with:
##   - is_valid: bool
##   - directory_name: String
##   - display_name: String
##   - profile_dir: String
##   - error_message: String
static func resolve_source_profile(profile_manager: Node) -> Dictionary:
	_io_mutex.lock()
	var result := _resolve_source_profile_unlocked(profile_manager)
	_io_mutex.unlock()
	return result


static func _resolve_source_profile_unlocked(profile_manager: Node) -> Dictionary:
	var res := {
		"is_valid": false,
		"directory_name": "",
		"display_name": "",
		"profile_dir": "",
		"error_message": "",
	}

	if not profile_manager or not profile_manager.has_method("get_profiles"):
		res["error_message"] = "ProfileManager not available."
		return res

	var configured_dir: String = ConfigManager.get_value(CONFIG_KEY_SOURCE_DIR, "")
	var legacy_name: String = ConfigManager.get_value(CONFIG_KEY_SOURCE_NAME_LEGACY, "")

	var all_profiles: Array = profile_manager.get_profiles()

	# 1. Match by stable directory_name
	if not configured_dir.is_empty():
		for p: Dictionary in all_profiles:
			if p.get("directory_name", "") == configured_dir:
				res["is_valid"] = true
				res["directory_name"] = configured_dir
				res["display_name"] = p.get("profile_name", configured_dir)
				res["profile_dir"] = AppPaths.PROFILES_DIR.path_join(configured_dir)
				return res
		res["error_message"] = "Source profile directory '%s' no longer exists." % configured_dir
		return res

	# 2. Legacy Migration: Match by profile_name
	if not legacy_name.is_empty():
		for p: Dictionary in all_profiles:
			if p.get("profile_name", "") == legacy_name:
				var dir_name: String = p.get("directory_name", "")
				if not dir_name.is_empty():
					ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE_DIR, dir_name)
					print("[GameSettings] Migrated source profile reference from name '%s' to directory '%s'." % [legacy_name, dir_name])
					res["is_valid"] = true
					res["directory_name"] = dir_name
					res["display_name"] = legacy_name
					res["profile_dir"] = AppPaths.PROFILES_DIR.path_join(dir_name)
					return res
		res["error_message"] = "Legacy source profile '%s' not found." % legacy_name
		return res

	res["error_message"] = "No source profile configured."
	return res

#endregion


#region Public API — Validation & Hashing

## Calculates SHA-256 hash of a file. Returns "" if file does not exist or cannot be read.
static func calculate_file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


## Validates structural integrity of a PersistedSettings.json file.
static func validate_persisted_settings_file(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	var content := FileAccess.get_file_as_string(file_path)
	if content.strip_edges().is_empty() or content.length() < 16:
		return false
	var parsed = JSON.parse_string(content)
	if not parsed is Dictionary:
		return false
	var files_arr = parsed.get("files")
	if not files_arr is Array:
		return false
	return true


## Checks whether [param dir_path] contains valid League configuration files.
static func has_valid_settings(dir_path: String) -> bool:
	if dir_path.is_empty() or not DirAccess.dir_exists_absolute(dir_path):
		return false
	var has_cfg := FileAccess.file_exists(dir_path.path_join("game.cfg"))
	var has_json := validate_persisted_settings_file(dir_path.path_join("PersistedSettings.json"))
	var has_input := FileAccess.file_exists(dir_path.path_join("input.ini"))
	return (has_cfg or has_json or has_input)


## Inspects and returns snapshot metadata. Returns empty Dictionary if invalid.
static func get_snapshot_metadata() -> Dictionary:
	var meta_path := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(METADATA_FILENAME)
	if not FileAccess.file_exists(meta_path):
		return {}
	var json_str := FileAccess.get_file_as_string(meta_path)
	var data = JSON.parse_string(json_str)
	return data if data is Dictionary else {}


## Returns true when the tracked settings files inside [param dir_path] differ
## from the master snapshot. Also returns true when the master is missing or
## corrupt (there is nothing reliable to compare against).
static func settings_dir_differs_from_master(dir_path: String) -> bool:
	if not has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
		return true
	var meta := get_snapshot_metadata()
	var file_hashes: Dictionary = meta.get("file_hashes", {})
	if file_hashes.is_empty():
		return true
	for filename_v in file_hashes.keys():
		var filename := str(filename_v)
		if filename == "ItemSets.json":
			continue
		var candidate := dir_path.path_join(filename)
		if not FileAccess.file_exists(candidate):
			return true
		if calculate_file_hash(candidate) != str(file_hashes[filename_v]):
			return true
	return false


## Returns true when any tracked settings file inside [param dir_path] was
## modified after the master snapshot was captured.
static func settings_dir_newer_than_master(dir_path: String) -> bool:
	var meta := get_snapshot_metadata()
	var captured_at: float = float(meta.get("captured_at_unix", 0.0))
	if captured_at <= 0.0:
		return false
	for filename in SHARED_FILES:
		var candidate := dir_path.path_join(filename)
		if FileAccess.file_exists(candidate) and FileAccess.get_modified_time(candidate) > captured_at:
			return true
	return false

#endregion


#region Public API — Snapshot Capture & Copy

## Copies all configuration files and champion subdirectories from [param source_dir] to [param dest_dir].
static func copy_settings(source_dir: String, dest_dir: String) -> bool:
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		return false
	if dest_dir.is_empty():
		return false

	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK:
		printerr("[GameSettings] Failed to create destination directory '%s'." % dest_dir)
		return false

	var any_copied := false
	for filename in SHARED_FILES:
		var src := source_dir.path_join(filename)
		if not FileAccess.file_exists(src):
			continue
		var dst := dest_dir.path_join(filename)
		if FileAccess.file_exists(dst):
			set_file_readonly_windows(dst, false)
			DirAccess.remove_absolute(dst)
		if DirAccess.copy_absolute(src, dst) == OK:
			any_copied = true
		else:
			printerr("[GameSettings] Failed to copy '%s' to '%s'." % [src, dst])

	for dirname in SHARED_DIRS:
		var src_subdir := source_dir.path_join(dirname)
		if not DirAccess.dir_exists_absolute(src_subdir):
			continue
		var dst_subdir := dest_dir.path_join(dirname)
		_copy_dir_recursive(src_subdir, dst_subdir)

	return any_copied


## Restores the master shared snapshot into [param dest_dir].
static func restore_shared_settings_to_dir(dest_dir: String) -> bool:
	if not has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
		return false
	return copy_settings(AppPaths.SHARED_GAME_SETTINGS_DIR, dest_dir)


## Captures an atomic snapshot from [param source_dir] into the master shared storage.
## Strict validation guarantees that only consistent, verified files are stored.
static func capture_master_snapshot(source_dir: String, source_dir_name: String, source_display_name: String) -> int:
	_io_mutex.lock()
	var res := _capture_master_snapshot_unlocked(source_dir, source_dir_name, source_display_name)
	_io_mutex.unlock()
	return res


static func _capture_master_snapshot_unlocked(source_dir: String, source_dir_name: String, source_display_name: String) -> int:
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		printerr("[GameSettings] Capture failed: Source directory does not exist: ", source_dir)
		return CaptureResult.SOURCE_NOT_FOUND

	if not has_valid_settings(source_dir):
		printerr("[GameSettings] Capture failed: Source directory has no valid settings: ", source_dir)
		return CaptureResult.INVALID_SOURCE_FILES

	# Validate PersistedSettings.json if present
	var persisted_path := source_dir.path_join("PersistedSettings.json")
	if FileAccess.file_exists(persisted_path) and not validate_persisted_settings_file(persisted_path):
		printerr("[GameSettings] Capture failed: PersistedSettings.json in source is invalid or corrupted.")
		return CaptureResult.CORRUPT_PERSISTED_SETTINGS

	var staging_dir := AppPaths.SHARED_GAME_SETTINGS_DIR + "_tmp"
	if DirAccess.dir_exists_absolute(staging_dir):
		_remove_dir_recursive(staging_dir)

	if DirAccess.make_dir_recursive_absolute(staging_dir) != OK:
		printerr("[GameSettings] Capture failed: Could not create staging directory.")
		return CaptureResult.STAGING_FAILED

	var file_hashes: Dictionary = {}
	var file_sizes: Dictionary = {}
	var files_present: Array[String] = []

	# 1. Copy and hash files
	for filename in SHARED_FILES:
		var src := source_dir.path_join(filename)
		if not FileAccess.file_exists(src):
			continue
		var dst := staging_dir.path_join(filename)
		if DirAccess.copy_absolute(src, dst) != OK:
			printerr("[GameSettings] Capture failed: Error copying file '%s'." % filename)
			_remove_dir_recursive(staging_dir)
			return CaptureResult.STAGING_FAILED
		var hash_val := calculate_file_hash(dst)
		var size_val := FileAccess.get_file_as_bytes(dst).size()
		file_hashes[filename] = hash_val
		file_sizes[filename] = size_val
		files_present.append(filename)

	# 2. Copy directories
	for dirname in SHARED_DIRS:
		var src_sub := source_dir.path_join(dirname)
		if not DirAccess.dir_exists_absolute(src_sub):
			continue
		var dst_sub := staging_dir.path_join(dirname)
		_copy_dir_recursive(src_sub, dst_sub)
		files_present.append(dirname)

	# 3. Read current generation
	var prev_meta := get_snapshot_metadata()
	var next_gen: int = int(prev_meta.get("generation", 0)) + 1

	# 4. Generate metadata.json
	var metadata := {
		"schema_version": SCHEMA_VERSION,
		"source_directory": source_dir_name,
		"source_display_name": source_display_name,
		"captured_at_unix": Time.get_unix_time_from_system(),
		"captured_at_iso": Time.get_datetime_string_from_system(true),
		"generation": next_gen,
		"files_present": files_present,
		"file_hashes": file_hashes,
		"file_sizes": file_sizes,
	}

	var meta_file := FileAccess.open(staging_dir.path_join(METADATA_FILENAME), FileAccess.WRITE)
	if not meta_file:
		printerr("[GameSettings] Capture failed: Could not write metadata.json.")
		_remove_dir_recursive(staging_dir)
		return CaptureResult.METADATA_WRITE_FAILED
	meta_file.store_string(JSON.stringify(metadata, "\t"))
	meta_file.close()

	# 5. Promote staging files to master shared storage
	if DirAccess.make_dir_recursive_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR) != OK:
		printerr("[GameSettings] Capture failed: Could not create master shared directory.")
		_remove_dir_recursive(staging_dir)
		return CaptureResult.STAGING_FAILED

	var copy_ok := true
	for fn in files_present:
		if fn in SHARED_FILES:
			var s_file := staging_dir.path_join(fn)
			var d_file := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(fn)
			if FileAccess.file_exists(d_file):
				set_file_readonly_windows(d_file, false)
				DirAccess.remove_absolute(d_file)
			if DirAccess.copy_absolute(s_file, d_file) != OK:
				copy_ok = false
				printerr("[GameSettings] Failed to promote '%s' to master storage." % fn)
		elif fn in SHARED_DIRS:
			var s_dir := staging_dir.path_join(fn)
			var d_dir := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(fn)
			_copy_dir_recursive(s_dir, d_dir)

	# Copy metadata.json to master storage
	var meta_src := staging_dir.path_join(METADATA_FILENAME)
	var meta_dst := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(METADATA_FILENAME)
	if FileAccess.file_exists(meta_dst):
		set_file_readonly_windows(meta_dst, false)
	if DirAccess.copy_absolute(meta_src, meta_dst) != OK:
		copy_ok = false
		printerr("[GameSettings] Failed to copy metadata.json to master storage.")

	_remove_dir_recursive(staging_dir)

	if not copy_ok:
		printerr("[GameSettings] Capture failed: Could not copy all files to master directory.")
		return CaptureResult.STAGING_FAILED

	print("[GameSettings] Master snapshot captured successfully from '%s' (Gen %d, %d files: %s)." % [source_display_name, next_gen, files_present.size(), ", ".join(PackedStringArray(files_present))])
	return CaptureResult.SUCCESS

#endregion


#region Public API — Source Profile Open Refresh

## Ensures the master snapshot reflects the source profile's freshest settings
## before the source profile is launched (its files are unlocked for in-game
## edits). Precedence when several copies exist:
##   1. Live League config when it differs from the master — the source was
##      played after the last capture (normal close, crash, manual client exit
##      or same-profile restart).
##   2. Source profile folder when the master is missing/invalid (or owned by
##      a different profile).
##   3. Source profile folder when it is newer than the master while the live
##      config matches the master (a failed close-time capture).
## Falls back to repairing the live config from the master when it is broken,
## and seeds the source profile backup when it is missing.
## Returns true when the master snapshot is valid afterwards.
static func refresh_master_for_source(live_config_dir: String, source_profile_dir: String, source_dir_name: String, source_display_name: String) -> bool:
	_io_mutex.lock()
	var res := _refresh_master_for_source_unlocked(live_config_dir, source_profile_dir, source_dir_name, source_display_name)
	_io_mutex.unlock()
	return res


static func _refresh_master_for_source_unlocked(live_config_dir: String, source_profile_dir: String, source_dir_name: String, source_display_name: String) -> bool:
	var source_valid := not source_profile_dir.is_empty() and has_valid_settings(source_profile_dir)
	var master_valid := has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR)

	if source_valid:
		_capture_master_snapshot_unlocked(source_profile_dir, source_dir_name, source_display_name)
		if not live_config_dir.is_empty():
			copy_settings(source_profile_dir, live_config_dir)
		return true

	if master_valid:
		if not live_config_dir.is_empty():
			copy_settings(AppPaths.SHARED_GAME_SETTINGS_DIR, live_config_dir)
		if not source_profile_dir.is_empty():
			copy_settings(AppPaths.SHARED_GAME_SETTINGS_DIR, source_profile_dir)
		return true

	if has_valid_settings(live_config_dir):
		if _capture_master_snapshot_unlocked(live_config_dir, source_dir_name, source_display_name) == CaptureResult.SUCCESS:
			if not source_profile_dir.is_empty():
				copy_settings(live_config_dir, source_profile_dir)
			return true

	return false

#endregion


#region Public API — Snapshot Application & Protection

## Deploys the master shared snapshot into [param league_config_dir].
## Performs strict origin verification, post-copy hash validation, and read-only protection.
static func apply_master_snapshot_to_league(league_config_dir: String, profile_manager: Node, enforce_readonly: bool = true) -> int:
	_io_mutex.lock()
	var res := _apply_master_snapshot_unlocked(league_config_dir, profile_manager, enforce_readonly)
	_io_mutex.unlock()
	return res


static func _apply_master_snapshot_unlocked(league_config_dir: String, profile_manager: Node, enforce_readonly: bool) -> int:
	var sync_enabled := bool(ConfigManager.get_value(CONFIG_KEY_ENABLED, false))
	if not sync_enabled:
		return ApplyResult.SYNC_DISABLED

	if league_config_dir.is_empty() or not DirAccess.dir_exists_absolute(league_config_dir):
		printerr("[GameSettings] Apply aborted: League Config directory not found: ", league_config_dir)
		return ApplyResult.DEPLOY_FAILED

	# 1. Resolve configured Source Profile
	var source_info := _resolve_source_profile_unlocked(profile_manager)
	if not source_info["is_valid"]:
		printerr("[GameSettings] Apply aborted: %s" % source_info["error_message"])
		return ApplyResult.SOURCE_MISSING

	var expected_dir_name: String = source_info["directory_name"]
	var source_path: String = source_info["profile_dir"]

	# 2. Check and validate existing master snapshot
	var meta := get_snapshot_metadata()
	var snapshot_source_dir: String = meta.get("source_directory", "")

	# If snapshot is missing or belongs to a different profile, capture fresh from source folder!
	if snapshot_source_dir != expected_dir_name or not has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
		print("[GameSettings] Snapshot missing or belongs to another profile ('%s' vs expected '%s'). Capturing fresh..." % [snapshot_source_dir, expected_dir_name])
		var capture_res := _capture_master_snapshot_unlocked(source_path, expected_dir_name, source_info["display_name"])
		if capture_res != CaptureResult.SUCCESS:
			printerr("[GameSettings] Apply aborted: Could not capture valid snapshot from source profile.")
			return ApplyResult.SNAPSHOT_CORRUPT
		meta = get_snapshot_metadata()

	# 3. Final sanity check on metadata
	if meta.get("source_directory", "") != expected_dir_name:
		printerr("[GameSettings] FATAL: Snapshot source mismatch after capture! Aborting apply.")
		return ApplyResult.HASH_MISMATCH

	var file_hashes: Dictionary = meta.get("file_hashes", {})

	# 4. Remove Read-Only attributes from destination files before writing
	for filename in SHARED_FILES:
		var target_file := league_config_dir.path_join(filename)
		if FileAccess.file_exists(target_file):
			set_file_readonly_windows(target_file, false)

	# 5. Deploy files and directories to League/Config
	for filename in SHARED_FILES:
		var src := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(filename)
		if not FileAccess.file_exists(src):
			continue
		var dst := league_config_dir.path_join(filename)
		if FileAccess.file_exists(dst):
			set_file_readonly_windows(dst, false)
			DirAccess.remove_absolute(dst)
		if DirAccess.copy_absolute(src, dst) != OK:
			printerr("[GameSettings] Apply failed: Could not copy '%s' to '%s'." % [src, dst])
			return ApplyResult.DEPLOY_FAILED

	for dirname in SHARED_DIRS:
		var src_dir := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(dirname)
		if not DirAccess.dir_exists_absolute(src_dir):
			continue
		var dst_dir := league_config_dir.path_join(dirname)
		_copy_dir_recursive(src_dir, dst_dir)

	# 6. Verify post-deploy file hashes
	for filename in file_hashes.keys():
		if filename == "ItemSets.json":
			continue # ItemSets is optional and client-managed
		var expected_hash: String = file_hashes[filename]
		var deployed_file := league_config_dir.path_join(filename)
		if not FileAccess.file_exists(deployed_file):
			printerr("[GameSettings] Verification failed: Deployed file missing: ", deployed_file)
			return ApplyResult.DEPLOY_VERIFICATION_FAILED
		var actual_hash := calculate_file_hash(deployed_file)
		if actual_hash != expected_hash:
			printerr("[GameSettings] Verification failed: Hash mismatch for '%s' (%s vs %s)." % [filename, actual_hash, expected_hash])
			return ApplyResult.HASH_MISMATCH

	# 7. Apply Read-Only protection to configuration files and Champions folder if enforce_readonly is requested
	if enforce_readonly:
		for filename in SHARED_FILES:
			var protected_file := league_config_dir.path_join(filename)
			if FileAccess.file_exists(protected_file):
				set_file_readonly_windows(protected_file, true)
		for dirname in SHARED_DIRS:
			var protected_dir := league_config_dir.path_join(dirname)
			if DirAccess.dir_exists_absolute(protected_dir):
				_set_dir_readonly_windows(protected_dir, true)

	print("[GameSettings] Master snapshot applied and verified for '%s' (Hashes OK, Read-Only: %s)." % [source_info["display_name"], str(enforce_readonly)])
	return ApplyResult.SUCCESS


## Sets or removes the Windows Read-Only attribute on a file.
static func set_file_readonly_windows(file_path: String, readonly: bool) -> void:
	if OS.get_name() != "Windows":
		return
	var flag := "+R" if readonly else "-R"
	var global_path := ProjectSettings.globalize_path(file_path) if file_path.begins_with("user://") or file_path.begins_with("res://") else file_path
	global_path = global_path.replace("/", "\\")
	var output: Array = []
	OS.execute("attrib", [flag, global_path], output, true, false)


static func _set_dir_readonly_windows(dir_path: String, readonly: bool) -> void:
	if OS.get_name() != "Windows":
		return
	var flag := "+R" if readonly else "-R"
	var global_path := ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("user://") or dir_path.begins_with("res://") else dir_path
	global_path = global_path.replace("/", "\\")
	var output: Array = []
	OS.execute("attrib", [flag, global_path + "\\*.*", "/S"], output, true, false)


## Cleans up Read-Only flags on all League config files when sync is disabled.
static func cleanup_readonly_flags(league_config_dir: String) -> void:
	if league_config_dir.is_empty() or not DirAccess.dir_exists_absolute(league_config_dir):
		return
	for filename in SHARED_FILES:
		var target := league_config_dir.path_join(filename)
		if FileAccess.file_exists(target):
			set_file_readonly_windows(target, false)
	for dirname in SHARED_DIRS:
		var target_dir := league_config_dir.path_join(dirname)
		if DirAccess.dir_exists_absolute(target_dir):
			_set_dir_readonly_windows(target_dir, false)
	print("[GameSettings] Cleared Read-Only attributes in League Config folder.")

#endregion


#region Public API — League Directory Discovery

## Locates the League of Legends install directory using multiple robust sources.
static func find_league_dir(riot_client_location: String = "") -> String:
	# 1. Official Riot Client Installs JSON
	var from_installs := _league_dir_from_installs_json()
	if not from_installs.is_empty():
		return from_installs

	# 2. Riot Metadata YAML
	var from_metadata := _league_dir_from_metadata_yaml()
	if not from_metadata.is_empty():
		return from_metadata

	# 3. Windows Registry (HKCU / HKLM)
	var from_registry := _league_dir_from_registry()
	if not from_registry.is_empty():
		return from_registry

	# 4. Sibling of provided or saved Riot Client directory
	var rc_loc := riot_client_location
	if rc_loc.is_empty():
		rc_loc = ConfigManager.get_value("RiotClientLocation", "")
	if not rc_loc.is_empty():
		var sibling := rc_loc.get_base_dir().path_join("League of Legends")
		if DirAccess.dir_exists_absolute(sibling):
			return sibling

	# 5. Standard common drive locations
	for drive: String in ["D:", "C:", "E:", "F:", "G:"]:
		var candidate: String = drive + "/Riot Games/League of Legends"
		if DirAccess.dir_exists_absolute(candidate):
			return candidate

	return ""

#endregion


#region Private Helpers

static func _league_dir_from_installs_json() -> String:
	if not FileAccess.file_exists(RIOT_INSTALLS_JSON):
		return ""
	var json_str := FileAccess.get_file_as_string(RIOT_INSTALLS_JSON)
	if json_str.is_empty():
		return ""
	var data = JSON.parse_string(json_str)
	if not data is Dictionary:
		return ""

	var associated = data.get("associated_client", {})
	if associated is Dictionary:
		for path_key in associated.keys():
			var p_str := str(path_key).trim_suffix("/").trim_suffix("\\")
			if p_str.to_lower().ends_with("league of legends") and DirAccess.dir_exists_absolute(p_str):
				return p_str
	return ""


static func _league_dir_from_metadata_yaml() -> String:
	if not FileAccess.file_exists(RIOT_METADATA_YAML):
		return ""
	var f := FileAccess.open(RIOT_METADATA_YAML, FileAccess.READ)
	if not f:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("product_install_full_path:"):
			var parts := line.split(":", false, 1)
			if parts.size() >= 2:
				var path := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
				if DirAccess.dir_exists_absolute(path):
					return path
	return ""


static func _league_dir_from_registry() -> String:
	for reg_key in REG_KEYS:
		var output: Array = []
		var exit_code := OS.execute("reg", ["query", reg_key, "/v", "InstallLocation"], output, true, false)
		if exit_code == 0:
			for chunk: String in output:
				for line in chunk.split("\n", false):
					if line.contains("InstallLocation") and line.contains("REG_SZ"):
						var parts := line.split("REG_SZ", false, 1)
						if parts.size() >= 2:
							var dir := parts[1].strip_edges()
							if DirAccess.dir_exists_absolute(dir):
								return dir
	return ""


static func _copy_dir_recursive(source_dir: String, dest_dir: String) -> void:
	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK:
		return
	var dir := DirAccess.open(source_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		if item != "." and item != "..":
			var src_item := source_dir.path_join(item)
			var dst_item := dest_dir.path_join(item)
			if dir.current_is_dir():
				_copy_dir_recursive(src_item, dst_item)
			else:
				DirAccess.copy_absolute(src_item, dst_item)
		item = dir.get_next()
	dir.list_dir_end()


static func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		if item != "." and item != "..":
			var item_path := path.path_join(item)
			if dir.current_is_dir():
				_remove_dir_recursive(item_path)
			else:
				DirAccess.remove_absolute(item_path)
		item = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

#endregion
