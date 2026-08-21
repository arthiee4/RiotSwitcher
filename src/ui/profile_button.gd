@tool
class_name ProfileButton
extends Control

## A single profile card in the grid. It only handles presentation and user
## input; all heavy work (killing processes, swapping session files) is
## orchestrated by ProfileGridController, which confirms state changes back
## through confirm_started()/confirm_stopped()/reset_toggle_state().

#region Glow Customization (Inspector)
@export_group("Glow Settings")
## Ative para ver e ajustar o glow ao vivo no editor!
@export var preview_glow: bool = false:
	set(value):
		preview_glow = value
		_update_glow_preview()

@export var glow_color: Color = Color(1.0, 0.04, 0.14, 1.0):
	set(value):
		glow_color = value
		_update_glow()

@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 1.3:
	set(value):
		glow_intensity = value
		_update_glow()

@export_range(0.5, 6.0, 0.1) var glow_spread: float = 1.8:
	set(value):
		glow_spread = value
		_update_glow()

@export var glow_rect_size: Vector2 = Vector2(0.26, 0.10):
	set(value):
		glow_rect_size = value
		_update_glow()
#endregion

signal client_toggled(profile_button: Control, is_starting: bool)
signal delete_requested(profile_button: Control)
signal edit_requested(profile_button: Control)

const PLAY_ICON: Texture2D = preload("res://assets/icons/ui/icon_play.png")
const STOP_ICON: Texture2D = preload("res://assets/icons/ui/icon_stop.png")
const DRAG_THRESHOLD := 6.0
const HOVER_FADE_IN_TIME := 0.08
const HOVER_FADE_OUT_TIME := 0.08
const HOVER_SCALE_FACTOR := 1.04

## Full profile dictionary from ProfileManager. Set right after instantiation.
var profile_data: Dictionary = {}

var client_is_running := false
var _is_interactable := true
var _is_transitioning := false

# Drag & click state
var _is_mouse_down := false
var _drag_start_pos := Vector2.ZERO

@onready var _context_menu: Control = get_node_or_null("card/context_menu")
@onready var _delete_button: TextureButton = get_node_or_null("card/context_menu/Panel/delete/TextureButton")
@onready var _edit_button: TextureButton = get_node_or_null("card/context_menu/Panel/edit/TextureButton")
@onready var _glow_effect: Control = $glow if has_node("glow") else find_child("glow", true, false)
@onready var _button: Button = get_node_or_null("card/card_inner/Button")
@onready var _state_icon: TextureRect = get_node_or_null("card/card_inner/Button/TextureRect")
@onready var _card: Control = get_node_or_null("card")
@onready var _hover_info: Control = $hover_info if has_node("hover_info") else null
@onready var _desc_label: Label = $hover_info/desc_label if has_node("hover_info/desc_label") else null

var _hover_tween: Tween = null
var _glow_tween: Tween = null


var profile_name: String:
	get: return profile_data.get("profile_name", "")


func _ready() -> void:
	_update_glow()
	_update_glow_preview()

	if Engine.is_editor_hint():
		return

	if _delete_button:
		_delete_button.pressed.connect(_on_delete_button_pressed)
	if _edit_button:
		_edit_button.pressed.connect(_on_edit_button_pressed)
	if _card:
		_card.gui_input.connect(_on_card_gui_input)
	if _button and _button is Button:
		if not _button.pressed.is_connected(_on_profile_button_pressed):
			_button.pressed.connect(_on_profile_button_pressed)
		_button.mouse_entered.connect(_on_card_mouse_entered)
		_button.mouse_exited.connect(_on_card_mouse_exited)
	if _context_menu:
		_context_menu.visible = false
	if _hover_info:
		_hover_info.visible = false
	if _glow_effect:
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)
		_glow_effect.pivot_offset = _glow_effect.size * 0.5
	set_process_input(true)


func _update_glow() -> void:
	var glow_node: Control = _glow_effect if _glow_effect else (get_node_or_null("glow") as Control)
	if not glow_node or not glow_node.material is ShaderMaterial:
		return
	var mat: ShaderMaterial = glow_node.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", glow_rect_size)
	mat.set_shader_parameter("bness", glow_intensity)
	mat.set_shader_parameter("fall_off_scale", glow_spread)
	mat.set_shader_parameter("glow_color", glow_color)
	mat.set_shader_parameter("glow_color_secondary", glow_color.darkened(0.25))


func _update_glow_preview() -> void:
	var glow_node: Control = _glow_effect if _glow_effect else (get_node_or_null("glow") as Control)
	if not glow_node:
		return
	if preview_glow:
		glow_node.modulate.a = 1.0
		glow_node.scale = Vector2(1.04, 1.04)
	else:
		if Engine.is_editor_hint():
			glow_node.modulate.a = 0.0
			glow_node.scale = Vector2(0.96, 0.96)


#region State confirmation (called by ProfileGridController)

## Confirms the client for this profile is now running.
func confirm_started() -> void:
	client_is_running = true
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = STOP_ICON


## Confirms the client was stopped and the session saved.
func confirm_stopped() -> void:
	client_is_running = false
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = PLAY_ICON


## Reverts the toggle after a failed start/stop attempt.
func reset_toggle_state() -> void:
	client_is_running = false
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = PLAY_ICON

#endregion

#region Input handlers

func _on_profile_button_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	var starting := not client_is_running

	# Immediately switch icon with punchy pop animation for instant UI responsiveness
	if _state_icon:
		_state_icon.pivot_offset = _state_icon.size * 0.5
		_state_icon.texture = STOP_ICON if starting else PLAY_ICON
		_state_icon.scale = Vector2(1.28, 1.28)
		var icon_tw := create_tween()
		icon_tw.tween_property(_state_icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	client_toggled.emit(self, starting)


func _on_delete_button_pressed() -> void:
	_context_menu.visible = false
	if client_is_running or _is_transitioning:
		printerr("Cannot delete profile while its client is running.")
		return
	delete_requested.emit(self)


func _on_edit_button_pressed() -> void:
	_context_menu.visible = false
	if client_is_running or _is_transitioning:
		printerr("Cannot edit profile while its client is running.")
		return
	edit_requested.emit(self)


## Handles right-click (context menu) and click-and-drag for grid reordering.
func _on_card_gui_input(event: InputEvent) -> void:
	if not _is_interactable or _is_transitioning:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			_context_menu.visible = not _context_menu.visible
			if _context_menu.visible:
				_hide_hover_info()
				_context_menu.global_position = get_global_mouse_position()
			get_viewport().set_input_as_handled()
			return

		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				if _context_menu and _context_menu.visible:
					_context_menu.visible = false
					get_viewport().set_input_as_handled()
					return
				if profile_data.is_empty():
					return
				var parent_grid = get_parent()
				if parent_grid and parent_grid.has_method("_is_busy") and parent_grid._is_busy():
					return

				_is_mouse_down = true
				_drag_start_pos = event.global_position
			else:
				_is_mouse_down = false

	elif event is InputEventMouseMotion and _is_mouse_down:
		if event.global_position.distance_to(_drag_start_pos) >= DRAG_THRESHOLD:
			_is_mouse_down = false
			if _context_menu:
				_context_menu.visible = false
			_hide_hover_info()
			var parent_grid = get_parent()
			if parent_grid and parent_grid.has_method("start_card_drag"):
				parent_grid.start_card_drag(self, event.global_position)


## Hides the context menu when clicking anywhere outside of it.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _context_menu or not _context_menu.visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		if not _context_menu.get_global_rect().has_point(event.position):
			_context_menu.visible = false

#endregion

#region Visual state & Hover Info

func _on_card_mouse_entered() -> void:
	if Engine.is_editor_hint() or not _is_interactable:
		return

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_tween = create_tween().set_parallel(true)
		_glow_tween.tween_property(_glow_effect, "modulate:a", 1.0, HOVER_FADE_IN_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_glow_tween.tween_property(_glow_effect, "scale", Vector2(HOVER_SCALE_FACTOR, HOVER_SCALE_FACTOR), HOVER_FADE_IN_TIME + 0.02).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var description: String = profile_data.get("description", "").strip_edges()
	if not description.is_empty() and _hover_info and _desc_label:
		_desc_label.text = description
		_show_hover_info()


func _on_card_mouse_exited() -> void:
	if Engine.is_editor_hint() or not _is_interactable:
		return

	# If mouse is still within the profile card rect (e.g. over play button), don't exit hover
	var global_mouse := get_global_mouse_position()
	if get_global_rect().has_point(global_mouse):
		return

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_tween = create_tween().set_parallel(true)
		_glow_tween.tween_property(_glow_effect, "modulate:a", 0.0, HOVER_FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_glow_tween.tween_property(_glow_effect, "scale", Vector2(0.96, 0.96), HOVER_FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_hide_hover_info()


func _show_hover_info() -> void:
	if not _hover_info or (_context_menu and _context_menu.visible) or not _is_interactable:
		return

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	# Recalculate dynamic container dimensions based on text content & padding
	_hover_info.visible = true
	_hover_info.reset_size()
	var min_sz := _hover_info.get_combined_minimum_size()
	var card_w: float = size.x if size.x > 0 else 181.0
	var final_w: float = maxf(min_sz.x, _hover_info.size.x)
	var final_h: float = maxf(min_sz.y, _hover_info.size.y)

	_hover_info.size = Vector2(final_w, final_h)
	# Center horizontally above card with 7px gap
	_hover_info.position = Vector2((card_w - final_w) * 0.5, -final_h - 7.0)
	_hover_info.pivot_offset = Vector2(final_w * 0.5, final_h)

	_hover_info.modulate.a = 0.0
	_hover_info.scale = Vector2(0.94, 0.94)

	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(_hover_info, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_hover_info, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_hover_info() -> void:
	if not _hover_info or not _hover_info.visible:
		return

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(_hover_info, "modulate:a", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.tween_property(_hover_info, "scale", Vector2(0.95, 0.95), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.chain().tween_callback(func():
		if is_instance_valid(_hover_info):
			_hover_info.visible = false
	)


var _interactable_tween: Tween = null


## Dims and disables the card (or restores it) with smooth, juicy animations.
func set_interactable(interactable: bool, delay: float = 0.0) -> void:
	_is_interactable = interactable
	if _button:
		_button.disabled = not interactable
	if not interactable:
		_hide_hover_info()

	pivot_offset = size * 0.5

	if _interactable_tween and _interactable_tween.is_valid():
		_interactable_tween.kill()

	_interactable_tween = create_tween().set_parallel(true)

	if interactable:
		var target_modulate := Color(1, 1, 1, 1)
		var tw_mod := _interactable_tween.tween_property(self, "modulate", target_modulate, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var tw_scale := _interactable_tween.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if delay > 0.0:
			tw_mod.set_delay(delay)
			tw_scale.set_delay(delay)
	else:
		var target_modulate := Color(1, 1, 1, 0.45)
		var tw_mod := _interactable_tween.tween_property(self, "modulate", target_modulate, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var tw_scale := _interactable_tween.tween_property(self, "scale", Vector2(0.97, 0.97), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if delay > 0.0:
			tw_mod.set_delay(delay)
			tw_scale.set_delay(delay)

	if not interactable and _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)


func hide_context_menu() -> void:
	if _context_menu:
		_context_menu.visible = false

#endregion
