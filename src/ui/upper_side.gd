class_name UpperSide
extends Control

## Drag handle for the borderless window: dragging this bar moves the window.

var _dragging := false
var _drag_offset := Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = event.position

	if event is InputEventMouseMotion and _dragging:
		var window_position := Vector2(DisplayServer.window_get_position())
		DisplayServer.window_set_position(window_position + event.position - _drag_offset)
