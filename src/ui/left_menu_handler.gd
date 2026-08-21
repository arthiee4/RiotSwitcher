@tool
class_name LeftMenuHandler
extends Control

## Left navigation rail: Home / Add Profile / Settings. Emits a signal per
## destination; Main performs the actual view switch.

#region Glow Customization (Inspector)
@export_group("Highlight Glow Settings")
## Ative para ver e ajustar o glow do menu ao vivo no editor!
@export var preview_glow: bool = false:
	set(value):
		preview_glow = value
		_update_glow_preview()

@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 1.6:
	set(value):
		glow_intensity = value
		_update_glow()

@export_range(0.5, 6.0, 0.1) var glow_spread: float = 1.5:
	set(value):
		glow_spread = value
		_update_glow()

@export var glow_rect_size: Vector2 = Vector2(0.02, 0.10):
	set(value):
		glow_rect_size = value
		_update_glow()

@export_group("Menu Colors")
@export var color_home: Color = Color(1.0, 0.04, 0.14, 1.0)
@export var color_add_profile: Color = Color(0.0, 0.40, 1.0, 1.0)
@export var color_settings: Color = Color(214 / 255.0, 129 / 255.0, 0.0, 1.0)
#endregion

signal home_selected
signal settings_selected
signal add_profile_selected

@onready var _add_button_panel: Control = $add_profile_button if has_node("add_profile_button") else get_node_or_null("VBoxContainer/add_profile_button")
@onready var _add_icon: TextureRect = $add_profile_button/Button/TextureRect if has_node("add_profile_button/Button/TextureRect") else get_node_or_null("VBoxContainer/add_profile_button/Button/TextureRect")
@onready var _add_selected_panel: Control = $add_profile_button/selected_panel if has_node("add_profile_button/selected_panel") else get_node_or_null("VBoxContainer/add_profile_button/selected_panel")

@onready var _home_button_panel: Control = $home_button if has_node("home_button") else get_node_or_null("VBoxContainer/home_button")
@onready var _home_icon: TextureRect = $home_button/Button/TextureRect if has_node("home_button/Button/TextureRect") else get_node_or_null("VBoxContainer/home_button/Button/TextureRect")
@onready var _home_selected_panel: Control = $home_button/selected_panel if has_node("home_button/selected_panel") else get_node_or_null("VBoxContainer/home_button/selected_panel")

@onready var _settings_button_panel: Control = $settings_button if has_node("settings_button") else get_node_or_null("VBoxContainer/settings_button")
@onready var _settings_icon: TextureRect = $settings_button/Button/TextureRect if has_node("settings_button/Button/TextureRect") else get_node_or_null("VBoxContainer/settings_button/Button/TextureRect")
@onready var _settings_selected_panel: Control = $settings_button/selected_panel if has_node("settings_button/selected_panel") else get_node_or_null("VBoxContainer/settings_button/selected_panel")

@onready var _icon_highlight: Control = $iconhighlight if has_node("iconhighlight") else null
@onready var _highlight_glow: Control = $iconhighlight/glow if has_node("iconhighlight/glow") else null
@onready var _highlight_panel: Panel = $iconhighlight/Panel if has_node("iconhighlight/Panel") else null
@onready var _vbox: Control = $VBoxContainer if has_node("VBoxContainer") else self


func _ready() -> void:
	_update_glow()
	_update_glow_preview()

	if Engine.is_editor_hint():
		return

	var home_btn := _get_button(_home_button_panel)
	if home_btn and not home_btn.pressed.is_connected(_on_home_button_pressed):
		home_btn.pressed.connect(_on_home_button_pressed)

	var settings_btn := _get_button(_settings_button_panel)
	if settings_btn and not settings_btn.pressed.is_connected(_on_settings_button_pressed):
		settings_btn.pressed.connect(_on_settings_button_pressed)

	var add_btn := _get_button(_add_button_panel)
	if add_btn and not add_btn.pressed.is_connected(_on_add_profile_button_pressed):
		add_btn.pressed.connect(_on_add_profile_button_pressed)

	select_home()


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


## Programmatically selects Home (used after creating a profile).
func select_home() -> void:
	_on_home_button_pressed()


func _on_home_button_pressed() -> void:
	_update_selection(_home_selected_panel, _home_button_panel, _home_icon, color_home)
	home_selected.emit()


func _on_settings_button_pressed() -> void:
	_update_selection(_settings_selected_panel, _settings_button_panel, _settings_icon, color_settings)
	settings_selected.emit()


func _on_add_profile_button_pressed() -> void:
	_update_selection(_add_selected_panel, _add_button_panel, _add_icon, color_add_profile)
	add_profile_selected.emit()


func _update_selection(selected_panel: Control, button_panel: Control, active_icon: TextureRect, color: Color) -> void:
	if _home_selected_panel: _home_selected_panel.visible = false
	if _settings_selected_panel: _settings_selected_panel.visible = false
	if _add_selected_panel: _add_selected_panel.visible = false

	if _home_icon: _home_icon.modulate = Color.WHITE
	if _settings_icon: _settings_icon.modulate = Color.WHITE
	if _add_icon: _add_icon.modulate = Color.WHITE

	if selected_panel: selected_panel.visible = true
	if active_icon: active_icon.modulate = color
	_set_highlight_theme(color, color)

	if _icon_highlight and button_panel:
		var y_offset := _vbox.position.y if _vbox != self else 0.0
		var target_y := y_offset + button_panel.position.y + 9
		var tween := create_tween().set_ease(Tween.EASE_OUT_IN)
		tween.tween_property(_icon_highlight, "position:y", target_y, 0.1)


func _set_highlight_theme(glow_color: Color, panel_color: Color) -> void:
	var glow_node: Control = _highlight_glow if _highlight_glow else get_node_or_null("iconhighlight/glow")
	if glow_node:
		if glow_node.material is ShaderMaterial:
			(glow_node.material as ShaderMaterial).set_shader_parameter("glow_color", glow_color)
		glow_node.color = glow_color
	var panel_node: Panel = _highlight_panel if _highlight_panel else get_node_or_null("iconhighlight/Panel")
	if panel_node:
		var stylebox := panel_node.get_theme_stylebox("panel")
		if stylebox is StyleBoxFlat:
			stylebox.bg_color = panel_color
