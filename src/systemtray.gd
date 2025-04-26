extends Node

func _ready() -> void:
	var si: StatusIndicator = StatusIndicator.new()
	si.icon = load("res://apple-touch-icon.png")
	si.tooltip = "RiotSwitcher 2"
	si.pressed.connect(_on_menu_id_pressed)
	add_child(si)

	var menu: PopupMenu = PopupMenu.new()
	add_child(menu)

	menu.add_item("Exit", 0)
	si.menu = menu.get_path()
	menu.id_pressed.connect(_on_menu_id_selected)

func _on_menu_id_selected(id: int) -> void:
	match id:
		0:
			get_tree().quit()

func _on_menu_id_pressed(button, _position):
	if button == MOUSE_BUTTON_LEFT:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
