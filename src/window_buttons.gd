extends Control

## Custom window chrome (borderless window): close and minimize buttons.

@onready var _close_button: Button = $x
@onready var _minimize_button: Button = $"-"


func _ready() -> void:
	_close_button.pressed.connect(_on_close_button_pressed)
	_minimize_button.pressed.connect(_on_minimize_button_pressed)


## The scene root (Main) handles the close request: it saves the running
## session and hides the window to the system tray.
func _on_close_button_pressed() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _on_minimize_button_pressed() -> void:
	get_window().mode = Window.MODE_MINIMIZED
