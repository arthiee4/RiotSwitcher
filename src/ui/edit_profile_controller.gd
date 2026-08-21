class_name EditProfileController
extends Control

## Controller for the Edit Profile modal popup.
## Matches the exact design of add_menu with a live 1.5x profile_button preview,
## a full 12-preset background grid, browser upload button, and safe saving.

signal profile_edited(old_name: String, new_name: String)

const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const ALLOWED_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]

var profile_manager: Node

var _original_profile_data: Dictionary = {}
var _current_bg_path: String = ""
var _is_open: bool = false
var _anim_tween: Tween = null

@onready var _backdrop: ColorRect = $backdrop if has_node("backdrop") else find_child("backdrop", true, false)
@onready var _panel: Panel = $Panel if has_node("Panel") else find_child("Panel", true, false)
@onready var _name_input: LineEdit = $Panel/profile_name/Panel/LineEdit if has_node("Panel/profile_name/Panel/LineEdit") else find_child("LineEdit", true, false)
@onready var _desc_input: LineEdit = $Panel/profile_description/Panel/LineEdit if has_node("Panel/profile_description/Panel/LineEdit") else null
@onready var _preview_button: Control = $Panel/preview/profile_button if has_node("Panel/preview/profile_button") else find_child("profile_button", true, false)
@onready var _preview_name: Label = $Panel/preview/profile_button/profile_name if has_node("Panel/preview/profile_button/profile_name") else find_child("profile_name", true, false)
@onready var _preview_bg: TextureRect = $Panel/preview/profile_button/card/Panel/profile_bg if has_node("Panel/preview/profile_button/card/Panel/profile_bg") else find_child("profile_bg", true, false)
@onready var _backgrounds_container: Control = $Panel/bg_select/backgrounds if has_node("Panel/bg_select/backgrounds") else find_child("backgrounds", true, false)
@onready var _browse_button: Button = $Panel/upload_custom_bg/browser_button if has_node("Panel/upload_custom_bg/browser_button") else find_child("browser_button", true, false)
@onready var _file_dialog: FileDialog = $FileDialog if has_node("FileDialog") else find_child("FileDialog", true, false)
@onready var _cancel_button: Button = $Panel/actions/cancel_button if has_node("Panel/actions/cancel_button") else find_child("cancel_button", true, false)
@onready var _save_button: Button = $Panel/actions/save_button if has_node("Panel/actions/save_button") else find_child("save_button", true, false)
@onready var _error_label: Label = $Panel/error/Label if has_node("Panel/error/Label") else find_child("Label", true, false)


func _ready() -> void:
	visible = false
	_hide_error()

	if not profile_manager:
		profile_manager = ProfileManager

	_cancel_button.pressed.connect(close)
	_save_button.pressed.connect(_on_save_pressed)
	_name_input.text_changed.connect(_on_name_text_changed)
	_name_input.text_submitted.connect(func(_text): _on_save_pressed())
	if _desc_input:
		_desc_input.text_submitted.connect(func(_text): _on_save_pressed())
	_browse_button.pressed.connect(_on_upload_button_pressed)
	_file_dialog.file_selected.connect(_on_file_selected)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)

	# Disable card interactions in preview mode
	if _preview_button:
		_preview_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card_btn := _preview_button.get_node_or_null("card")
		if card_btn:
			card_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card_inner_btn := _preview_button.get_node_or_null("card/card_inner/Button")
		if card_inner_btn:
			card_inner_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_connect_preset_buttons()


func _connect_preset_buttons() -> void:
	if not _backgrounds_container:
		return

	for i in range(_backgrounds_container.get_child_count()):
		var bg_panel := _backgrounds_container.get_child(i)
		var btn: Button = bg_panel.get_node_or_null("Button")
		if btn:
			var bg_idx := i + 1
			var path := "res://assets/backgrounds/profiles_bg/%d.webp" % bg_idx
			btn.pressed.connect(func(): _on_preset_selected(path))


## Opens the edit modal for a given profile dictionary.
func open_edit(profile_data: Dictionary) -> void:
	if profile_data.is_empty():
		return

	_original_profile_data = profile_data.duplicate()
	var current_name: String = profile_data.get("profile_name", "")
	_current_bg_path = profile_data.get("custom_background_image", "")

	_name_input.text = current_name
	if _desc_input:
		_desc_input.text = profile_data.get("description", "")
	_preview_name.text = current_name
	_update_bg_preview()
	_hide_error()

	_is_open = true
	visible = true

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	# Initial smooth zoom & fade animation
	_backdrop.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.94, 0.94)
	_panel.pivot_offset = _panel.size * 0.5

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_name_input.grab_focus()
	_name_input.select_all()


## Closes the modal with a smooth fade-out animation.
func close() -> void:
	if not _is_open:
		return
	_is_open = false

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "scale", Vector2(0.95, 0.95), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.chain().tween_callback(func(): visible = false)


func _on_name_text_changed(new_text: String) -> void:
	_preview_name.text = new_text if not new_text.strip_edges().is_empty() else _original_profile_data.get("profile_name", "")
	_hide_error()


func _on_preset_selected(bg_path: String) -> void:
	_current_bg_path = bg_path
	_update_bg_preview()
	_hide_error()


func _on_upload_button_pressed() -> void:
	_file_dialog.popup_centered(Vector2i(650, 450))


func _on_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if not extension in ALLOWED_EXTENSIONS:
		_show_error("Invalid file format. Use PNG, JPG, or WEBP.")
		return

	var typed_name := _name_input.text.strip_edges()
	var base_name := typed_name.validate_filename().replace(" ", "_") if not typed_name.is_empty() else "bg"
	var file_name := "%s_%d.%s" % [base_name, Time.get_unix_time_from_system(), extension]
	var destination_path := AppPaths.BACKGROUNDS_DIR.path_join(file_name)

	if DirAccess.copy_absolute(path, destination_path) != OK:
		_show_error("Could not save custom background image.")
		return

	_current_bg_path = destination_path
	_update_bg_preview()
	_hide_error()


func _update_bg_preview() -> void:
	if not _preview_bg:
		return

	if _current_bg_path.is_empty():
		_preview_bg.texture = load(DEFAULT_BG_PATH)
		return

	if _current_bg_path.begins_with("res://"):
		if ResourceLoader.exists(_current_bg_path):
			_preview_bg.texture = load(_current_bg_path)
		else:
			_preview_bg.texture = load(DEFAULT_BG_PATH)
		return

	if FileAccess.file_exists(_current_bg_path):
		var img := Image.load_from_file(_current_bg_path)
		if img:
			_preview_bg.texture = ImageTexture.create_from_image(img)
			return

	_preview_bg.texture = load(DEFAULT_BG_PATH)


func _on_save_pressed() -> void:
	var old_name: String = _original_profile_data.get("profile_name", "")
	var new_name := _name_input.text.strip_edges()

	if new_name.is_empty():
		_show_error("Profile name cannot be empty.")
		return

	if new_name != old_name and profile_manager.has_profile(new_name):
		_show_error("A profile named '%s' already exists." % new_name)
		return

	var description: String = _desc_input.text.strip_edges() if _desc_input else ""

	var success: bool = profile_manager.update_profile(
		old_name,
		new_name,
		_current_bg_path,
		true,
		true,
		description
	)

	if not success:
		_show_error("Failed to update profile. Please try again.")
		return

	profile_edited.emit(old_name, new_name)
	close()


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		close()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
		close()
		get_viewport().set_input_as_handled()


func _show_error(message: String) -> void:
	if _error_label:
		_error_label.text = message
		_error_label.visible = true


func _hide_error() -> void:
	if _error_label:
		_error_label.visible = false
