@tool
class_name LeftMenuHandler
extends Control

# Left navigation rail: Home / Add Profile / Settings (LCU Hextech Navigation UI).

const TEX_SIDEBAR_LOGO := preload("res://assets/icons/no_bg.png")
const ICON_HOME_SVG := preload("res://assets/icons/ui/icon_home.svg")
const ICON_ADD_SVG := preload("res://assets/icons/ui/icon_add.svg")
const ICON_SETTINGS_SVG := preload("res://assets/icons/ui/icon_settings.svg")


@export_group("Highlight Glow Settings")
# Preview glow in the editor.
@export var preview_glow: bool = false:
	set(value):
		preview_glow = value
		_update_glow_preview()

@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 1.45:
	set(value):
		glow_intensity = value
		_update_glow()

@export_range(0.5, 6.0, 0.1) var glow_spread: float = 1.6:
	set(value):
		glow_spread = value
		_update_glow()

@export var glow_rect_size: Vector2 = Vector2(0.02, 0.10):
	set(value):
		glow_rect_size = value
		_update_glow()

@export_group("Menu Colors")
@export var color_home: Color = Color(0.7843, 0.6078, 0.2353, 1.0)        # #c89b3c Hextech Gold
@export var color_add_profile: Color = Color(0.7843, 0.6078, 0.2353, 1.0) # #c89b3c Hextech Gold
@export var color_settings: Color = Color(0.7843, 0.6667, 0.4314, 1.0)    # #c8aa6e Hextech Gold 3

signal home_selected
signal settings_selected
signal add_profile_selected

@onready var _add_button_panel: Control = $VBoxContainer/add_profile_button if has_node("VBoxContainer/add_profile_button") else get_node_or_null("add_profile_button")
@onready var _add_icon: TextureRect = $VBoxContainer/add_profile_button/Button/TextureRect if has_node("VBoxContainer/add_profile_button/Button/TextureRect") else get_node_or_null("add_profile_button/Button/TextureRect")
@onready var _add_selected_panel: Control = $VBoxContainer/add_profile_button/selected_panel if has_node("VBoxContainer/add_profile_button/selected_panel") else get_node_or_null("add_profile_button/selected_panel")

@onready var _home_button_panel: Control = $VBoxContainer/home_button if has_node("VBoxContainer/home_button") else get_node_or_null("home_button")
@onready var _home_icon: TextureRect = $VBoxContainer/home_button/Button/TextureRect if has_node("VBoxContainer/home_button/Button/TextureRect") else get_node_or_null("home_button/Button/TextureRect")
@onready var _home_selected_panel: Control = $VBoxContainer/home_button/selected_panel if has_node("VBoxContainer/home_button/selected_panel") else get_node_or_null("home_button/selected_panel")

@onready var _settings_button_panel: Control = $VBoxContainer/settings_button if has_node("VBoxContainer/settings_button") else get_node_or_null("settings_button")
@onready var _settings_icon: TextureRect = $VBoxContainer/settings_button/Button/TextureRect if has_node("VBoxContainer/settings_button/Button/TextureRect") else get_node_or_null("settings_button/Button/TextureRect")
@onready var _settings_selected_panel: Control = $VBoxContainer/settings_button/selected_panel if has_node("VBoxContainer/settings_button/selected_panel") else get_node_or_null("settings_button/selected_panel")

@onready var _icon_highlight: Control = $iconhighlight if has_node("iconhighlight") else null
@onready var _highlight_glow: Control = $iconhighlight/glow if has_node("iconhighlight/glow") else null
@onready var _highlight_panel: Panel = $iconhighlight/Panel if has_node("iconhighlight/Panel") else null
@onready var _vbox: Control = $VBoxContainer if has_node("VBoxContainer") else self

var _active_icon: TextureRect = null
var _active_button_panel: Control = null
var _highlight_tween: Tween = null
var _accent_color: Color = Color("c8aa6e")

const ACCENT_PRESETS: Dictionary = {
	"red": Color("ff0000"),
	"white": Color("f0e6d2"),
	"blue": Color("4f8fd8"),
	"gold": Color("c8aa6e"),
	"green": Color("45b878"),
	"violet": Color("9b70d8"),
	"cyan": Color("39c6c8"),
	"orange": Color("e08a3e"),
	"pink": Color("d96b9b"),
	"gray": Color("858b95"),
}


func _get_configured_accent_color() -> Color:
	if Engine.is_editor_hint():
		return color_home
	var preset := String(ConfigManager.get_value("AccentColor", "white")).to_lower()
	return ACCENT_PRESETS.get(preset, ACCENT_PRESETS["white"])


func _on_configs_updated(new_config: Dictionary) -> void:
	var preset := String(new_config.get("AccentColor", "white")).to_lower()
	var col: Color = ACCENT_PRESETS.get(preset, ACCENT_PRESETS["white"])
	apply_accent_color(col)


func _ready() -> void:
	_accent_color = _get_configured_accent_color()
	_apply_hextech_rail_visuals()
	_update_glow()
	_update_glow_preview()

	if _vbox is Container:
		if not _vbox.sort_children.is_connected(_sync_highlight_to_active_button):
			_vbox.sort_children.connect(_sync_highlight_to_active_button)
		# Force immediate synchronous container sort so button positions are valid in _ready()
		_vbox.notification(Container.NOTIFICATION_SORT_CHILDREN)

	if Engine.is_editor_hint():
		_active_button_panel = _home_button_panel
		_sync_highlight_to_active_button()
		return

	if not ConfigManager.configs_updated.is_connected(_on_configs_updated):
		ConfigManager.configs_updated.connect(_on_configs_updated)

	var home_btn := _get_button(_home_button_panel)
	if home_btn:
		if not home_btn.pressed.is_connected(_on_home_button_pressed):
			home_btn.pressed.connect(_on_home_button_pressed)

	var settings_btn := _get_button(_settings_button_panel)
	if settings_btn:
		if not settings_btn.pressed.is_connected(_on_settings_button_pressed):
			settings_btn.pressed.connect(_on_settings_button_pressed)

	var add_btn := _get_button(_add_button_panel)
	if add_btn:
		if not add_btn.pressed.is_connected(_on_add_profile_button_pressed):
			add_btn.pressed.connect(_on_add_profile_button_pressed)

	# Left rail uses the distinct League of Legends navigation tab sound.
	for panel in [_home_button_panel, _settings_button_panel, _add_button_panel]:
		var nav_btn := _get_button(panel)
		if nav_btn:
			nav_btn.set_meta("sfx", &"nav")

	# Snap immediately on startup without tweening from an unsorted position
	_update_selection(_home_selected_panel, _home_button_panel, _home_icon, _accent_color, false)
	home_selected.emit()
	_sync_highlight_to_active_button.call_deferred()


func _apply_hextech_rail_visuals() -> void:
	var logo_node := (get_node_or_null("logo") if has_node("logo") else get_node_or_null("TextureRect")) as TextureRect
	if logo_node and TEX_SIDEBAR_LOGO:
		logo_node.texture = TEX_SIDEBAR_LOGO

	# Enforce uniform SVG icons and 100% responsive proportional anchors across all 3 buttons
	_setup_responsive_icon(_home_icon, ICON_HOME_SVG)
	_setup_responsive_icon(_add_icon, ICON_ADD_SVG)
	_setup_responsive_icon(_settings_icon, ICON_SETTINGS_SVG)

	for panel in [_home_button_panel, _add_button_panel, _settings_button_panel]:
		if panel:
			panel.custom_minimum_size = Vector2(54, 54)
			var sel := panel.get_node_or_null("selected_panel") as Control
			if sel:
				sel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				sel.offset_left = 2.0
				sel.offset_top = 2.0
				sel.offset_right = -2.0
				sel.offset_bottom = -2.0

	var glow_node: Control = _highlight_glow if _highlight_glow else get_node_or_null("iconhighlight/glow")
	if glow_node and glow_node.material is ShaderMaterial:
		glow_node.material = (glow_node.material as ShaderMaterial).duplicate() as ShaderMaterial

	var bottom_glow := get_node_or_null("glow") as ColorRect
	if bottom_glow and bottom_glow.material is ShaderMaterial:
		var bmat := (bottom_glow.material as ShaderMaterial).duplicate() as ShaderMaterial
		bottom_glow.material = bmat


func _setup_responsive_icon(icon: TextureRect, svg_tex: Texture2D) -> void:
	if not icon:
		return
	if svg_tex:
		icon.texture = svg_tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_left = 0.22
	icon.anchor_top = 0.22
	icon.anchor_right = 0.78
	icon.anchor_bottom = 0.78
	icon.offset_left = 0.0
	icon.offset_top = 0.0
	icon.offset_right = 0.0
	icon.offset_bottom = 0.0


const CLEAN_COLOR_HOME := Color(1.0, 0.04, 0.14, 1.0)
const CLEAN_COLOR_ADD := Color(0.0, 0.40, 1.0, 1.0)
const CLEAN_COLOR_SETTINGS := Color(214.0 / 255.0, 129.0 / 255.0, 0.0, 1.0)
const LCU_GOLD_ACTIVE := Color(0.7843, 0.6078, 0.2353, 1.0)
const LCU_ICON_IDLE := Color(0.7843, 0.6667, 0.4314, 0.78)
const LCU_ICON_ACTIVE := Color(0.9412, 0.902, 0.8235, 1.0)


func _get_ui_style() -> String:
	if Engine.is_editor_hint():
		return "fancy"
	return String(ConfigManager.get_value("UIStyle", "clean")).to_lower()


func _is_clean_ui() -> bool:
	return _get_ui_style() == "clean"


func _is_league_ui() -> bool:
	return _get_ui_style() == "league_client"


func _active_menu_color() -> Color:
	if _is_clean_ui():
		if _active_button_panel == _add_button_panel:
			return CLEAN_COLOR_ADD
		if _active_button_panel == _settings_button_panel:
			return CLEAN_COLOR_SETTINGS
		return CLEAN_COLOR_HOME
	if _is_league_ui():
		return LCU_GOLD_ACTIVE
	return _accent_color


func _refresh_icon_modulates() -> void:
	var is_clean: bool = _is_clean_ui()
	var is_league: bool = _is_league_ui()
	var idle_col: Color = LCU_ICON_IDLE if is_league else Color.WHITE
	if _home_icon:
		_home_icon.modulate = idle_col
	if _add_icon:
		_add_icon.modulate = idle_col
	if _settings_icon:
		_settings_icon.modulate = idle_col
	if is_clean and _active_icon:
		_active_icon.modulate = _active_menu_color()
	elif is_league and _active_icon:
		_active_icon.modulate = LCU_ICON_ACTIVE


func apply_accent_color(accent: Color) -> void:
	_accent_color = accent
	if _is_clean_ui():
		color_home = CLEAN_COLOR_HOME
		color_add_profile = CLEAN_COLOR_ADD
		color_settings = CLEAN_COLOR_SETTINGS
	elif _is_league_ui():
		color_home = LCU_GOLD_ACTIVE
		color_add_profile = LCU_GOLD_ACTIVE
		color_settings = LCU_GOLD_ACTIVE
	else:
		color_home = accent
		color_add_profile = accent
		color_settings = accent
	var rail_bg := get_node_or_null("bg") as ColorRect
	if rail_bg:
		rail_bg.color = Color(0.0039, 0.0392, 0.0745, 0.98) if _is_league_ui() else Color(0.07058824, 0.07058824, 0.07058824, 1.0)
	if _active_button_panel == null:
		_active_button_panel = _home_button_panel
		_active_icon = _home_icon
	_refresh_icon_modulates()
	var active_col := _active_menu_color()
	_set_highlight_theme(active_col, active_col)


func _update_glow() -> void:
	var glow_node: Control = _highlight_glow if _highlight_glow else get_node_or_null("iconhighlight/glow")
	if not glow_node or not glow_node.material is ShaderMaterial:
		return
	var mat: ShaderMaterial = glow_node.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", glow_rect_size)
	mat.set_shader_parameter("bness", glow_intensity)
	mat.set_shader_parameter("fall_off_scale", glow_spread)


func _update_glow_preview() -> void:
	var glow_node: Control = _highlight_glow if _highlight_glow else get_node_or_null("iconhighlight/glow")
	if not glow_node:
		return
	if preview_glow:
		_set_highlight_theme(color_home, color_home)


func _get_button(panel: Control) -> Button:
	if not panel:
		return null
	return panel.get_node_or_null("Button") as Button


# Programmatically selects Home (used after creating a profile).
func select_home() -> void:
	_on_home_button_pressed()


func _on_home_button_pressed() -> void:
	_update_selection(_home_selected_panel, _home_button_panel, _home_icon, color_home, true)
	home_selected.emit()


func _on_settings_pressed() -> void:
	_on_settings_button_pressed()


func _on_settings_button_pressed() -> void:
	_update_selection(_settings_selected_panel, _settings_button_panel, _settings_icon, color_settings, true)
	settings_selected.emit()


func _on_add_profile_button_pressed() -> void:
	_update_selection(_add_selected_panel, _add_button_panel, _add_icon, color_add_profile, true)
	add_profile_selected.emit()


func _compute_highlight_target_y(button_panel: Control) -> float:
	if not button_panel or not _icon_highlight:
		return 274.0
	var y_offset := _vbox.position.y if _vbox != self else 0.0
	var btn_y := button_panel.position.y
	# Fallback if VBoxContainer has not sorted its children yet on frame 0
	if btn_y <= 0.0 and button_panel == _home_button_panel:
		var rail_h := size.y if size.y > 0.0 else 720.0
		btn_y = (rail_h - (54.0 * 3.0 + 14.0 * 2.0)) * 0.5
	var btn_h := button_panel.size.y if button_panel.size.y > 0.0 else 54.0
	var hl_h := _icon_highlight.size.y if _icon_highlight.size.y > 0.0 else 36.0
	return y_offset + btn_y + (btn_h - hl_h) * 0.5


func _sync_highlight_to_active_button() -> void:
	if not _icon_highlight or not _active_button_panel:
		return
	if _highlight_tween and _highlight_tween.is_valid():
		return
	_icon_highlight.position.y = _compute_highlight_target_y(_active_button_panel)


func _update_selection(selected_panel: Control, button_panel: Control, active_icon: TextureRect, _color: Color, animate: bool = true) -> void:
	_active_icon = active_icon
	_active_button_panel = button_panel
	if _home_selected_panel: _home_selected_panel.visible = false
	if _settings_selected_panel: _settings_selected_panel.visible = false
	if _add_selected_panel: _add_selected_panel.visible = false

	if selected_panel: selected_panel.visible = true
	_refresh_icon_modulates()
	var active_col := _active_menu_color()
	_set_highlight_theme(active_col, active_col)

	if _icon_highlight and button_panel:
		var target_y := _compute_highlight_target_y(button_panel)
		if _highlight_tween and _highlight_tween.is_valid():
			_highlight_tween.kill()
			_highlight_tween = null
		if animate:
			_highlight_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_highlight_tween.tween_property(_icon_highlight, "position:y", target_y, 0.14)
		else:
			_icon_highlight.position.y = target_y


func _set_highlight_theme(glow_color: Color, panel_color: Color) -> void:
	var is_clean: bool = _is_clean_ui()
	var is_league: bool = _is_league_ui()
	if _icon_highlight:
		_icon_highlight.offset_right = -36.5 if is_clean else (-39.5 if is_league else -38.5)
	var glow_node: Control = _highlight_glow if _highlight_glow else get_node_or_null("iconhighlight/glow")
	if glow_node:
		if glow_node.material is ShaderMaterial:
			var mat := glow_node.material as ShaderMaterial
			mat.set_shader_parameter("glow_color", glow_color)
			mat.set_shader_parameter("glow_color_secondary", Color(glow_color.r, glow_color.g, glow_color.b, 0.85))
		glow_node.color = glow_color
	var bottom_glow := get_node_or_null("glow") as ColorRect
	if bottom_glow:
		if bottom_glow.material is ShaderMaterial:
			var bmat := bottom_glow.material as ShaderMaterial
			bmat.set_shader_parameter("glow_color", glow_color)
			bmat.set_shader_parameter("glow_color_secondary", Color(glow_color.r, glow_color.g, glow_color.b, 0.85))
		bottom_glow.color = Color(glow_color.r, glow_color.g, glow_color.b, 0.35)
	var panel_node: Panel = _highlight_panel if _highlight_panel else get_node_or_null("iconhighlight/Panel")
	if panel_node:
		var stylebox := panel_node.get_theme_stylebox("panel")
		if stylebox is StyleBoxFlat:
			var flat := (stylebox as StyleBoxFlat).duplicate() as StyleBoxFlat
			flat.bg_color = panel_color
			flat.border_width_right = 0 if is_clean else 1
			flat.border_color = panel_color if is_clean else (LCU_ICON_ACTIVE if is_league else panel_color.lightened(0.22))
			var cr := 4 if is_clean else (0 if is_league else 2)
			flat.corner_radius_top_right = cr
			flat.corner_radius_bottom_right = cr
			panel_node.add_theme_stylebox_override("panel", flat)
	for sel_panel in [_home_selected_panel, _add_selected_panel, _settings_selected_panel]:
		if sel_panel and sel_panel is Panel:
			var sel_sb := (sel_panel as Panel).get_theme_stylebox("panel")
			if sel_sb is StyleBoxFlat:
				var sel_flat := (sel_sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				sel_flat.bg_color = Color(panel_color.r, panel_color.g, panel_color.b, 0.0 if is_clean else (0.12 if is_league else 0.08))
				sel_flat.border_color = Color(panel_color.r, panel_color.g, panel_color.b, 0.0 if is_clean else (0.62 if is_league else 0.28))
				var sel_cr := 0 if is_league else 4
				sel_flat.corner_radius_top_left = sel_cr
				sel_flat.corner_radius_top_right = sel_cr
				sel_flat.corner_radius_bottom_right = sel_cr
				sel_flat.corner_radius_bottom_left = sel_cr
				(sel_panel as Panel).add_theme_stylebox_override("panel", sel_flat)
