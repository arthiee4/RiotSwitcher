extends Control

## Left navigation rail: Home / Add Profile / Settings. Emits a signal per
## destination; Main performs the actual view switch.

signal home_selected
signal settings_selected
signal add_profile_selected

const COLOR_HOME := Color(1, 0, 0, 1)
const COLOR_SETTINGS := Color(214 / 255.0, 129 / 255.0, 0, 1)
const COLOR_ADD := Color(0, 0, 1, 1)

@onready var _add_button_panel: Control = $add_profile_button
@onready var _add_icon: TextureRect = $add_profile_button/Button/TextureRect
@onready var _add_selected_panel: Control = $add_profile_button/selected_panel

@onready var _home_button_panel: Control = $home_button
@onready var _home_icon: TextureRect = $home_button/Button/TextureRect
@onready var _home_selected_panel: Control = $home_button/selected_panel

@onready var _settings_button_panel: Control = $settings_button
@onready var _settings_icon: TextureRect = $settings_button/Button/TextureRect
@onready var _settings_selected_panel: Control = $settings_button/selected_panel

@onready var _icon_highlight: Control = $iconhighlight
@onready var _highlight_glow: Control = $iconhighlight/glow
@onready var _highlight_panel: Panel = $iconhighlight/Panel


func _ready() -> void:
	$home_button/Button.pressed.connect(_on_home_button_pressed)
	$settings_button/Button.pressed.connect(_on_settings_button_pressed)
	$add_profile_button/Button.pressed.connect(_on_add_profile_button_pressed)
	select_home()


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
	_home_selected_panel.visible = false
	_settings_selected_panel.visible = false
	_add_selected_panel.visible = false

	_home_icon.modulate = Color.WHITE
	_settings_icon.modulate = Color.WHITE
	_add_icon.modulate = Color.WHITE

	selected_panel.visible = true
	active_icon.modulate = color
	_set_highlight_theme(Color(color, 0.1 if color == COLOR_HOME else 0.5), color)

	var tween := create_tween().set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(_icon_highlight, "position:y", button_panel.position.y + 9, 0.1)


func _set_highlight_theme(glow_color: Color, panel_color: Color) -> void:
	_highlight_glow.color = glow_color
	var stylebox := _highlight_panel.get_theme_stylebox("panel")
	if stylebox is StyleBoxFlat:
		stylebox.bg_color = panel_color
