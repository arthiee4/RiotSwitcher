class_name LeagueSettingsSync
extends RefCounted

## Shares League of Legends game settings (hotkeys, video, interface) across
## every profile by keeping a single shared copy of the files that carry them
## (game.cfg, PersistedSettings.json, input.ini).

const REG_LOL_UNINSTALL := "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live"
const SHARED_FILES: Array[String] = ["game.cfg", "PersistedSettings.json", "input.ini"]


## Locates the League of Legends install directory, or "" when not found.
static func find_league_dir(riot_client_location: String) -> String:
	var from_registry := _league_dir_from_registry()
	if not from_registry.is_empty():
		return from_registry
	# Fallback: League usually sits next to the Riot Client folder.
	if not riot_client_location.is_empty():
		var sibling := riot_client_location.get_base_dir().path_join("League of Legends")
		if DirAccess.dir_exists_absolute(sibling):
			return sibling
	return ""


## Captures game settings from a source directory (live League/Config or profile folder) into shared storage.
static func save_shared_settings_from_dir(source_dir: String) -> bool:
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		return false
	if DirAccess.make_dir_recursive_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR) != OK:
		printerr("LeagueSettingsSync: Failed to create shared settings directory.")
		return false

	var any_copied := false
	for filename in SHARED_FILES:
		var source := source_dir.path_join(filename)
		if not FileAccess.file_exists(source):
			continue
		if DirAccess.copy_absolute(source, AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(filename)) == OK:
			any_copied = true
	return any_copied


## Writes the shared backup into the destination directory (live League/Config or target profile folder).
static func restore_shared_settings_to_dir(dest_dir: String) -> bool:
	if dest_dir.is_empty() or not DirAccess.dir_exists_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR):
		return true

	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK:
		return false

	var all_ok := true
	for filename in SHARED_FILES:
		var backup := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(filename)
		if not FileAccess.file_exists(backup):
			continue
		if DirAccess.copy_absolute(backup, dest_dir.path_join(filename)) != OK:
			printerr("LeagueSettingsSync: Failed to restore '%s' to '%s'." % [filename, dest_dir])
			all_ok = false
	return all_ok


## Reads the League install path from the registry uninstall key. Returns "" on failure.
static func _league_dir_from_registry() -> String:
	var output: Array = []
	var exit_code := OS.execute("reg", ["query", REG_LOL_UNINSTALL, "/v", "InstallLocation"], output, true, false)
	if exit_code != 0:
		return ""
	for chunk: String in output:
		for line in chunk.split("\n", false):
			if line.contains("InstallLocation") and line.contains("REG_SZ"):
				var parts := line.split("REG_SZ", false, 1)
				if parts.size() < 2:
					continue
				var dir := parts[1].strip_edges()
				if DirAccess.dir_exists_absolute(dir):
					return dir
	return ""
