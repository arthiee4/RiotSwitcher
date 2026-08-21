class_name AddProfileController
extends Control

## "Add profile" form: name input, background picker (built-in or custom
## upload), preview, and creation. Validation errors are shown inline.

signal profile_created_successfully
signal warning_dismissed

const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const ALLOWED_EXTENSIONS: Array[String] = ["png", "jpg", "webp"]

## Injected by Main.
var profile_manager: Node

var _current_custom_bg_path: String = ""
var _background_textures: Array = [] # Built-in backgrounds, aligned with picker buttons.

@onready var _backgrounds_container: Control = $bg_select/backgrounds
@onready var _preview_background: TextureRect = $preview/profile_button/card/Panel/profile_bg
@onready var _browse_button: Button = $upload_custom_bg/browser_button
@onready var _file_dialog: FileDialog = $creation/create_button/FileDialog
@onready var _name_input: LineEdit = $profile_name/LineEdit
@onready var _description_input: LineEdit = $profile_description/LineEdit if has_node("profile_description/LineEdit") else null
@onready var _name_preview: Label = $preview/profile_button/profile_name
@onready var _create_button: Button = $creation/create_button
@onready var _error_label: Label = $error/Label
@onready var _warning_panel: Control = $warning
@onready var _close_warning_button: Button = $warning/closewarning

var _cascade_tweens: Array[Tween] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AppPaths.BACKGROUNDS_DIR)
	_load_background_images()
	_connect_signals()
	reset_form()


## Injected by Main.
func set_profile_manager(pm: Node) -> void:
	profile_manager = pm
	_update_name_preview()


func set_warning_visibility(visible_: bool) -> void:
	_warning_panel.visible = visible_


func reset_form() -> void:
	_error_label.visible = false
	_name_input.text = ""
	if _description_input:
		_description_input.text = ""
	_update_name_preview()
	_preview_background.texture = null
	_current_custom_bg_path = ""


func _load_background_images() -> void:
	_background_textures.clear()
	var index := 0
	for child in _backgrounds_container.get_children():
		var button := child.get_node_or_null("Button")
		if not button:
			continue
		index += 1
		var image_path := "res://assets/backgrounds/profiles_bg/%d.webp" % index
		if ResourceLoader.exists(image_path):
			_background_textures.append(load(image_path))
		else:
			printerr("AddProfile: Built-in background not found: ", image_path)
			_background_textures.append(null)
		button.pressed.connect(_on_standard_background_selected.bind(_background_textures.size() - 1))


func _connect_signals() -> void:
	_name_input.text_changed.connect(_on_name_text_changed)
	if _description_input:
		_description_input.text_submitted.connect(func(_text): _on_create_button_pressed())
	_file_dialog.filters = ["*.png, *.jpg, *.webp ; Image Files"]
	_file_dialog.file_selected.connect(_on_file_selected)
	_browse_button.pressed.connect(_on_browse_button_pressed)
	_create_button.pressed.connect(_on_create_button_pressed)
	_close_warning_button.pressed.connect(_on_close_warning_pressed)


func _generate_auto_profile_name() -> String:
	if not profile_manager:
		return "Account 1"
	var index := 1
	while profile_manager.has_profile("Account %d" % index):
		index += 1
	return "Account %d" % index


func _update_name_preview() -> void:
	if not _name_preview:
		return
	_name_preview.text = _name_input.text.strip_edges()


func _on_create_button_pressed() -> void:
	if not profile_manager:
		_show_error("Internal error: Profile Manager not available.")
		return

	var raw_typed := _name_input.text.strip_edges()
	var has_custom_name := not raw_typed.is_empty()
	var profile_name := raw_typed if has_custom_name else _generate_auto_profile_name()
	var description := _description_input.text.strip_edges() if _description_input else ""

	if not _preview_background.texture:
		_show_error("Please select or upload a background image!")
		return
	if profile_manager.has_profile(profile_name):
		_show_error("Profile name '%s' already exists!" % profile_name)
		return

	_hide_error()
	var background_path := _resolve_background_path()
	if not profile_manager.add_profile(profile_name, background_path, has_custom_name, description):
		_show_error("Failed to create profile! Check logs.")
		return

	reset_form()
	profile_created_successfully.emit()


## Decides which background path gets stored for the new profile.
func _resolve_background_path() -> String:
	if not _current_custom_bg_path.is_empty():
		return _current_custom_bg_path
	var resource_path: String = _preview_background.texture.resource_path
	if resource_path.begins_with("res://"):
		return resource_path
	return DEFAULT_BG_PATH


func _on_browse_button_pressed() -> void:
	_hide_error()
	_file_dialog.popup_centered()


## Copies the picked image into the app's backgrounds folder and previews it.
func _on_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if not extension in ALLOWED_EXTENSIONS:
		_show_error("Invalid file type. Please use PNG, JPG, or WEBP.")
		return

	var typed_name := _name_input.text.strip_edges()
	var base_name := typed_name.validate_filename().replace(" ", "_") if not typed_name.is_empty() else _generate_auto_profile_name().validate_filename().replace(" ", "_")
	var file_name := "%s_%d.%s" % [base_name, Time.get_unix_time_from_system(), extension]
	var destination_path := AppPaths.BACKGROUNDS_DIR.path_join(file_name)

	if DirAccess.copy_absolute(path, destination_path) != OK:
		_show_error("Could not save custom background image.")
		return

	var image := Image.load_from_file(destination_path)
	if not image:
		_show_error("Failed to load saved custom image.")
		_current_custom_bg_path = ""
		return

	_preview_background.texture = ImageTexture.create_from_image(image)
	_current_custom_bg_path = destination_path
	_hide_error()


func _on_standard_background_selected(index: int) -> void:
	if index < 0 or index >= _background_textures.size() or not _background_textures[index]:
		_show_error("Selected background is unavailable.")
		return
	_preview_background.texture = _background_textures[index]
	_current_custom_bg_path = ""
	_hide_error()


func _on_name_text_changed(_new_text: String) -> void:
	_update_name_preview()
	_hide_error()


func _on_close_warning_pressed() -> void:
	_warning_panel.visible = false
	warning_dismissed.emit()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true


func _hide_error() -> void:
	_error_label.visible = false


## Plays a professional staggered cascade entrance animation for the add profile view.
func play_cascade_entrance() -> void:
	for tw in _cascade_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cascade_tweens.clear()

	# 1. Title entrance (slide down + fade)
	var title_node := get_node_or_null("tittle") as Control
	if title_node:
		title_node.modulate.a = 0.0
		var title_has_offset: bool = "offset_transform_enabled" in title_node
		if title_has_offset:
			title_node.set("offset_transform_enabled", true)
			title_node.set("offset_transform_position", Vector2(0.0, -8.0))
			title_node.set("offset_transform_visual_only", true)
		else:
			title_node.position.y = 20.0

		var tw := title_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(title_node, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if title_has_offset:
			tw.tween_property(title_node, "offset_transform_position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(title_node, "position:y", 28.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Input fields (profile_name and profile_description)
	var input_nodes: Array[Control] = []
	var p_name := get_node_or_null("profile_name") as Control
	var p_desc := get_node_or_null("profile_description") as Control
	if p_name: input_nodes.append(p_name)
	if p_desc: input_nodes.append(p_desc)

	for inp in input_nodes:
		inp.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in inp
		if has_offset:
			inp.set("offset_transform_enabled", true)
			inp.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			inp.set("offset_transform_scale", Vector2(0.96, 0.96))
			inp.set("offset_transform_visual_only", false)
		else:
			inp.scale = Vector2(0.96, 0.96)

		var tw := inp.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(inp, "modulate:a", 1.0, 0.16).set_delay(0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(inp, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(inp, "scale", Vector2.ONE, 0.18).set_delay(0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3. Background label ("Choose your bg")
	var bg_label := get_node_or_null("bg_select/Label") as Control
	if bg_label:
		bg_label.modulate.a = 0.0
		var tw := bg_label.create_tween()
		_cascade_tweens.append(tw)
		tw.tween_property(bg_label, "modulate:a", 1.0, 0.14).set_delay(0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Background thumbnails cascade (bgexample1 ... bgexample12)
	if _backgrounds_container:
		var bg_children := _backgrounds_container.get_children()
		for i in range(bg_children.size()):
			var bg_card := bg_children[i] as Control
			if not bg_card or not is_instance_valid(bg_card):
				continue

			bg_card.modulate.a = 0.0
			var has_offset: bool = "offset_transform_enabled" in bg_card
			if has_offset:
				bg_card.set("offset_transform_enabled", true)
				bg_card.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
				bg_card.set("offset_transform_scale", Vector2(0.85, 0.85))
				bg_card.set("offset_transform_visual_only", false)
			else:
				var sz := bg_card.size
				if sz.x > 0 and sz.y > 0:
					bg_card.pivot_offset = sz * 0.5
				bg_card.scale = Vector2(0.85, 0.85)

			var delay: float = 0.06 + (i * 0.025) # 25ms ripple stagger
			var tw := bg_card.create_tween().set_parallel(true)
			_cascade_tweens.append(tw)
			tw.tween_property(bg_card, "modulate:a", 1.0, 0.14).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if has_offset:
				tw.tween_property(bg_card, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				tw.tween_property(bg_card, "scale", Vector2.ONE, 0.18).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 5. Upload custom image & Finish creation
	var bottom_nodes: Array[Control] = []
	var upload_node := get_node_or_null("upload_custom_bg") as Control
	var create_node := get_node_or_null("creation") as Control
	if upload_node: bottom_nodes.append(upload_node)
	if create_node: bottom_nodes.append(create_node)

	for b_node in bottom_nodes:
		b_node.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in b_node
		if has_offset:
			b_node.set("offset_transform_enabled", true)
			b_node.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			b_node.set("offset_transform_scale", Vector2(0.96, 0.96))
			b_node.set("offset_transform_visual_only", false)
		else:
			b_node.scale = Vector2(0.96, 0.96)

		var tw := b_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(b_node, "modulate:a", 1.0, 0.16).set_delay(0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(b_node, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(b_node, "scale", Vector2.ONE, 0.18).set_delay(0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 6. Live preview card zoom pop
	var preview_node := get_node_or_null("preview") as Control
	if preview_node:
		preview_node.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in preview_node
		if has_offset:
			preview_node.set("offset_transform_enabled", true)
			preview_node.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			preview_node.set("offset_transform_scale", Vector2(0.92, 0.92))
			preview_node.set("offset_transform_visual_only", false)
		else:
			var sz := preview_node.size
			if sz.x > 0 and sz.y > 0:
				preview_node.pivot_offset = sz * 0.5
			preview_node.scale = Vector2(0.92, 0.92)

		var tw := preview_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(preview_node, "modulate:a", 1.0, 0.18).set_delay(0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(preview_node, "offset_transform_scale", Vector2.ONE, 0.22).set_delay(0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(preview_node, "scale", Vector2.ONE, 0.22).set_delay(0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
