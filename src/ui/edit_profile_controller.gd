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
var _cascade_tweens: Array[Tween] = []

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
	_cancel_button.set_meta("sfx", &"cancel")
	_save_button.pressed.connect(_on_save_pressed)
	_save_button.set_meta("sfx", &"confirm")
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
	SfxManager.open()

	_kill_cascade()

	# Backdrop fade + subtle scale-in of the whole panel around its center
	_backdrop.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.96, 0.96)

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "modulate:a", 1.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_play_cascade()

	_name_input.grab_focus()
	_name_input.select_all()


func _kill_cascade() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	for tw in _cascade_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cascade_tweens.clear()


func _play_cascade() -> void:
	# Fast, subtle stagger (~0.2s total) so the modal feels snappy.
	# 1. Title — fade in
	var title_node := _panel.get_node_or_null("title") as Control
	if title_node:
		title_node.modulate.a = 0.0
		var tw := title_node.create_tween()
		_cascade_tweens.append(tw)
		tw.tween_property(title_node, "modulate:a", 1.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Inputs (profile_name, profile_description) — fade + subtle scale pop
	var input_nodes: Array[Control] = []
	var p_name := _panel.get_node_or_null("profile_name") as Control
	var p_desc := _panel.get_node_or_null("profile_description") as Control
	if p_name: input_nodes.append(p_name)
	if p_desc: input_nodes.append(p_desc)

	for i in range(input_nodes.size()):
		var inp := input_nodes[i]
		inp.modulate.a = 0.0
		inp.scale = Vector2(0.98, 0.98)
		var delay := 0.02 + i * 0.02
		var tw := inp.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(inp, "modulate:a", 1.0, 0.10).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(inp, "scale", Vector2.ONE, 0.16).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3. Bg label
	var bg_label := _panel.get_node_or_null("bg_select/Label") as Control
	if bg_label:
		bg_label.modulate.a = 0.0
		var tw := bg_label.create_tween()
		_cascade_tweens.append(tw)
		tw.tween_property(bg_label, "modulate:a", 1.0, 0.10).set_delay(0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Background thumbnails — quick ripple stagger
	if _backgrounds_container:
		var bg_children := _backgrounds_container.get_children()
		for i in range(bg_children.size()):
			var bg_card := bg_children[i] as Control
			if not bg_card or not is_instance_valid(bg_card):
				continue
			bg_card.modulate.a = 0.0
			var sz := bg_card.size
			if sz.x > 0 and sz.y > 0:
				bg_card.pivot_offset = sz * 0.5
			bg_card.scale = Vector2(0.92, 0.92)
			var delay: float = 0.04 + i * 0.012
			var tw := bg_card.create_tween().set_parallel(true)
			_cascade_tweens.append(tw)
			tw.tween_property(bg_card, "modulate:a", 1.0, 0.10).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(bg_card, "scale", Vector2.ONE, 0.16).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 5. Upload row + actions
	var bottom_nodes: Array[Control] = []
	var upload_node := _panel.get_node_or_null("upload_custom_bg") as Control
	var actions_node := _panel.get_node_or_null("actions") as Control
	if upload_node: bottom_nodes.append(upload_node)
	if actions_node: bottom_nodes.append(actions_node)

	for b_node in bottom_nodes:
		b_node.modulate.a = 0.0
		b_node.scale = Vector2(0.98, 0.98)
		var tw := b_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(b_node, "modulate:a", 1.0, 0.10).set_delay(0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b_node, "scale", Vector2.ONE, 0.16).set_delay(0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 6. Preview card — quick zoom pop
	var preview_node := _panel.get_node_or_null("preview") as Control
	if preview_node:
		preview_node.modulate.a = 0.0
		var sz := preview_node.size
		if sz.x > 0 and sz.y > 0:
			preview_node.pivot_offset = sz * 0.5
		preview_node.scale = Vector2(0.94, 0.94)
		var tw := preview_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(preview_node, "modulate:a", 1.0, 0.12).set_delay(0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(preview_node, "scale", Vector2.ONE, 0.18).set_delay(0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Closes the modal with a smooth fade-out animation.
func close() -> void:
	if not _is_open:
		return
	_is_open = false

	_kill_cascade()

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "scale", Vector2(0.97, 0.97), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
		SfxManager.cancel()
		close()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
		SfxManager.cancel()
		close()
		get_viewport().set_input_as_handled()


func _show_error(message: String) -> void:
	if _error_label:
		_error_label.text = message
		_error_label.visible = true
	SfxManager.error()


func _hide_error() -> void:
	if _error_label:
		_error_label.visible = false
