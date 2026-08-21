class_name ProfileButton
extends Control

## A single profile card in the grid. It only handles presentation and user
## input; all heavy work (killing processes, swapping session files) is
## orchestrated by ProfileGridController, which confirms state changes back
## through confirm_started()/confirm_stopped()/reset_toggle_state().

signal client_toggled(profile_button: Control, is_starting: bool)
signal delete_requested(profile_button: Control)
signal edit_requested(profile_button: Control)

const PLAY_ICON: Texture2D = preload("res://assets/icons/ui/icon_play.png")
const STOP_ICON: Texture2D = preload("res://assets/icons/ui/icon_stop.png")
const DRAG_THRESHOLD := 6.0

## Full profile dictionary from ProfileManager. Set right after instantiation.
var profile_data: Dictionary = {}

var client_is_running := false
var _is_interactable := true
var _is_transitioning := false

# Drag & click state
var _is_mouse_down := false
var _drag_start_pos := Vector2.ZERO

@onready var _context_menu: Control = $card/context_menu
@onready var _delete_button: TextureButton = $card/context_menu/Panel/delete/TextureButton
@onready var _edit_button: TextureButton = $card/context_menu/Panel/edit/TextureButton
@onready var _glow_effect: Control = $card/card_inner/glow
@onready var _button: Button = $card/card_inner/Button
@onready var _state_icon: TextureRect = $card/card_inner/Button/TextureRect
@onready var _card: Control = $card


var profile_name: String:
	get: return profile_data.get("profile_name", "")


func _ready() -> void:
	_delete_button.pressed.connect(_on_delete_button_pressed)
	if _edit_button:
		_edit_button.pressed.connect(_on_edit_button_pressed)
	_card.gui_input.connect(_on_card_gui_input)
	if _button and _button is Button and not _button.pressed.is_connected(_on_profile_button_pressed):
		_button.pressed.connect(_on_profile_button_pressed)
	_context_menu.visible = false
	set_process_input(true)


#region State confirmation (called by ProfileGridController)

## Confirms the client for this profile is now running.
func confirm_started() -> void:
	client_is_running = true
	_is_transitioning = false
	_state_icon.texture = STOP_ICON


## Confirms the client was stopped and the session saved.
func confirm_stopped() -> void:
	client_is_running = false
	_is_transitioning = false
	_state_icon.texture = PLAY_ICON


## Reverts the toggle after a failed start/stop attempt.
func reset_toggle_state() -> void:
	client_is_running = false
	_is_transitioning = false
	_state_icon.texture = PLAY_ICON

#endregion

#region Input handlers

func _on_profile_button_pressed() -> void:
	if _is_transitioning:
		return
	if not _is_interactable and not client_is_running:
		return
	_is_transitioning = true
	if not client_is_running:
		_state_icon.texture = STOP_ICON
	else:
		_state_icon.texture = PLAY_ICON
	client_toggled.emit(self, not client_is_running)


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


func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			if not _is_interactable or _is_transitioning:
				get_viewport().set_input_as_handled()
				return
			_context_menu.visible = true
			_context_menu.global_position = event.global_position
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				if _context_menu.visible:
					_context_menu.visible = false
					get_viewport().set_input_as_handled()
					return
				if not _is_interactable or _is_transitioning or profile_data.is_empty():
					return
				var parent_grid = get_parent()
				if parent_grid and parent_grid.has_method("_is_busy") and parent_grid._is_busy():
					return

				_is_mouse_down = true
				_drag_start_pos = event.global_position
			else:
				# Mouse release on card body (clicking card body does not start profile)
				_is_mouse_down = false

	elif event is InputEventMouseMotion:
		if _is_mouse_down:
			if event.global_position.distance_to(_drag_start_pos) >= DRAG_THRESHOLD:
				_is_mouse_down = false
				var parent_grid = get_parent()
				if parent_grid and parent_grid.has_method("start_card_drag"):
					parent_grid.start_card_drag(self, event.global_position)


## Hides the context menu when clicking anywhere outside of it.
func _input(event: InputEvent) -> void:
	if not _context_menu.visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		if not _context_menu.get_global_rect().has_point(event.position):
			_context_menu.visible = false

#endregion

#region Visual state

func _on_card_mouse_entered() -> void:
	if not _is_interactable:
		return
	var tween := create_tween()
	tween.tween_property(_glow_effect, "modulate", Color(1, 1, 1, 0.4), 0.02).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


func _on_card_mouse_exited() -> void:
	if not _is_interactable:
		return
	var tween := create_tween()
	tween.tween_property(_glow_effect, "modulate", Color(1, 1, 1, 0.0), 0.02).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


## Dims and disables the card (or restores it) with a short animation.
func set_interactable(interactable: bool) -> void:
	_is_interactable = interactable
	_button.disabled = not interactable

	var target_modulate := Color(1, 1, 1, 1) if interactable else Color(1, 1, 1, 0.5)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate", target_modulate, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)

	if not interactable and _card.get_global_rect().has_point(get_global_mouse_position()):
		tween.tween_property(_glow_effect, "modulate", Color(1, 1, 1, 0.0), 0.01).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


func hide_context_menu() -> void:
	_context_menu.visible = false

#endregion
