class_name SettingsMenuController
extends Control

## Settings view controller. Manages presentation and staggered cascade entrance animation.

@onready var _title_label: Label = $Label if has_node("Label") else null
@onready var _vbox: VBoxContainer = $VBoxContainer if has_node("VBoxContainer") else null

var _cascade_tweens: Array[Tween] = []


func _ready() -> void:
	pass


## Plays a crisp, staggered cascade entrance animation for all settings cards.
func play_cascade_entrance() -> void:
	for tw in _cascade_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cascade_tweens.clear()

	# Title animation
	if _title_label and is_instance_valid(_title_label):
		_title_label.modulate.a = 0.0
		var title_has_offset: bool = "offset_transform_enabled" in _title_label
		if title_has_offset:
			_title_label.set("offset_transform_enabled", true)
			_title_label.set("offset_transform_position", Vector2(0.0, -8.0))
			_title_label.set("offset_transform_visual_only", true)
		else:
			_title_label.position.y = 37.0

		var title_tween := _title_label.create_tween().set_parallel(true)
		_cascade_tweens.append(title_tween)
		title_tween.tween_property(_title_label, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if title_has_offset:
			title_tween.tween_property(_title_label, "offset_transform_position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			title_tween.tween_property(_title_label, "position:y", 45.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Cards cascade inside VBoxContainer
	if not _vbox or not is_instance_valid(_vbox):
		return

	var children := _vbox.get_children()
	for i in range(children.size()):
		var child = children[i]
		if not child is Control or not is_instance_valid(child):
			continue

		child.modulate.a = 0.0

		var has_offset: bool = "offset_transform_enabled" in child
		if has_offset:
			child.set("offset_transform_enabled", true)
			child.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			child.set("offset_transform_scale", Vector2(0.96, 0.96))
			child.set("offset_transform_visual_only", false)
		else:
			var sz: Vector2 = child.size
			if sz.x <= 0 or sz.y <= 0:
				sz = child.get_combined_minimum_size()
			if sz.x > 0 and sz.y > 0:
				child.pivot_offset = Vector2(sz.x * 0.5, sz.y * 0.5)
			child.scale = Vector2(0.96, 0.96)

		var delay: float = 0.03 + (i * 0.04) # Stagger 40ms per card
		var tween := child.create_tween().set_parallel(true)
		_cascade_tweens.append(tween)

		tween.tween_property(child, "modulate:a", 1.0, 0.16).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tween.tween_property(child, "offset_transform_scale", Vector2.ONE, 0.20).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(child, "scale", Vector2.ONE, 0.20).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
