class_name SharedSettingsController
extends Control

## Settings row for shared game settings: a toggle that enables sharing and
## a dropdown to pick the source profile — the one whose hotkeys/graphics
## every account will use.
##
## The source profile's game settings are captured whenever its session ends
## (see ProfileGridController) and applied to the live League folder before
## any profile launches. Per-profile session management is untouched.

const CONFIG_KEY_ENABLED := "SyncGameSettings"
const CONFIG_KEY_SOURCE_DIR := "SharedSettingsSourceDirectory"
const CONFIG_KEY_SOURCE_NAME_LEGACY := "SharedSettingsSourceProfile"

@onready var _check_button: CheckButton = $Panel/CheckButton if has_node("Panel/CheckButton") else null
@onready var _dropdown: OptionButton = $Panel/OptionButton if has_node("Panel/OptionButton") else null

var _lock_timer: Timer = null
var _lock_tween: Tween = null
var _is_locked_by_game: bool = false


func _ready() -> void:
	if not _check_button or not _dropdown:
		printerr("SharedSettings: Missing CheckButton or OptionButton node.")
		return
	_check_button.button_pressed = bool(ConfigManager.get_value(CONFIG_KEY_ENABLED, Constants.DEFAULT_SYNC_GAME_SETTINGS))
	_check_button.toggled.connect(_on_toggled)
	_dropdown.item_selected.connect(_on_profile_selected)
	ProfileManager.profiles_updated.connect(_refresh_profiles)
	ConfigManager.configs_updated.connect(_update_game_running_lock)

	_lock_timer = Timer.new()
	_lock_timer.wait_time = 1.0
	_lock_timer.timeout.connect(_update_game_running_lock)
	add_child(_lock_timer)
	_lock_timer.start()

	_refresh_profiles()
	_update_game_running_lock()


func _on_toggled(pressed: bool) -> void:
	if not ConfigManager.set_value_and_save(CONFIG_KEY_ENABLED, pressed):
		printerr("[GameSettings] Failed to save '%s'." % CONFIG_KEY_ENABLED)
	_update_dropdown_state()

	var rc_loc: String = ConfigManager.get_value("RiotClientLocation", "")
	var league_dir := LeagueSettingsSync.find_league_dir(rc_loc)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""

	if pressed:
		_refresh_profiles() # Auto-select a source when none is configured yet.
		_sync_from_selected_source()
	else:
		if not live_config_dir.is_empty():
			LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)


func _on_profile_selected(index: int) -> void:
	var dir_name: String = _dropdown.get_item_metadata(index)
	if dir_name.is_empty():
		return
	if not ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE_DIR, dir_name):
		printerr("[GameSettings] Failed to save '%s'." % CONFIG_KEY_SOURCE_DIR)

	# Update legacy name key as well for backwards compatibility
	var p := _find_profile_by_dir(dir_name)
	if not p.is_empty():
		ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE_NAME_LEGACY, p.get("profile_name", ""))

	_sync_from_selected_source()


func _sync_from_selected_source() -> void:
	var source_info := LeagueSettingsSync.resolve_source_profile(ProfileManager)
	if not source_info["is_valid"]:
		printerr("[GameSettings] Cannot sync: %s" % source_info["error_message"])
		return

	var source_dir_name: String = source_info["directory_name"]
	var source_display_name: String = source_info["display_name"]
	var source_profile_dir: String = source_info["profile_dir"]

	var rc_loc: String = ConfigManager.get_value("RiotClientLocation", "")
	var league_dir := LeagueSettingsSync.find_league_dir(rc_loc)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""

	var source_dir_valid := LeagueSettingsSync.has_valid_settings(source_profile_dir)
	var live_valid := not live_config_dir.is_empty() and LeagueSettingsSync.has_valid_settings(live_config_dir)
	var master_valid := LeagueSettingsSync.has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR)

	# The Source Profile's own backup folder is the authority: the live League
	# config may hold any other profile's settings, so it is only used to seed
	# the source folder when the source has no settings of its own yet.
	if not source_dir_valid and live_valid:
		print("[GameSettings] Source profile '%s' has no saved settings; seeding from live League settings." % source_display_name)
		LeagueSettingsSync.copy_settings(live_config_dir, source_profile_dir)
	elif not source_dir_valid and master_valid:
		print("[GameSettings] Source profile '%s' has no saved settings; seeding from master snapshot." % source_display_name)
		LeagueSettingsSync.restore_shared_settings_to_dir(source_profile_dir)
	elif not source_dir_valid:
		printerr("[GameSettings] Cannot sync: source profile '%s' has no settings to capture." % source_display_name)
		return

	# 2. Capture master snapshot from the source profile directory
	var capture_res := LeagueSettingsSync.capture_master_snapshot(source_profile_dir, source_dir_name, source_display_name)
	if capture_res != LeagueSettingsSync.CaptureResult.SUCCESS:
		printerr("[GameSettings] Failed to capture master snapshot from '%s' (Error: %d)." % [source_display_name, capture_res])
		return

	# 3. Apply master snapshot to live League Config
	if not live_config_dir.is_empty():
		LeagueSettingsSync.apply_master_snapshot_to_league(live_config_dir, ProfileManager, false)
		LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)


## Rebuilds the dropdown from the profile list, keeping the saved selection.
func _refresh_profiles() -> void:
	if not is_instance_valid(_dropdown):
		return

	var source_info := LeagueSettingsSync.resolve_source_profile(ProfileManager)
	var current_source_dir: String = source_info.get("directory_name", "")

	_dropdown.clear()

	var selected_index := -1
	var index := 0
	var profiles: Array = ProfileManager.get_profiles()

	for profile: Dictionary in profiles:
		var profile_name: String = profile.get("profile_name", "")
		var dir_name: String = profile.get("directory_name", "")
		if dir_name.is_empty():
			continue
		_dropdown.add_item(profile_name)
		_dropdown.set_item_metadata(index, dir_name)
		if dir_name == current_source_dir:
			selected_index = index
		index += 1

	if index == 0:
		_dropdown.add_item("(no profiles)")
		_dropdown.set_item_metadata(0, "")
	else:
		if selected_index >= 0:
			_dropdown.select(selected_index)
		elif bool(ConfigManager.get_value(CONFIG_KEY_ENABLED, Constants.DEFAULT_SYNC_GAME_SETTINGS)):
			# No source configured (or it was deleted) while sync is enabled:
			# select the first profile so a source always exists.
			_dropdown.select(0)
			var first_dir: String = _dropdown.get_item_metadata(0)
			ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE_DIR, first_dir)
			var p := _find_profile_by_dir(first_dir)
			if not p.is_empty():
				ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE_NAME_LEGACY, p.get("profile_name", ""))

	_update_dropdown_state()


func _update_dropdown_state() -> void:
	if _is_locked_by_game:
		_check_button.disabled = true
		_dropdown.disabled = true
		return
	var enabled: bool = _check_button.button_pressed and _dropdown.item_count > 0 and not String(_dropdown.get_item_metadata(0)).is_empty()
	_dropdown.disabled = not enabled


func _update_game_running_lock(_configs: Dictionary = {}) -> void:
	if not is_inside_tree() or not is_instance_valid(_check_button) or not is_instance_valid(_dropdown):
		return

	var last_running: String = ConfigManager.get_value("LastRunningProfile", "")
	var is_running: bool = not last_running.is_empty()

	if is_running == _is_locked_by_game:
		return
	_is_locked_by_game = is_running

	if _lock_tween and _lock_tween.is_valid():
		_lock_tween.kill()
	_lock_tween = create_tween()

	if _is_locked_by_game:
		_check_button.disabled = true
		_dropdown.disabled = true
		_lock_tween.tween_property(self, "modulate:a", 0.45, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tooltip_text = tr("Settings are locked while a profile is running. Close the game to modify.")
	else:
		_check_button.disabled = false
		_update_dropdown_state()
		_lock_tween.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tooltip_text = ""


func _find_profile_by_dir(dir_name: String) -> Dictionary:
	for p: Dictionary in ProfileManager.get_profiles():
		if p.get("directory_name", "") == dir_name:
			return p
	return {}

