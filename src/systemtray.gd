extends Node

func _ready() -> void:
	var si: StatusIndicator = StatusIndicator.new()
	si.icon = load("res://apple-touch-icon.png")
	si.tooltip = tr("RiotSwitcher")
	si.pressed.connect(_on_menu_id_pressed)
	add_child(si)

	var menu: PopupMenu = PopupMenu.new()
	add_child(menu)

	menu.add_item(tr("Exit"), 0)
	si.menu = menu.get_path()
	menu.id_pressed.connect(_on_menu_id_selected)

func _on_menu_id_selected(id: int) -> void:
	match id:
		0:
			get_tree().quit()

func _on_menu_id_pressed(button, _position):
	if button == MOUSE_BUTTON_LEFT:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

## FPS limiter
func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = 5  # Reduz para 10 FPS quando perde o foco
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = 60  # Volta para 60 FPS quando volta o foco
