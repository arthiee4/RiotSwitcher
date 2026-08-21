class_name SystemTrayController
extends Node

## System tray icon. Left click restores the window; the menu offers Exit.
## Main connects to the signals and owns the actual window/app lifecycle.

signal exit_requested
signal show_window_requested

const TRAY_ICON: Texture2D = preload("res://assets/icons/icon1.png")

const MENU_ID_EXIT := 0


func _ready() -> void:
	var indicator := StatusIndicator.new()
	indicator.icon = TRAY_ICON
	indicator.tooltip = "Riot Switcher"
	indicator.pressed.connect(_on_indicator_pressed)
	add_child(indicator)

	var menu := PopupMenu.new()
	menu.add_item(tr("Exit"), MENU_ID_EXIT)
	menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(menu)
	indicator.menu = menu.get_path()


func _on_menu_id_pressed(id: int) -> void:
	if id == MENU_ID_EXIT:
		exit_requested.emit()


func _on_indicator_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		show_window_requested.emit()
