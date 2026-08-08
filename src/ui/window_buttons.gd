class_name WindowButtons
extends Control

## Custom window chrome (borderless window): close and minimize buttons.

@onready var _close_button: Button = $x if has_node("x") else null
@onready var _minimize_button: Button = $"-" if has_node("-") else null


func _ready() -> void:
	if _close_button and not _close_button.pressed.is_connected(_on_close_button_pressed):
		_close_button.pressed.connect(_on_close_button_pressed)
	if _minimize_button and not _minimize_button.pressed.is_connected(_on_minimize_button_pressed):
		_minimize_button.pressed.connect(_on_minimize_button_pressed)


## Handles close button press: saves session if main exists, then terminates the app.
func _on_close_button_pressed() -> void:
	if is_inside_tree():
		var main_node := get_tree().root.get_node_or_null("main")
		if main_node and main_node.has_method("save_session_and_quit"):
			main_node.save_session_and_quit()
			return
	get_tree().quit()


func _on_minimize_button_pressed() -> void:
	get_window().mode = Window.MODE_MINIMIZED
