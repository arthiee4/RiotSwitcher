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
const CONFIG_KEY_SOURCE := "SharedSettingsSourceProfile"

@onready var _check_button: CheckButton = $Panel/CheckButton if has_node("Panel/CheckButton") else null
@onready var _dropdown: OptionButton = $Panel/OptionButton if has_node("Panel/OptionButton") else null


func _ready() -> void:
	if not _check_button or not _dropdown:
		printerr("SharedSettings: Missing CheckButton or OptionButton node.")
		return
	_check_button.button_pressed = bool(ConfigManager.get_value(CONFIG_KEY_ENABLED, Constants.DEFAULT_SYNC_GAME_SETTINGS))
	_check_button.toggled.connect(_on_toggled)
	_dropdown.item_selected.connect(_on_profile_selected)
	ProfileManager.profiles_updated.connect(_refresh_profiles)
	_refresh_profiles()


func _on_toggled(pressed: bool) -> void:
	if not ConfigManager.set_value_and_save(CONFIG_KEY_ENABLED, pressed):
		printerr("SharedSettings: Failed to save '%s'." % CONFIG_KEY_ENABLED)
	_update_dropdown_state()
	if pressed:
		_sync_all_profiles_now()


func _on_profile_selected(index: int) -> void:
	var profile_name: String = _dropdown.get_item_metadata(index)
	if profile_name.is_empty():
		return
	if not ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE, profile_name):
		printerr("SharedSettings: Failed to save '%s'." % CONFIG_KEY_SOURCE)
	_sync_all_profiles_now()


func _sync_all_profiles_now() -> void:
	var source_profile: String = ConfigManager.get_value(CONFIG_KEY_SOURCE, "")
	if source_profile.is_empty():
		return

	var source_dir := ""
	if ProfileManager and ProfileManager.has_method("_get_profile_dir"):
		var profile_dir: String = ProfileManager._get_profile_dir(source_profile)
		if not profile_dir.is_empty() and DirAccess.dir_exists_absolute(profile_dir):
			source_dir = profile_dir

	var league_dir := LeagueSettingsSync.find_league_dir("")
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""

	if source_dir.is_empty() or not FileAccess.file_exists(source_dir.path_join("PersistedSettings.json")):
		source_dir = live_config_dir

	if not source_dir.is_empty() and DirAccess.dir_exists_absolute(source_dir):
		LeagueSettingsSync.save_shared_settings_from_dir(source_dir)

	if not live_config_dir.is_empty():
		LeagueSettingsSync.restore_shared_settings_to_dir(live_config_dir)

	if ProfileManager and ProfileManager.has_method("get_profiles"):
		for profile: Dictionary in ProfileManager.get_profiles():
			var dir_name: String = profile.get("directory_name", "")
			if not dir_name.is_empty():
				var target_p_dir := AppPaths.PROFILES_DIR.path_join(dir_name)
				LeagueSettingsSync.restore_shared_settings_to_dir(target_p_dir)


## Rebuilds the dropdown from the profile list, keeping the saved selection.
func _refresh_profiles() -> void:
	if not is_instance_valid(_dropdown):
		return
	var saved_source: String = ConfigManager.get_value(CONFIG_KEY_SOURCE, "")
	_dropdown.clear()

	var selected_index := -1
	var index := 0
	for profile: Dictionary in ProfileManager.get_profiles():
		var profile_name: String = profile.get("profile_name", "")
		if profile_name.is_empty():
			continue
		_dropdown.add_item(profile_name)
		_dropdown.set_item_metadata(index, profile_name)
		if profile_name == saved_source:
			selected_index = index
		index += 1

	if index == 0:
		_dropdown.add_item("(no profiles)")
		_dropdown.set_item_metadata(0, "")
	else:
		# Default to the first profile when nothing was chosen yet, so the
		# saved config always matches what the dropdown shows.
		if selected_index < 0:
			selected_index = 0
			ConfigManager.set_value_and_save(CONFIG_KEY_SOURCE, _dropdown.get_item_metadata(0))
		_dropdown.select(selected_index)

	_update_dropdown_state()


func _update_dropdown_state() -> void:
	var enabled: bool = _check_button.button_pressed and _dropdown.item_count > 0 and not String(_dropdown.get_item_metadata(0)).is_empty()
	_dropdown.disabled = not enabled
