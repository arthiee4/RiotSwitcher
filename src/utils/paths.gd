class_name AppPaths
extends RefCounted

## Central definition of every file/directory path the app persists to.
## All user data lives under user:// so it also works in exported builds
## (res:// is read-only once packed).

const DATA_DIR := "user://data/"
const CONFIG_FILE := DATA_DIR + "configs.json"
const PROFILES_FILE := DATA_DIR + "profiles_data.json"
const PROFILES_DIR := "user://profiles/"
const BACKGROUNDS_DIR := "user://backgrounds/"
const SHARED_GAME_SETTINGS_DIR := "user://shared_game_settings/"

## Legacy locations used by older versions (kept for one-time migration).
const LEGACY_CONFIG_FILE := "res://Data/configs.json"
const LEGACY_PROFILES_FILE := "res://Data/profiles_data.json"
const LEGACY_BACKGROUNDS_DIR := "user://UserBackground/"


## Copies data from legacy locations to the current ones, once.
## Safe to call on every startup: it only copies when the new file is missing.
static func migrate_legacy_data() -> void:
	_migrate_file(LEGACY_CONFIG_FILE, CONFIG_FILE)
	_migrate_file(LEGACY_PROFILES_FILE, PROFILES_FILE)

	if DirAccess.dir_exists_absolute(LEGACY_BACKGROUNDS_DIR) and not DirAccess.dir_exists_absolute(BACKGROUNDS_DIR):
		DirAccess.make_dir_recursive_absolute(BACKGROUNDS_DIR)
		_copy_dir_contents(LEGACY_BACKGROUNDS_DIR, BACKGROUNDS_DIR)
		# Background paths stored in profiles_data.json still point to the old
		# folder, so rewrite them after migrating.
		_rewrite_background_paths()


static func _migrate_file(legacy_path: String, new_path: String) -> void:
	if FileAccess.file_exists(new_path) or not FileAccess.file_exists(legacy_path):
		return
	var data = JsonFile.load_data(legacy_path)
	if data != null and JsonFile.save_data(new_path, data):
		print("AppPaths: Migrated '%s' -> '%s'" % [legacy_path, new_path])


static func _rewrite_background_paths() -> void:
	var data = JsonFile.load_data(PROFILES_FILE)
	if not data is Dictionary or not data.has("profiles") or not data["profiles"] is Array:
		return
	var changed := false
	for profile: Dictionary in data["profiles"]:
		var bg: String = profile.get("custom_background_image", "")
		if bg.begins_with(LEGACY_BACKGROUNDS_DIR):
			profile["custom_background_image"] = BACKGROUNDS_DIR + bg.trim_prefix(LEGACY_BACKGROUNDS_DIR)
			changed = true
	if changed:
		JsonFile.save_data(PROFILES_FILE, data)


static func _copy_dir_contents(source_dir: String, dest_dir: String) -> void:
	var dir := DirAccess.open(source_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and not dir.current_is_dir():
			DirAccess.copy_absolute(source_dir.path_join(entry), dest_dir.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
