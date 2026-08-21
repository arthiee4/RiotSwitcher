extends Control

@onready var _delete_button: Button = $Panel/Button if has_node("Panel/Button") else find_child("Button", true, false)


func _ready() -> void:
	if _delete_button:
		_delete_button.pressed.connect(_on_delete_all_pressed)


func _on_delete_all_pressed() -> void:
	# Deleting every profile while a client is running would destroy the
	# running profile's session backup before it was ever saved.
	var grid := _find_profile_grid()
	if grid:
		if grid.has_method("get_running_profile_name") and not str(grid.get_running_profile_name()).is_empty():
			printerr("DeleteAllProfiles: Cannot delete profiles while a client is running.")
			return
		if grid.has_method("_is_busy") and grid._is_busy():
			printerr("DeleteAllProfiles: Another operation is in progress.")
			return

	if ProfileManager and ProfileManager.has_method("delete_all_profiles"):
		ProfileManager.delete_all_profiles()


func _find_profile_grid() -> Node:
	for node in get_tree().root.find_children("*", "", true, false):
		if node.has_method("get_running_profile_name") and node.has_method("save_running_session"):
			return node
	return null
