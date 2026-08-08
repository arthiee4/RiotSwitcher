class_name ToggleSettingController
extends Control

## Generic settings row: binds a CheckButton to a boolean ConfigManager key.
## Set config_key (and optionally default_value) per instance in the scene.

@export var config_key: String = ""
@export var default_value: bool = false

@onready var _check_button: CheckButton = $Panel/CheckButton if has_node("Panel/CheckButton") else null


func _ready() -> void:
	if config_key.is_empty() or not _check_button:
		printerr("ToggleSetting: Missing config_key or CheckButton node.")
		return
	_check_button.button_pressed = bool(ConfigManager.get_value(config_key, default_value))
	_check_button.toggled.connect(_on_toggled)


func _on_toggled(pressed: bool) -> void:
	if not ConfigManager.set_value_and_save(config_key, pressed):
		printerr("ToggleSetting: Failed to save '%s'." % config_key)
