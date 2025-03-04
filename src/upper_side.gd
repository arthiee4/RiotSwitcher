extends Control

var active_mouse_menu = null
var dragging = false
var drag_offset = Vector2()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_offset = event.position

	if event is InputEventMouseMotion and dragging:
		var window_position = Vector2(DisplayServer.window_get_position().x, DisplayServer.window_get_position().y)
		var new_position = window_position + event.position - drag_offset
		DisplayServer.window_set_position(new_position)
