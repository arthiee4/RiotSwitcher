extends Control

## First-run setup screen: asks for the Riot Client installation folder and
## saves it through the ConfigManager (which broadcasts configs_updated,
## causing Main to hide this screen).

@onready var _icon: TextureRect = $Control/TextureRect
@onready var _file_dialog: FileDialog = $Control/FileDialog
@onready var _browse_button: Button = $Control/Button
@onready var _error: Control = $Control/error

var _config_manager: Node
var _initial_icon_rotation: float
var _icon_tween: Tween


## Injected by Main before this screen is shown.
func set_config_manager(config_manager: Node) -> void:
	_config_manager = config_manager


func _ready() -> void:
	_initial_icon_rotation = _icon.rotation_degrees
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.title = "Select Riot Client Installation Directory"
	_error.visible = false
	_browse_button.pressed.connect(_on_browse_button_pressed)
	_file_dialog.dir_selected.connect(_on_dir_selected)
	if visible:
		_animate_icon()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_inside_tree():
			if visible:
				_animate_icon()
			else:
				_stop_icon_animation()


func _stop_icon_animation() -> void:
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
	if is_instance_valid(_icon):
		_icon.rotation_degrees = _initial_icon_rotation


func _animate_icon() -> void:
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()

	const SWAY_ANGLE := 5.0
	const SWAY_DURATION := 1.8
	_icon_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_icon_tween.tween_property(_icon, "rotation_degrees", _initial_icon_rotation + SWAY_ANGLE, SWAY_DURATION / 4.0)
	_icon_tween.tween_property(_icon, "rotation_degrees", _initial_icon_rotation - SWAY_ANGLE, SWAY_DURATION / 2.0)
	_icon_tween.tween_property(_icon, "rotation_degrees", _initial_icon_rotation, SWAY_DURATION / 4.0)


func _on_browse_button_pressed() -> void:
	_file_dialog.popup_centered()


func _on_dir_selected(dir_path: String) -> void:
	var exe_path := dir_path.path_join("RiotClientServices.exe")
	if not FileAccess.file_exists(exe_path):
		_error.text = "RiotClientServices.exe not found in this directory! Please select the correct folder."
		_error.visible = true
		return

	_error.visible = false
	if not _config_manager:
		printerr("Boot: ConfigManager not set; cannot save the client location.")
		return
	if not _config_manager.set_value_and_save("RiotClientLocation", dir_path):
		printerr("Boot: Failed to save the Riot Client location.")
		return

	_stop_icon_animation()
