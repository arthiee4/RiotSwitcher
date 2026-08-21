extends Control

## Root of the app. Wires the managers and controllers together and owns
## app-level behavior (view switching, window focus FPS, close-to-tray).

@onready var left_menu_handler: Control = $leftmenu_side if has_node("leftmenu_side") else find_child("leftmenu_side", true, false)
@onready var home_view: Control = $home if has_node("home") else find_child("home", true, false)
@onready var profile_grid: GridContainer = $home/GridContainer if has_node("home/GridContainer") else find_child("GridContainer", true, false)
@onready var settings_menu: Control = $settings_menu if has_node("settings_menu") else find_child("settings_menu", true, false)
@onready var add_menu: Control = $add_menu if has_node("add_menu") else find_child("add_menu", true, false)
@onready var edit_profile_modal: Control = $edit_profile_modal if has_node("edit_profile_modal") else find_child("edit_profile_modal", true, false)
@onready var boot_screen: Control = $boot if has_node("boot") else find_child("boot", true, false)
@onready var system_tray: Node = $systemtray if has_node("systemtray") else find_child("systemtray", true, false)

var riot_client_location: String = ""
var _current_active_view: Control = null
var _view_tween: Tween = null


func _ready() -> void:
	# Ensure transparent clear color for smooth desktop alpha blending
	get_tree().root.transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	modulate.a = 0.0

	_setup_window_icon()
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

	if edit_profile_modal:
		edit_profile_modal.profile_manager = ProfileManager

	if system_tray:
		system_tray.exit_requested.connect(_on_tray_exit_requested)
		system_tray.show_window_requested.connect(_on_tray_show_window_requested)

	# Load persisted data before wiring the grid so it can adopt a profile
	# that was left running when the app last exited.
	ProfileManager.load_profiles_data()
	ConfigManager.load_configs()

	if profile_grid:
		profile_grid.set_dependencies(ProfileManager, riot_client_location)
		profile_grid.edit_profile_requested.connect(_on_edit_profile_requested)

	_show_home_view()
	_play_startup_entrance()


func _play_startup_entrance() -> void:
	# Start fully transparent
	modulate.a = 0.0

	# Initial states for elements
	var riot_lbl := home_view.get_node_or_null("riot") as Control if home_view else null
	var switcher_lbl := home_view.get_node_or_null("switcher") as Control if home_view else null
	var version_lbl := home_view.get_node_or_null("version") as Control if home_view else null

	if riot_lbl:
		riot_lbl.modulate.a = 0.0
		riot_lbl.position.y -= 12.0
	if switcher_lbl:
		switcher_lbl.modulate.a = 0.0
		switcher_lbl.position.y -= 12.0
	if version_lbl:
		version_lbl.modulate.a = 0.0
	if left_menu_handler:
		left_menu_handler.modulate.a = 0.0

	# Wait 2 frames for rendering to stabilize
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Root Scene Fade-in (fades entire transparent window into view over desktop)
	const FADE_DURATION := 0.2
	var window_tween := create_tween()
	window_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Left Menu entrance
	if left_menu_handler:
		var left_tween := create_tween()
		left_tween.tween_property(left_menu_handler, "modulate:a", 1.0, FADE_DURATION).set_delay(0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Header title labels entrance
	var title_tween := create_tween().set_parallel(true)
	if riot_lbl:
		title_tween.tween_property(riot_lbl, "modulate:a", 1.0, 0.35).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(riot_lbl, "position:y", riot_lbl.position.y + 12.0, 0.40).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if switcher_lbl:
		title_tween.tween_property(switcher_lbl, "modulate:a", 1.0, 0.35).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(switcher_lbl, "position:y", switcher_lbl.position.y + 12.0, 0.40).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if version_lbl:
		title_tween.tween_property(version_lbl, "modulate:a", 0.66, 0.35).set_delay(0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Profile cards cascade entrance
	if profile_grid and profile_grid.has_method("play_cascade_entrance"):
		profile_grid.play_cascade_entrance(0.10)


func _setup_window_icon() -> void:
	var icon_tex := load("res://assets/icons/icon1.png") as Texture2D
	if not icon_tex:
		icon_tex = load("res://icon.svg") as Texture2D
	if icon_tex:
		var image := icon_tex.get_image()
		if image:
			DisplayServer.set_icon(image)


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
	if new_location.is_empty():
		var default_path := "C:/Riot Games/Riot Client"
		if FileAccess.file_exists(default_path.path_join("RiotClientServices.exe")):
			new_location = default_path
			ConfigManager.set_value_and_save("RiotClientLocation", default_path)

	if new_location != riot_client_location:
		riot_client_location = new_location
		if profile_grid:
			profile_grid.update_riot_client_location(riot_client_location)

	# First-run: no client location yet, so keep the setup screen visible.
	_set_boot_visible(riot_client_location.is_empty())

	if add_menu and add_menu.has_method("set_warning_visibility"):
		add_menu.set_warning_visibility(new_config_data.get("warning_shown", true))


func _on_add_menu_warning_dismissed() -> void:
	if not ConfigManager.set_value_and_save("warning_shown", false):
		printerr("Main: Failed to save warning state.")

#endregion

#region View switching (Juicy & Minimalist Transitions)

func _switch_to_view(target_view: Control) -> void:
	if not target_view or not is_instance_valid(target_view):
		return
	if _current_active_view == target_view and target_view.visible:
		return

	if edit_profile_modal and edit_profile_modal.has_method("close"):
		edit_profile_modal.close()

	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()
		_view_tween = null

	_current_active_view = target_view
	var all_views: Array[Control] = [home_view, settings_menu, add_menu]

	var views_to_hide: Array[Control] = []
	for v in all_views:
		if not v or not is_instance_valid(v) or v == target_view:
			continue
		if v.visible:
			views_to_hide.append(v)

	var needs_tween := views_to_hide.size() > 0 or target_view != home_view

	if needs_tween:
		_view_tween = create_tween().set_parallel(true)
		for v in views_to_hide:
			_view_tween.tween_property(v, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_view_tween.tween_property(v, "scale", Vector2(0.985, 0.985), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			var captured_v := v
			_view_tween.chain().tween_callback(func():
				captured_v.visible = false
				captured_v.scale = Vector2.ONE
			)

	# Setup and animate target view entrance
	target_view.visible = true

	if target_view == home_view:
		target_view.modulate.a = 1.0
		target_view.scale = Vector2.ONE
		if profile_grid and profile_grid.has_method("play_cascade_entrance"):
			profile_grid.play_cascade_entrance()
	elif target_view == settings_menu:
		target_view.modulate.a = 1.0
		target_view.scale = Vector2.ONE
		if settings_menu and settings_menu.has_method("play_cascade_entrance"):
			settings_menu.play_cascade_entrance()
	elif target_view == add_menu:
		target_view.modulate.a = 1.0
		target_view.scale = Vector2.ONE
		if add_menu and add_menu.has_method("play_cascade_entrance"):
			add_menu.play_cascade_entrance()
	else:
		var sz := target_view.size
		if sz.x <= 0 or sz.y <= 0:
			sz = target_view.get_rect().size
		if sz.x > 0 and sz.y > 0:
			target_view.pivot_offset = sz * 0.5

		target_view.modulate.a = 0.0
		target_view.scale = Vector2(0.975, 0.975)

		if _view_tween:
			_view_tween.tween_property(target_view, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_view_tween.tween_property(target_view, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_home_view() -> void:
	_switch_to_view(home_view)


func _show_settings_view() -> void:
	_switch_to_view(settings_menu)


func _show_add_profile_view() -> void:
	if add_menu and add_menu.has_method("reset_form"):
		add_menu.reset_form()
	_switch_to_view(add_menu)


func _on_profile_creation_success() -> void:
	left_menu_handler.select_home()


func _on_edit_profile_requested(profile_data: Dictionary) -> void:
	if edit_profile_modal and edit_profile_modal.has_method("open_edit"):
		edit_profile_modal.open_edit(profile_data)

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
	if PresenceManager != null:
		PresenceManager.stop_proxy()
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
