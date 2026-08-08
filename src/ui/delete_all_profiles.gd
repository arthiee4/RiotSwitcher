extends Control

@onready var _delete_button: Button = $Panel/Button if has_node("Panel/Button") else find_child("Button", true, false)


func _ready() -> void:
	if _delete_button:
		_delete_button.pressed.connect(_on_delete_all_pressed)


func _on_delete_all_pressed() -> void:
	if ProfileManager and ProfileManager.has_method("delete_all_profiles"):
		ProfileManager.delete_all_profiles()
