extends Control

# Root of the app.

@onready var left_menu_handler: Control = $leftmenu_side if has_node("leftmenu_side") else find_child("leftmenu_side", true, false)
@onready var home_view: Control = $home if has_node("home") else find_child("home", true, false)
@onready var profile_grid: GridContainer = $home/GridContainer if has_node("home/GridContainer") else find_child("GridContainer", true, false)
@onready var settings_menu: Control = $settings_menu if has_node("settings_menu") else find_child("settings_menu", true, false)
@onready var add_menu: Control = $add_menu if has_node("add_menu") else find_child("add_menu", true, false)
@onready var edit_profile_modal: Control = $edit_profile_modal if has_node("edit_profile_modal") else find_child("edit_profile_modal", true, false)
@onready var boot_screen: Control = $boot if has_node("boot") else find_child("boot", true, false)
@onready var system_tray: Node = $systemtray if has_node("systemtray") else find_child("systemtray", true, false)
@onready var upper_side: Control = $upper_side if has_node("upper_side") else find_child("upper_side", true, false)

var riot_client_location: String = ""
var _current_active_view: Control = null
var _view_tween: Tween = null
var _home_title_tween: Tween = null
var _accent_color_sources: Dictionary = {}
var _accent_style_sources: Dictionary = {}
var _accent_modulate_sources: Dictionary = {}

const ACCENT_PRESETS := {
	"red": Color("#ff0000"), "white": Color("#f0e6d2"),
	"blue": Color("#4f8fd8"), "gold": Color("#c8aa6e"),
	"green": Color("#45b878"), "violet": Color("#9b70d8"),
	"cyan": Color("#39c6c8"), "orange": Color("#e08a3e"),
	"pink": Color("#d96b9b"), "gray": Color("#858b95"),
}


func _ready() -> void:
	# Do not let the opaque scene background flash while the transparent window is initializing.
	visible = false
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

	# Load persisted data before wiring the grid so it can adopt a profile that was left running when the app last exited.
	ProfileManager.load_profiles_data()
	ConfigManager.load_configs()

	if profile_grid:
		profile_grid.set_dependencies(ProfileManager, riot_client_location)
		profile_grid.edit_profile_requested.connect(_on_edit_profile_requested)

	if not ProfileManager.profiles_updated.is_connected(_on_profiles_updated):
		ProfileManager.profiles_updated.connect(_on_profiles_updated)

	_apply_accent(String(ConfigManager.get_value("AccentColor", "white")))
	_setup_export_safe_theme_dropdowns()

	_show_home_view()
	_play_startup_entrance()
	_set_version_label()


func _setup_export_safe_theme_dropdowns() -> void:
	var accent_option := get_node_or_null("settings_menu/GridContainer/cleanlogs/Panel/OptionButton") as OptionButton
	var theme_option := get_node_or_null("settings_menu/GridContainer/cleanlogs/Panel/UIOptionButton") as OptionButton
	if not accent_option or not theme_option:
		return
	var accent_keys := ["white", "gold", "red", "blue", "green", "violet", "cyan", "orange", "pink", "gray"]
	var accent_labels := ["White", "Gold", "Red", "Blue", "Green", "Violet", "Cyan", "Orange", "Pink", "Gray"]
	accent_option.clear()
	for i in range(accent_keys.size()):
		accent_option.add_item(accent_labels[i], i)
		accent_option.set_item_metadata(i, accent_keys[i])
	var theme_keys := ["fancy", "clean", "league_client"]
	var theme_labels := ["Cyberpunk", "Classic", "League Client"]
	theme_option.clear()
	for i in range(theme_keys.size()):
		theme_option.add_item(theme_labels[i], i)
		theme_option.set_item_metadata(i, theme_keys[i])
	var accent := String(ConfigManager.get_value("AccentColor", "white")).to_lower()
	var theme := String(ConfigManager.get_value("UIStyle", "fancy")).to_lower()
	var accent_idx := accent_keys.find(accent)
	var theme_idx := theme_keys.find(theme)
	accent_option.select(maxi(accent_idx, 0))
	theme_option.select(maxi(theme_idx, 0))
	accent_option.disabled = theme == "clean" or theme == "league_client"
	if not accent_option.item_selected.is_connected(_on_export_accent_selected):
		accent_option.item_selected.connect(_on_export_accent_selected)
	if not theme_option.item_selected.is_connected(_on_export_theme_selected):
		theme_option.item_selected.connect(_on_export_theme_selected)


func _on_export_accent_selected(index: int) -> void:
	var keys := ["white", "gold", "red", "blue", "green", "violet", "cyan", "orange", "pink", "gray"]
	if index >= 0 and index < keys.size():
		ConfigManager.set_value_and_save("AccentColor", keys[index])
		_apply_accent(keys[index])


func _on_export_theme_selected(index: int) -> void:
	var keys := ["fancy", "clean", "league_client"]
	if index >= 0 and index < keys.size():
		ConfigManager.set_value_and_save("UIStyle", keys[index])
		_setup_export_safe_theme_dropdowns()
		_apply_accent(String(ConfigManager.get_value("AccentColor", "white")))


func _set_version_label() -> void:
	if not home_view:
		return
	var version_lbl := home_view.get_node_or_null("version") as Label
	if version_lbl:
		version_lbl.text = "%s  %s %s" % [Constants.APP_CHANNEL, Constants.APP_CODENAME, Constants.APP_VERSION]



func _play_home_title_entrance() -> void:
	if not home_view:
		return
	if _home_title_tween and _home_title_tween.is_valid():
		_home_title_tween.kill()

	var riot_lbl := home_view.get_node_or_null("riot") as Control
	var switcher_lbl := home_view.get_node_or_null("switcher") as Control
	var version_lbl := home_view.get_node_or_null("version") as Control
	var nodes: Array[Control] = []
	if riot_lbl: nodes.append(riot_lbl)
	if switcher_lbl: nodes.append(switcher_lbl)
	if version_lbl: nodes.append(version_lbl)
	if nodes.is_empty():
		return

	_home_title_tween = create_tween().set_parallel(true)
	for i in range(nodes.size()):
		var n := nodes[i]
		var target_alpha := 0.66 if n == version_lbl else 1.0
		var target_y := -26.0 if n == version_lbl else -60.0
		n.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in n
		if has_offset:
			n.set("offset_transform_enabled", true)
			n.set("offset_transform_position", Vector2(0.0, -8.0))
			n.set("offset_transform_visual_only", true)
		else:
			n.position.y = target_y - 8.0

		var delay := i * 0.02
		_home_title_tween.tween_property(n, "modulate:a", target_alpha, 0.16).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			_home_title_tween.tween_property(n, "offset_transform_position", Vector2.ZERO, 0.18).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_home_title_tween.tween_property(n, "position:y", target_y, 0.18).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_startup_entrance() -> void:
	# Start fully transparent
	modulate.a = 0.0

	if left_menu_handler:
		left_menu_handler.modulate.a = 0.0

	# Wait for the transparent window to be composited before showing the scene.
	await get_tree().process_frame
	await get_tree().process_frame
	visible = true
	await get_tree().process_frame

	# 1.
	const FADE_DURATION := 0.2
	var window_tween := create_tween()
	window_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2.
	if left_menu_handler:
		var left_tween := create_tween()
		left_tween.tween_property(left_menu_handler, "modulate:a", 1.0, FADE_DURATION).set_delay(0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3.
	_play_home_title_entrance()

	# 4.
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



func _on_configs_updated(new_config_data: Dictionary) -> void:
	_apply_accent(String(new_config_data.get("AccentColor", "white")))
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


func _on_profiles_updated(_profiles: Dictionary) -> void:
	_apply_accent(String(ConfigManager.get_value("AccentColor", "white")))


const COLOR_LEFTBAR_BG := Color(0.07058824, 0.07058824, 0.07058824, 1.0)
const COLOR_LEFTBAR_BG_HOVER := Color(0.115, 0.115, 0.115, 1.0)
const COLOR_LCU_BG := Color(0.0039, 0.0392, 0.0745, 1.0)
const COLOR_LCU_PANEL_BG := Color(0.0039, 0.0392, 0.0745, 0.92)
const COLOR_LCU_BTN_BG := Color(0.1176, 0.1373, 0.1569, 0.96)
const COLOR_LCU_BTN_HOVER := Color(0.165, 0.19, 0.22, 0.98)
const COLOR_LCU_GOLD := Color(0.7843, 0.6667, 0.4314, 1.0)
const COLOR_LCU_GOLD_BRIGHT := Color(0.9412, 0.902, 0.8235, 1.0)
const COLOR_LCU_GOLD_BORDER := Color(0.62, 0.48, 0.22, 0.95)
const COLOR_LCU_CYAN := Color(0.04, 0.78, 0.73, 0.92)


func _ensure_or_update_border_rect(
	parent: Control,
	node_name: String,
	z_idx: int,
	a_left: float,
	a_top: float,
	a_right: float,
	a_bottom: float,
	o_left: float,
	o_top: float,
	o_right: float,
	o_bottom: float,
	col: Color,
	is_vis: bool
) -> void:
	if not parent:
		return
	var rect := parent.get_node_or_null(node_name) as ColorRect
	if not rect and is_vis:
		rect = ColorRect.new()
		rect.name = node_name
		rect.z_index = z_idx
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.anchor_left = a_left
		rect.anchor_top = a_top
		rect.anchor_right = a_right
		rect.anchor_bottom = a_bottom
		rect.offset_left = o_left
		rect.offset_top = o_top
		rect.offset_right = o_right
		rect.offset_bottom = o_bottom
		parent.add_child(rect)
	if rect:
		rect.color = col
		rect.visible = is_vis


func _ensure_lcu_window_borders(is_league: bool) -> void:
	var old_top := get_node_or_null("lcu_top_gold_bar") as ColorRect
	if old_top:
		old_top.visible = false
	var border_col := Color(COLOR_LCU_GOLD.r, COLOR_LCU_GOLD.g, COLOR_LCU_GOLD.b, 0.18)
	if left_menu_handler:
		var right_border := left_menu_handler.get_node_or_null("border") as ColorRect
		if right_border:
			border_col = right_border.color
		# Left bar perimeter (x = 0..79; right edge at x = 79..80 is already 'leftmenu_side/border')
		_ensure_or_update_border_rect(left_menu_handler, "lcu_border_left", 3, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, border_col, is_league)
		_ensure_or_update_border_rect(left_menu_handler, "lcu_border_top", 3, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 79.0, 1.0, border_col, is_league)
		_ensure_or_update_border_rect(left_menu_handler, "lcu_border_bottom", 3, 0.0, 1.0, 0.0, 1.0, 1.0, -1.0, 79.0, 0.0, border_col, is_league)
	# Main app perimeter (x = 80..width)
	_ensure_or_update_border_rect(self, "lcu_app_border_top", 105, 0.0, 0.0, 1.0, 0.0, 80.0, 0.0, 0.0, 1.0, border_col, is_league)
	_ensure_or_update_border_rect(self, "lcu_app_border_bottom", 105, 0.0, 1.0, 1.0, 1.0, 80.0, -1.0, 0.0, 0.0, border_col, is_league)
	_ensure_or_update_border_rect(self, "lcu_app_border_right", 105, 1.0, 0.0, 1.0, 1.0, -1.0, 1.0, 0.0, -1.0, border_col, is_league)


func _apply_accent(preset: String) -> void:
	var ui_style := String(ConfigManager.get_value("UIStyle", "clean")).to_lower()
	var is_clean: bool = (ui_style == "clean")
	var is_league: bool = (ui_style == "league_client")
	var accent: Color = COLOR_LCU_GOLD if is_league else ACCENT_PRESETS.get(preset.to_lower(), ACCENT_PRESETS["white"])
	var bg_rect := get_node_or_null("bg_test") as ColorRect
	if bg_rect:
		bg_rect.color = COLOR_LCU_BG if is_league else Color(0, 0, 0, 1)
	var hex_bg := get_node_or_null("hextech_bg") as Control
	if hex_bg:
		hex_bg.visible = not is_clean
		hex_bg.modulate = Color(1.0, 0.88, 0.62, 0.42) if is_league else Color(1, 1, 1, 0.24)
	var accent_setting := find_child("cleanlogs", true, false)
	if accent_setting and accent_setting.has_method("apply_accent_color"):
		accent_setting.apply_accent_color(accent)
	_apply_accent_to_tree(self, accent, is_clean, is_league)
	var riot_label := home_view.get_node_or_null("riot") as Label if home_view else null
	if riot_label:
		riot_label.add_theme_color_override("font_color", COLOR_LCU_GOLD_BRIGHT if is_league else Color.WHITE)
	var switcher_label := home_view.get_node_or_null("switcher") as Label if home_view else null
	if switcher_label:
		switcher_label.add_theme_color_override("font_color", Color(0.757, 0.0, 0.116, 1.0) if (is_clean or is_league) else accent)
	_ensure_lcu_window_borders(is_league)
	if left_menu_handler:
		if left_menu_handler.has_method("apply_accent_color"):
			left_menu_handler.apply_accent_color(accent)
		else:
			left_menu_handler.set("color_home", accent)
			left_menu_handler.set("color_add_profile", accent)
			left_menu_handler.set("color_settings", accent)


func _apply_accent_to_tree(node: Node, accent: Color, is_clean: bool = false, is_league: bool = false) -> void:
	if node.name == "upper_side" or node.name == "iconhighlight" or node.name.begins_with("lcu_"):
		return
	if home_view and (node == home_view.get_node_or_null("riot") or node == home_view.get_node_or_null("switcher")):
		return
	if node is Control:
		_apply_accent_to_control(node as Control, accent, is_clean, is_league)
	if node is ProfileButton:
		return
	for child in node.get_children():
		_apply_accent_to_tree(child, accent, is_clean, is_league)


func _duplicate_stylebox_deep(sb: StyleBox) -> StyleBox:
	if sb == null:
		return null
	var copy: StyleBox = sb.duplicate(true)
	if copy is StyleBoxFancy:
		var fancy := copy as StyleBoxFancy
		var new_borders: Array[StyleBorder] = []
		for b in fancy.borders:
			if b != null:
				new_borders.append(b.duplicate() as StyleBorder)
		fancy.borders = new_borders
	return copy


func _is_settings_card_panel(control: Control) -> bool:
	if not (control is Panel and control.name == "Panel"):
		return false
	var p := control.get_parent()
	if not p:
		return false
	var gp := p.get_parent()
	return gp != null and settings_menu != null and gp.get_parent() == settings_menu and gp is GridContainer


func _apply_clean_settings_card_panel(panel_node: Panel, styled: StyleBoxFancy) -> void:
	var card := panel_node.get_parent()
	var col_idx: int = card.get_index() % 2 if card else 0
	styled.color = Color(0.0, 0.0, 0.0, 0.0)
	styled.corner_radius_top_left = 0
	styled.corner_radius_top_right = 0
	styled.corner_radius_bottom_right = 0
	styled.corner_radius_bottom_left = 0
	styled.corner_curvature_top_left = 0.0
	styled.corner_curvature_top_right = 0.0
	styled.corner_curvature_bottom_right = 0.0
	styled.corner_curvature_bottom_left = 0.0
	var b := StyleBorder.new()
	b.color = Color(1.0, 1.0, 1.0, 0.337255)
	if col_idx == 0:
		b.width_left = 2
		b.width_top = 2
		b.width_bottom = 2
		b.width_right = 0
	else:
		b.width_top = 2
		b.width_right = 2
		b.width_bottom = 2
		b.width_left = 0
	var borders_arr: Array[StyleBorder] = [b]
	styled.borders = borders_arr


func _apply_league_settings_card_panel(styled: StyleBoxFancy) -> void:
	styled.color = Color(0.0039, 0.0392, 0.0745, 0.88)
	styled.corner_radius_top_left = 0
	styled.corner_radius_top_right = 0
	styled.corner_radius_bottom_right = 0
	styled.corner_radius_bottom_left = 0
	var b_outer := StyleBorder.new()
	b_outer.width_left = 2
	b_outer.width_top = 1
	b_outer.width_right = 1
	b_outer.width_bottom = 1
	b_outer.color = COLOR_LCU_GOLD_BORDER
	var b_inner := StyleBorder.new()
	b_inner.set_width_all(1)
	b_inner.set_inset_all(3)
	b_inner.color = Color(0.7843, 0.6667, 0.4314, 0.18)
	var borders_arr: Array[StyleBorder] = [b_outer, b_inner]
	styled.borders = borders_arr


func _apply_accent_to_control(control: Control, accent: Color, is_clean: bool = false, is_league: bool = false) -> void:
	if control.has_method("apply_accent_color"):
		control.apply_accent_color(accent)
	if control.has_method("set_accent_color"):
		control.set_accent_color(accent)
	if control is ProfileButton:
		return
	if control is TextureRect and (control.name == "title_divider" or control.name == "preview_divider"):
		control.visible = not is_clean

	var id := str(control.get_instance_id())
	if control is ColorRect:
		var direct_key := id + ":color"
		var current_direct := (control as ColorRect).color
		if not _accent_color_sources.has(direct_key) and _is_hextech_gold(current_direct):
			_accent_color_sources[direct_key] = current_direct
		if _accent_color_sources.has(direct_key):
			var orig_cr: Color = _accent_color_sources[direct_key]
			(control as ColorRect).color = Color(1.0, 1.0, 1.0, orig_cr.a) if is_clean else _accent_variant(orig_cr, accent)
	if control is TextureRect and not (left_menu_handler and left_menu_handler.is_ancestor_of(control)):
		var texture_key := id + ":modulate"
		var current_modulate := (control as TextureRect).modulate
		if not _accent_modulate_sources.has(texture_key) and _is_hextech_gold(current_modulate):
			_accent_modulate_sources[texture_key] = current_modulate
		if _accent_modulate_sources.has(texture_key):
			var orig_mod: Color = _accent_modulate_sources[texture_key]
			(control as TextureRect).modulate = Color(1.0, 1.0, 1.0, orig_mod.a) if is_clean else _accent_variant(orig_mod, accent)

	var is_vanguard_title: bool = (
		control is Label
		and control.name == "Label"
		and control.get_parent() != null
		and control.get_parent().get_parent() != null
		and control.get_parent().get_parent().name == "vanguard"
	)

	for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_disabled_color", &"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"font_outline_color"]:
		var key := id + ":color:" + String(color_name)
		var current := control.get_theme_color(color_name)
		if not _accent_color_sources.has(key) and _is_hextech_gold(current):
			_accent_color_sources[key] = current
		if _accent_color_sources.has(key):
			var orig_col: Color = _accent_color_sources[key]
			if is_clean:
				if is_vanguard_title and color_name == &"font_color":
					control.add_theme_color_override(color_name, Color(0.815, 0.0, 0.0, 1.0))
				else:
					control.add_theme_color_override(color_name, Color(1.0, 1.0, 1.0, orig_col.a))
			elif is_league:
				control.add_theme_color_override(color_name, COLOR_LCU_GOLD_BRIGHT if color_name == &"font_hover_color" else orig_col)
			else:
				control.add_theme_color_override(color_name, _accent_variant(orig_col, accent))

	for style_name in [&"panel", &"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled", &"read_only", &"grabber", &"grabber_highlight", &"grabber_pressed", &"scroll", &"separator"]:
		var sname: StringName = style_name
		var style_key := id + ":style:" + String(sname)
		if not _accent_style_sources.has(style_key):
			var original := control.get_theme_stylebox(sname)
			if original and (_stylebox_has_gold(original) or original is StyleBoxFancy):
				_accent_style_sources[style_key] = _duplicate_stylebox_deep(original)
		if _accent_style_sources.has(style_key):
			var styled: StyleBox = _duplicate_stylebox_deep(_accent_style_sources[style_key] as StyleBox)
			if is_clean and sname == &"panel" and styled is StyleBoxFancy and _is_settings_card_panel(control):
				_apply_clean_settings_card_panel(control as Panel, styled as StyleBoxFancy)
			elif is_league and sname == &"panel" and styled is StyleBoxFancy and _is_settings_card_panel(control):
				_apply_league_settings_card_panel(styled as StyleBoxFancy)
			else:
				_recolor_stylebox(styled, accent, is_clean, is_league, sname, control)
			control.add_theme_stylebox_override(sname, styled)
	if control is VScrollBar:
		var bar_col: Color = Color(1.0, 1.0, 1.0, 0.45) if is_clean else (COLOR_LCU_GOLD if is_league else accent)
		for scrollbar_style_name in [&"grabber", &"grabber_highlight", &"grabber_pressed"]:
			var sb_sname: StringName = scrollbar_style_name
			var scrollbar_style := control.get_theme_stylebox(sb_sname)
			if scrollbar_style is StyleBoxFlat:
				var scrollbar_copy := scrollbar_style.duplicate(true) as StyleBoxFlat
				var scrollbar_alpha := scrollbar_copy.bg_color.a
				scrollbar_copy.bg_color = bar_col
				scrollbar_copy.bg_color.a = (0.45 if sb_sname == &"grabber" else 0.7) if is_clean else (scrollbar_alpha if scrollbar_alpha > 0.01 else 0.9)
				control.add_theme_stylebox_override(sb_sname, scrollbar_copy)
	if control is CheckButton:
		var chk_col: Color = Color.WHITE if is_clean else (COLOR_LCU_GOLD if is_league else accent)
		control.add_theme_color_override("font_color", chk_col)
		control.add_theme_color_override("font_hover_color", Color.WHITE if is_clean else (COLOR_LCU_GOLD_BRIGHT if is_league else accent.lightened(0.12)))
		control.add_theme_color_override("font_pressed_color", chk_col)
		control.modulate = chk_col
	if control is OptionButton:
		var opt := control as OptionButton
		var opt_col: Color = Color(0.92, 0.92, 0.96, 1.0) if is_clean else (COLOR_LCU_GOLD_BRIGHT if is_league else accent)
		var opt_hov_col: Color = Color.WHITE if is_clean else (COLOR_LCU_GOLD_BRIGHT if is_league else accent.lightened(0.18))
		opt.add_theme_color_override("font_color", opt_col)
		opt.add_theme_color_override("font_hover_color", opt_hov_col)
		opt.add_theme_color_override("font_pressed_color", opt_col)
		opt.add_theme_color_override("font_focus_color", opt_col)
		opt.add_theme_color_override("font_hover_pressed_color", opt_hov_col)
		opt.add_theme_color_override("icon_normal_color", opt_col)
		opt.add_theme_color_override("icon_hover_color", opt_hov_col)
		opt.add_theme_color_override("icon_pressed_color", opt_col)
		opt.add_theme_color_override("icon_focus_color", opt_col)
		opt.add_theme_constant_override("modulate_arrow", 1)
		for option_style_name in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
			var opt_sname: StringName = option_style_name
			var opt_key := id + ":style:" + String(opt_sname)
			if not _accent_style_sources.has(opt_key):
				var orig_opt := opt.get_theme_stylebox(opt_sname)
				if orig_opt:
					_accent_style_sources[opt_key] = _duplicate_stylebox_deep(orig_opt)
			var option_source: StyleBox = _accent_style_sources.get(opt_key, null) as StyleBox
			if option_source:
				var option_style := _duplicate_stylebox_deep(option_source)
				var is_hov: bool = (opt_sname != &"normal")
				if option_style is StyleBoxFlat:
					var option_flat := option_style as StyleBoxFlat
					if is_clean:
						option_flat.bg_color = Color(0.82, 0.18, 0.22, 0.9) if is_hov else COLOR_LEFTBAR_BG
						option_flat.border_color = Color(1.0, 0.3, 0.3, 0.8) if is_hov else Color(1.0, 1.0, 1.0, 0.16)
					elif is_league:
						option_flat.bg_color = COLOR_LCU_BTN_HOVER if is_hov else COLOR_LCU_BTN_BG
						option_flat.border_color = COLOR_LCU_GOLD_BRIGHT if is_hov else COLOR_LCU_GOLD_BORDER
					else:
						option_flat.bg_color = COLOR_LEFTBAR_BG_HOVER if is_hov else COLOR_LEFTBAR_BG
						option_flat.border_color = accent
						option_flat.border_color.a = 0.72 if is_hov else 0.45
					opt.add_theme_stylebox_override(opt_sname, option_style)
				elif option_style is StyleBoxFancy:
					var option_fancy := option_style as StyleBoxFancy
					if is_clean:
						option_fancy.color = Color(0.82, 0.18, 0.22, 0.9) if is_hov else COLOR_LEFTBAR_BG
						var ob := StyleBorder.new()
						ob.set_width_all(1)
						ob.color = Color(1.0, 0.3, 0.3, 0.8) if is_hov else Color(1.0, 1.0, 1.0, 0.16)
						var ob_arr: Array[StyleBorder] = [ob]
						option_fancy.borders = ob_arr
						option_fancy.corner_detail = 12
						option_fancy.corner_radius_top_left = 8
						option_fancy.corner_radius_top_right = 8
						option_fancy.corner_radius_bottom_right = 8
						option_fancy.corner_radius_bottom_left = 8
						option_fancy.corner_curvature_top_left = 1.0
						option_fancy.corner_curvature_top_right = 1.0
						option_fancy.corner_curvature_bottom_right = 1.0
						option_fancy.corner_curvature_bottom_left = 1.0
					elif is_league:
						option_fancy.color = COLOR_LCU_BTN_HOVER if is_hov else COLOR_LCU_BTN_BG
						var lob := StyleBorder.new()
						lob.set_width_all(1)
						lob.color = COLOR_LCU_GOLD_BRIGHT if is_hov else COLOR_LCU_GOLD_BORDER
						var lob_arr: Array[StyleBorder] = [lob]
						option_fancy.borders = lob_arr
						option_fancy.corner_radius_top_left = 0
						option_fancy.corner_radius_top_right = 0
						option_fancy.corner_radius_bottom_right = 0
						option_fancy.corner_radius_bottom_left = 0
					else:
						option_fancy.color = COLOR_LEFTBAR_BG_HOVER if is_hov else COLOR_LEFTBAR_BG
						for border in option_fancy.borders:
							if border:
								var b_alpha := border.color.a if border.color.a > 0.01 else 0.88
								border.color = accent.lightened(0.14) if is_hov else accent
								border.color.a = b_alpha
					opt.add_theme_stylebox_override(opt_sname, option_style)
		_apply_accent_to_popup_menu(opt.get_popup(), accent, is_clean, is_league)
	if control is ScrollContainer:
		_apply_accent_to_scrollbar((control as ScrollContainer).get_v_scroll_bar(), accent, is_clean, is_league)


func _apply_accent_to_popup_menu(popup: PopupMenu, accent: Color, is_clean: bool = false, is_league: bool = false) -> void:
	if not popup:
		return
	var pop_font: Color = Color(0.92, 0.92, 0.96, 1.0) if is_clean else (COLOR_LCU_GOLD_BRIGHT if is_league else accent)
	var pop_hov_font: Color = Color.WHITE if is_clean else (COLOR_LCU_GOLD_BRIGHT if is_league else accent.lightened(0.22))
	var pop_sep: Color = Color(1.0, 1.0, 1.0, 0.12) if is_clean else Color(accent.r, accent.g, accent.b, 0.72)
	popup.add_theme_color_override("font_color", pop_font)
	popup.add_theme_color_override("font_hover_color", pop_hov_font)
	popup.add_theme_color_override("font_separator_color", pop_sep)
	var panel_bg := COLOR_LCU_BG if is_league else COLOR_LEFTBAR_BG
	var panel_sb := popup.get_theme_stylebox("panel")
	if panel_sb is StyleBoxFlat:
		var panel_copy := (panel_sb as StyleBoxFlat).duplicate(true) as StyleBoxFlat
		panel_copy.bg_color = panel_bg
		panel_copy.border_color = Color(1.0, 1.0, 1.0, 0.18) if is_clean else (COLOR_LCU_GOLD_BORDER if is_league else Color(accent.r, accent.g, accent.b, 0.85))
		popup.add_theme_stylebox_override("panel", panel_copy)
	elif panel_sb is StyleBoxFancy:
		var panel_fancy := _duplicate_stylebox_deep(panel_sb) as StyleBoxFancy
		panel_fancy.color = panel_bg
		if is_clean:
			var pb := StyleBorder.new()
			pb.set_width_all(1)
			pb.color = Color(1.0, 1.0, 1.0, 0.18)
			var pb_arr: Array[StyleBorder] = [pb]
			panel_fancy.borders = pb_arr
			panel_fancy.corner_detail = 12
			panel_fancy.corner_radius_top_left = 6
			panel_fancy.corner_radius_top_right = 6
			panel_fancy.corner_radius_bottom_right = 6
			panel_fancy.corner_radius_bottom_left = 6
			panel_fancy.corner_curvature_top_left = 1.0
			panel_fancy.corner_curvature_top_right = 1.0
			panel_fancy.corner_curvature_bottom_right = 1.0
			panel_fancy.corner_curvature_bottom_left = 1.0
		elif is_league:
			var lpb := StyleBorder.new()
			lpb.set_width_all(1)
			lpb.color = COLOR_LCU_GOLD_BORDER
			var lpb_arr: Array[StyleBorder] = [lpb]
			panel_fancy.borders = lpb_arr
			panel_fancy.corner_radius_top_left = 0
			panel_fancy.corner_radius_top_right = 0
			panel_fancy.corner_radius_bottom_right = 0
			panel_fancy.corner_radius_bottom_left = 0
		else:
			for border in panel_fancy.borders:
				if border:
					border.color = Color(accent.r, accent.g, accent.b, border.color.a if border.color.a > 0.01 else 0.85)
		popup.add_theme_stylebox_override("panel", panel_fancy)
	var hover_sb := popup.get_theme_stylebox("hover")
	if hover_sb is StyleBoxFlat:
		var hover_copy := (hover_sb as StyleBoxFlat).duplicate(true) as StyleBoxFlat
		hover_copy.bg_color = Color(0.82, 0.18, 0.22, 0.85) if is_clean else (COLOR_LCU_BTN_HOVER if is_league else Color(accent.r, accent.g, accent.b, 0.18))
		hover_copy.border_color = Color(1.0, 0.3, 0.3, 0.8) if is_clean else (COLOR_LCU_GOLD if is_league else Color(accent.r, accent.g, accent.b, 0.65))
		popup.add_theme_stylebox_override("hover", hover_copy)
	var sep_sb := popup.get_theme_stylebox("separator")
	if sep_sb is StyleBoxLine:
		var sep_copy := (sep_sb as StyleBoxLine).duplicate(true) as StyleBoxLine
		sep_copy.color = pop_sep
		popup.add_theme_stylebox_override("separator", sep_copy)


func _apply_accent_to_scrollbar(scrollbar: VScrollBar, accent: Color, is_clean: bool = false, is_league: bool = false) -> void:
	if not scrollbar:
		return
	var grab_col: Color = Color(1.0, 1.0, 1.0, 0.45) if is_clean else (COLOR_LCU_GOLD if is_league else accent)
	for style_name in [&"grabber", &"grabber_highlight", &"grabber_pressed", &"scroll"]:
		var sname: StringName = style_name
		var source := scrollbar.get_theme_stylebox(sname)
		if not source:
			continue
		var styled := source.duplicate(true) as StyleBox
		if styled is StyleBoxFlat:
			var flat := styled as StyleBoxFlat
			if sname == &"scroll":
				flat.bg_color = COLOR_LCU_BG if is_league else COLOR_LEFTBAR_BG
				flat.border_color = Color(0, 0, 0, 0)
			else:
				var alpha := flat.bg_color.a
				flat.bg_color = grab_col
				flat.bg_color.a = (0.45 if sname == &"grabber" else 0.7) if is_clean else (alpha if alpha > 0.01 else 0.9)
				flat.border_color = grab_col
				flat.border_color.a = minf(flat.border_color.a, 0.9)
			scrollbar.add_theme_stylebox_override(sname, styled)


func _is_hextech_gold(color: Color) -> bool:
	return color.a > 0.01 and color.h > 0.065 and color.h < 0.18 and color.s > 0.20 and color.v > 0.10


func _accent_variant(original: Color, accent: Color) -> Color:
	var result: Color = accent
	if original.v < 0.35:
		var ratio: float = float(clampf(float(original.v) / 0.78, 0.18, 1.0))
		result = accent.darkened(1.0 - ratio)
	result.a = original.a
	return result


func _stylebox_has_gold(stylebox: StyleBox) -> bool:
	if stylebox is StyleBoxFlat:
		var flat := stylebox as StyleBoxFlat
		return _is_hextech_gold(flat.bg_color) or _is_hextech_gold(flat.border_color) or _is_hextech_gold(flat.shadow_color)
	if stylebox is StyleBoxFancy:
		var fancy := stylebox as StyleBoxFancy
		if _is_hextech_gold(fancy.color):
			return true
		for border in fancy.borders:
			if border and _is_hextech_gold(border.color):
				return true
	if stylebox is StyleBoxLine:
		var line := stylebox as StyleBoxLine
		return _is_hextech_gold(line.color)
	return false


func _recolor_stylebox(stylebox: StyleBox, accent: Color, is_clean: bool = false, is_league: bool = false, style_name: StringName = &"", control: Control = null) -> void:
	if stylebox is StyleBoxFlat:
		var flat := stylebox as StyleBoxFlat
		if is_clean:
			if flat.bg_color.a > 0.01:
				flat.bg_color = COLOR_LEFTBAR_BG
			flat.border_color = Color(1.0, 1.0, 1.0, 0.12 if flat.border_color.a > 0.01 else 0.0)
		elif is_league:
			if flat.bg_color.a > 0.01:
				flat.bg_color = COLOR_LCU_PANEL_BG
			if flat.border_color.a > 0.01:
				flat.border_color = COLOR_LCU_GOLD_BORDER
		else:
			if _is_hextech_gold(flat.bg_color): flat.bg_color = _accent_variant(flat.bg_color, accent)
			if _is_hextech_gold(flat.border_color): flat.border_color = _accent_variant(flat.border_color, accent)
			if _is_hextech_gold(flat.shadow_color): flat.shadow_color = _accent_variant(flat.shadow_color, accent)
	elif stylebox is StyleBoxFancy:
		var fancy := stylebox as StyleBoxFancy
		var is_in_settings: bool = (control != null and settings_menu != null and settings_menu.is_ancestor_of(control))
		var is_hov: bool = (style_name == &"hover" or style_name == &"pressed" or style_name == &"hover_pressed")
		var is_bg_card_btn: bool = (control != null and control.get_parent() != null and control.get_parent().name.begins_with("bgexample"))
		var is_root_view_panel: bool = (control != null and control.name == "Panel" and (control.get_parent() == settings_menu or control.get_parent() == add_menu))
		if is_clean:
			fancy.corner_detail = 12
			fancy.corner_curvature_top_left = 1.0
			fancy.corner_curvature_top_right = 1.0
			fancy.corner_curvature_bottom_right = 1.0
			fancy.corner_curvature_bottom_left = 1.0
			if control is Button and not (control is OptionButton) and not (control is CheckButton):
				var is_primary_cta: bool = (control.name == "create_button" or control.name == "save_button")
				if is_bg_card_btn:
					fancy.color = Color(1.0, 1.0, 1.0, 0.08) if is_hov else Color(0.0, 0.0, 0.0, 0.0)
					var bb := StyleBorder.new()
					bb.set_width_all(1)
					bb.color = Color(1.0, 1.0, 1.0, 0.28 if is_hov else 0.08)
					var bb_arr: Array[StyleBorder] = [bb]
					fancy.borders = bb_arr
					fancy.corner_radius_top_left = 8
					fancy.corner_radius_top_right = 8
					fancy.corner_radius_bottom_right = 8
					fancy.corner_radius_bottom_left = 8
				elif is_primary_cta:
					fancy.color = Color(0.92, 0.08, 0.24, 1.0) if is_hov else Color(0.82, 0.0, 0.18, 1.0)
					var empty_b: Array[StyleBorder] = []
					fancy.borders = empty_b
					fancy.corner_radius_top_left = 8
					fancy.corner_radius_top_right = 8
					fancy.corner_radius_bottom_right = 8
					fancy.corner_radius_bottom_left = 8
				elif is_in_settings and control.name != "cancel_button":
					fancy.color = Color(0.82, 0.18, 0.22, 0.9) if is_hov else COLOR_LEFTBAR_BG
					var sb := StyleBorder.new()
					sb.set_width_all(1)
					sb.color = Color(1.0, 0.3, 0.3, 0.8) if is_hov else Color(1.0, 1.0, 1.0, 0.16)
					var sb_arr: Array[StyleBorder] = [sb]
					fancy.borders = sb_arr
					fancy.corner_radius_top_left = 8
					fancy.corner_radius_top_right = 8
					fancy.corner_radius_bottom_right = 8
					fancy.corner_radius_bottom_left = 8
				else:
					fancy.color = COLOR_LEFTBAR_BG_HOVER if is_hov else COLOR_LEFTBAR_BG
					var gb := StyleBorder.new()
					gb.set_width_all(1)
					gb.color = Color(1.0, 1.0, 1.0, 0.20 if is_hov else 0.12)
					var gb_arr: Array[StyleBorder] = [gb]
					fancy.borders = gb_arr
					fancy.corner_radius_top_left = 8
					fancy.corner_radius_top_right = 8
					fancy.corner_radius_bottom_right = 8
					fancy.corner_radius_bottom_left = 8
			elif control != null and control.name == "bg" and left_menu_handler != null and control.get_parent() == left_menu_handler:
				fancy.color = COLOR_LEFTBAR_BG
				var lb := StyleBorder.new()
				lb.width_right = 1
				lb.color = Color(1.0, 1.0, 1.0, 0.055)
				var lb_arr: Array[StyleBorder] = [lb]
				fancy.borders = lb_arr
			elif is_root_view_panel:
				fancy.color = Color(0.0, 0.0, 0.0, 0.0)
				var empty_panel_b: Array[StyleBorder] = []
				fancy.borders = empty_panel_b
			else:
				if fancy.color.a > 0.08 and not is_bg_card_btn:
					fancy.color = COLOR_LEFTBAR_BG
				var has_visible_border := false
				for b in fancy.borders:
					if b and b.color.a > 0.01 and (b.width_left > 0 or b.width_top > 0 or b.width_right > 0 or b.width_bottom > 0):
						has_visible_border = true
						break
				if has_visible_border:
					var nb := StyleBorder.new()
					nb.set_width_all(1)
					nb.color = Color(1.0, 1.0, 1.0, 0.14)
					var nb_arr: Array[StyleBorder] = [nb]
					fancy.borders = nb_arr
				else:
					var empty_nb: Array[StyleBorder] = []
					fancy.borders = empty_nb
				if fancy.corner_radius_top_left > 0 or fancy.corner_radius_top_right > 0 or fancy.corner_radius_bottom_right > 0 or fancy.corner_radius_bottom_left > 0:
					fancy.corner_radius_top_left = 8
					fancy.corner_radius_top_right = 8
					fancy.corner_radius_bottom_right = 8
					fancy.corner_radius_bottom_left = 8
		elif is_league:
			fancy.corner_radius_top_left = 0
			fancy.corner_radius_top_right = 0
			fancy.corner_radius_bottom_right = 0
			fancy.corner_radius_bottom_left = 0
			if control is Button and not (control is OptionButton) and not (control is CheckButton):
				var is_primary_cta_lcu: bool = (control.name == "create_button" or control.name == "save_button")
				if is_bg_card_btn:
					fancy.color = Color(0.7843, 0.6078, 0.2353, 0.12) if is_hov else Color(0.0, 0.0, 0.0, 0.0)
					var lbb := StyleBorder.new()
					lbb.set_width_all(1)
					lbb.color = COLOR_LCU_GOLD_BRIGHT if is_hov else Color(0.62, 0.48, 0.22, 0.45)
					var lbb_arr: Array[StyleBorder] = [lbb]
					fancy.borders = lbb_arr
				elif is_primary_cta_lcu:
					fancy.color = Color(0.04, 0.20, 0.28, 0.98) if is_hov else Color(0.0235, 0.1255, 0.1882, 0.96)
					var lcta_out := StyleBorder.new()
					lcta_out.set_width_all(1)
					lcta_out.color = COLOR_LCU_GOLD_BORDER
					var lcta_in := StyleBorder.new()
					lcta_in.set_width_all(1)
					lcta_in.set_inset_all(2)
					lcta_in.color = Color(0.25, 0.94, 0.92, 1.0) if is_hov else COLOR_LCU_CYAN
					var lcta_arr: Array[StyleBorder] = [lcta_out, lcta_in]
					fancy.borders = lcta_arr
				else:
					fancy.color = COLOR_LCU_BTN_HOVER if is_hov else COLOR_LCU_BTN_BG
					var lbtn_b := StyleBorder.new()
					lbtn_b.set_width_all(1)
					lbtn_b.color = COLOR_LCU_GOLD_BRIGHT if is_hov else COLOR_LCU_GOLD_BORDER
					var lbtn_arr: Array[StyleBorder] = [lbtn_b]
					fancy.borders = lbtn_arr
			elif is_root_view_panel:
				fancy.color = Color(0.0, 0.0, 0.0, 0.0)
				var empty_lcu_panel: Array[StyleBorder] = []
				fancy.borders = empty_lcu_panel
			else:
				if fancy.color.a > 0.08 and not is_bg_card_btn:
					fancy.color = COLOR_LCU_PANEL_BG
				var lcu_borders: Array[StyleBorder] = []
				for border in fancy.borders:
					var clone := border.duplicate() as StyleBorder if border else null
					if clone and _is_hextech_gold(clone.color):
						clone.color = COLOR_LCU_GOLD_BRIGHT if style_name == &"focus" else COLOR_LCU_GOLD_BORDER
					lcu_borders.append(clone)
				fancy.borders = lcu_borders
		else:
			if _is_hextech_gold(fancy.color):
				fancy.color = _accent_variant(fancy.color, accent)
			elif fancy.color.a > 0.08 and not is_bg_card_btn and not is_root_view_panel:
				fancy.color = COLOR_LEFTBAR_BG_HOVER if is_hov else COLOR_LEFTBAR_BG
			var cloned_borders: Array[StyleBorder] = []
			for border in fancy.borders:
				var clone := border.duplicate() as StyleBorder if border else null
				if clone and _is_hextech_gold(clone.color):
					clone.color = _accent_variant(clone.color, accent)
				cloned_borders.append(clone)
			fancy.borders = cloned_borders
	elif stylebox is StyleBoxLine:
		var line := stylebox as StyleBoxLine
		if is_clean:
			line.color = Color(1.0, 1.0, 1.0, 0.12)
		elif is_league:
			line.color = COLOR_LCU_GOLD_BORDER
		elif _is_hextech_gold(line.color):
			line.color = _accent_variant(line.color, accent)


func _on_add_menu_warning_dismissed() -> void:
	if not ConfigManager.set_value_and_save("warning_shown", false):
		printerr("Main: Failed to save warning state.")



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
		if needs_tween:
			_play_home_title_entrance()
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
	_set_background_context("home")
	_switch_to_view(home_view)


func _show_settings_view() -> void:
	_set_background_context("settings")
	_switch_to_view(settings_menu)


func _show_add_profile_view() -> void:
	_set_background_context("add")
	if add_menu and add_menu.has_method("reset_form"):
		add_menu.reset_form()
	_switch_to_view(add_menu)


func _set_background_context(context: String) -> void:
	# The background is a static scene texture; menu changes do not mutate it.
	return


func _on_profile_creation_success() -> void:
	left_menu_handler.select_home()


func _on_edit_profile_requested(profile_data: Dictionary) -> void:
	if edit_profile_modal and edit_profile_modal.has_method("open_edit"):
		edit_profile_modal.open_edit(profile_data)



# Toggles the boot screen on/off, disabling processing and input when hidden so it never interferes with the main UI.
func _set_boot_visible(show_boot: bool) -> void:
	boot_screen.visible = show_boot
	boot_screen.set_process(show_boot)
	boot_screen.set_process_input(show_boot)
	# Block interaction with the content behind the boot screen.
	boot_screen.mouse_filter = Control.MOUSE_FILTER_STOP if show_boot else Control.MOUSE_FILTER_IGNORE



# Saves the running session and terminates the application cleanly.
func save_session_and_quit() -> void:
	if profile_grid and is_instance_valid(profile_grid):
		profile_grid.save_running_session()
	if PresenceManager != null:
		PresenceManager.stop_proxy()
	get_tree().quit()


# Closing the window hides it to the tray; the running session is saved so the account state is never lost.
func _hide_to_tray() -> void:
	if profile_grid and is_instance_valid(profile_grid):
		profile_grid.save_running_session()
	get_window().visible = false


func _on_tray_show_window_requested() -> void:
	get_window().visible = true
	DisplayServer.window_move_to_foreground()


func _on_tray_exit_requested() -> void:
	save_session_and_quit()
