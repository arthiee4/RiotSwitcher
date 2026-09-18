@tool
extends EditorPlugin

var builder_panel: Control
var builder_button: Button

func _enter_tree() -> void:
	if ClassDB.class_exists("CATuiBuilderPanel"):
		builder_panel = ClassDB.instantiate("CATuiBuilderPanel")
	else:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, 180)
		var label := Label.new()
		label.text = "CATui Builder GDExtension is loading..."
		panel.add_child(label)
		builder_panel = panel

	builder_panel.name = "CATuiBuilder"
	builder_button = add_control_to_bottom_panel(builder_panel, "CATui Builder")

func _exit_tree() -> void:
	if builder_panel:
		remove_control_from_bottom_panel(builder_panel)
		builder_panel.queue_free()
		builder_panel = null
		builder_button = null
