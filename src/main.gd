extends Control

## Root of the app. Wires the managers and controllers together and owns
## app-level behavior (view switching, window focus FPS, close-to-tray).

@onready var left_menu_handler: Control = $leftmenu_side if has_node("leftmenu_side") else find_child("leftmenu_side", true, false)
@onready var profile_grid: GridContainer = $content_side/GridContainer if has_node("content_side/GridContainer") else find_child("GridContainer", true, false)
@onready var settings_menu: Control = $settings_menu if has_node("settings_menu") else find_child("settings_menu", true, false)
@onready var add_menu: Control = $add_menu if has_node("add_menu") else find_child("add_menu", true, false)
@onready var boot_screen: Control = $boot if has_node("boot") else find_child("boot", true, false)
@onready var system_tray: Node = $systemtray if has_node("systemtray") else find_child("systemtray", true, false)

var riot_client_location: String = ""


func _ready() -> void:
	AppPaths.migrate_legacy_data()
	# We handle NOTIFICATION_WM_CLOSE_REQUEST ourselves (minimize to tray).
	get_tree().auto_accept_quit = false

	if boot_screen and boot_screen.has_method("set_config_manager"):
		boot_screen.set_config_manager(ConfigManager)

	ConfigManager.configs_updated.connect(_on_configs_updated)

	if left_menu_handler:
		left_menu_handler.home_selected.connect(_show_home_view)
		left_menu_handler.settings_selected.connect(_show_settings_view)
		left_menu_handler.add_profile_selected.connect(_show_add_profile_view)

	if add_menu:
		if add_menu.has_method("set_profile_manager"):
			add_menu.set_profile_manager(ProfileManager)
		add_menu.profile_created_successfully.connect(_on_profile_creation_success)
		add_menu.warning_dismissed.connect(_on_add_menu_warning_dismissed)

	if system_tray:
		system_tray.exit_requested.connect(_on_tray_exit_requested)
		system_tray.show_window_requested.connect(_on_tray_show_window_requested)

	if profile_grid:
		profile_grid.set_dependencies(ProfileManager, riot_client_location)

	ProfileManager.load_profiles_data()
	ConfigManager.load_configs()

	_show_home_view()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_session_and_quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = 5
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = 60


#region Config handling

func _on_configs_updated(new_config_data: Dictionary) -> void:
	var new_location: String = new_config_data.get("RiotClientLocation", "")
	if new_location != riot_client_location:
		riot_client_location = new_location
		profile_grid.update_riot_client_location(riot_client_location)

	# First-run: no client location yet, so keep the setup screen visible.
	_set_boot_visible(riot_client_location.is_empty())

	add_menu.set_warning_visibility(new_config_data.get("warning_shown", true))


func _on_add_menu_warning_dismissed() -> void:
	if not ConfigManager.set_value_and_save("warning_shown", false):
		printerr("Main: Failed to save warning state.")

#endregion

#region View switching

func _show_home_view() -> void:
	settings_menu.visible = false
	add_menu.visible = false


func _show_settings_view() -> void:
	settings_menu.visible = true
	add_menu.visible = false


func _show_add_profile_view() -> void:
	settings_menu.visible = false
	add_menu.visible = true


func _on_profile_creation_success() -> void:
	left_menu_handler.select_home()

#endregion

#region Boot screen

## Toggles the boot screen on/off, disabling processing and input when hidden
## so it never interferes with the main UI.
func _set_boot_visible(show_boot: bool) -> void:
	boot_screen.visible = show_boot
	boot_screen.set_process(show_boot)
	boot_screen.set_process_input(show_boot)
	# Block interaction with the content behind the boot screen.
	boot_screen.mouse_filter = Control.MOUSE_FILTER_STOP if show_boot else Control.MOUSE_FILTER_IGNORE

#endregion

#region System tray / window lifecycle

## Saves the running session and terminates the application cleanly.
func save_session_and_quit() -> void:
	if profile_grid and is_instance_valid(profile_grid):
		profile_grid.save_running_session()
	get_tree().quit()


## Closing the window hides it to the tray; the running session is saved
## so the account state is never lost.
func _hide_to_tray() -> void:
	if profile_grid and is_instance_valid(profile_grid):
		profile_grid.save_running_session()
	get_window().visible = false


func _on_tray_show_window_requested() -> void:
	get_window().visible = true
	DisplayServer.window_move_to_foreground()


func _on_tray_exit_requested() -> void:
	save_session_and_quit()

#endregion
