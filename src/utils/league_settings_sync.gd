class_name LeagueSettingsSync
extends RefCounted

## Shares League of Legends game settings (hotkeys, video, interface) across
## every profile by keeping a single shared copy of the files that carry them
## (<League>/Config/game.cfg and PersistedSettings.json).
##
## The shared copy lives in user://shared_game_settings/: it is refreshed from
## the live League folder whenever a session ends, and written back before a
## session starts — so the last used settings follow every account.
##
## All functions only touch the filesystem and are safe to call from worker
## threads. The League client must NOT be running while they execute.

const REG_LOL_UNINSTALL := "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game league_of_legends.live"
const SHARED_FILES: Array[String] = ["game.cfg", "PersistedSettings.json"]


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


## Copies the live game settings into the shared backup. Returns true on success.
static func save_shared_settings(league_dir: String) -> bool:
	if league_dir.is_empty():
		return false
	var config_dir := league_dir.path_join("Config")
	if DirAccess.make_dir_recursive_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR) != OK:
		printerr("LeagueSettingsSync: Failed to create shared settings directory.")
		return false

	var all_ok := true
	for filename in SHARED_FILES:
		var source := config_dir.path_join(filename)
		if not FileAccess.file_exists(source):
			continue
		if DirAccess.copy_absolute(source, AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(filename)) != OK:
			printerr("LeagueSettingsSync: Failed to back up '%s'." % filename)
			all_ok = false
	return all_ok


## Writes the shared backup over the live game settings. When no backup exists
## yet (feature just enabled), the current files are kept untouched.
static func restore_shared_settings(league_dir: String) -> bool:
	if league_dir.is_empty() or not DirAccess.dir_exists_absolute(AppPaths.SHARED_GAME_SETTINGS_DIR):
		return true
	var config_dir := league_dir.path_join("Config")

	var all_ok := true
	for filename in SHARED_FILES:
		var backup := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join(filename)
		if not FileAccess.file_exists(backup):
			continue
		DirAccess.make_dir_recursive_absolute(config_dir)
		if DirAccess.copy_absolute(backup, config_dir.path_join(filename)) != OK:
			printerr("LeagueSettingsSync: Failed to restore '%s'." % filename)
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
