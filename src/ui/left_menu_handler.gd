class_name LeftMenuHandler
extends Control

## Left navigation rail: Home / Add Profile / Settings. Emits a signal per
## destination; Main performs the actual view switch.

signal home_selected
signal settings_selected
signal add_profile_selected

const COLOR_HOME := Color(1, 0, 0, 1)
const COLOR_SETTINGS := Color(214 / 255.0, 129 / 255.0, 0, 1)
const COLOR_ADD := Color(0, 0, 1, 1)

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


func _get_button(panel: Control) -> Button:
	if not panel:
		return null
	return panel.get_node_or_null("Button") as Button


## Programmatically selects Home (used after creating a profile).
func select_home() -> void:
	_on_home_button_pressed()


func _on_home_button_pressed() -> void:
	_update_selection(_home_selected_panel, _home_button_panel, _home_icon, COLOR_HOME)
	home_selected.emit()


func _on_settings_button_pressed() -> void:
	_update_selection(_settings_selected_panel, _settings_button_panel, _settings_icon, COLOR_SETTINGS)
	settings_selected.emit()


func _on_add_profile_button_pressed() -> void:
	_update_selection(_add_selected_panel, _add_button_panel, _add_icon, COLOR_ADD)
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
	_set_highlight_theme(Color(color, 0.1 if color == COLOR_HOME else 0.5), color)

	if _icon_highlight and button_panel:
		var y_offset := _vbox.position.y if _vbox != self else 0.0
		var target_y := y_offset + button_panel.position.y + 9
		var tween := create_tween().set_ease(Tween.EASE_OUT_IN)
		tween.tween_property(_icon_highlight, "position:y", target_y, 0.1)


func _set_highlight_theme(glow_color: Color, panel_color: Color) -> void:
	if _highlight_glow:
		_highlight_glow.color = glow_color
	if _highlight_panel:
		var stylebox := _highlight_panel.get_theme_stylebox("panel")
		if stylebox is StyleBoxFlat:
			stylebox.bg_color = panel_color
