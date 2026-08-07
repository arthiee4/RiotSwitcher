extends Control

## "Add profile" form: name input, background picker (built-in or custom
## upload), preview, and creation. Validation errors are shown inline.

signal profile_created_successfully
signal warning_dismissed

const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const ALLOWED_EXTENSIONS: Array[String] = ["png", "jpg", "webp"]

## Injected by Main.
var profile_manager: ProfileManager

var _current_custom_bg_path: String = ""
var _background_textures: Array = [] # Built-in backgrounds, aligned with picker buttons.

@onready var _backgrounds_container: Control = $bg_select/backgrounds
@onready var _preview_background: TextureRect = $preview/bgexample3/preview_bg
@onready var _browse_button: Button = $upload_custom_bg/browser_button
@onready var _file_dialog: FileDialog = $creation/create_button/FileDialog
@onready var _name_input: LineEdit = $profile_name/LineEdit
@onready var _name_preview: Label = $preview/preview_profile_name
@onready var _create_button: Button = $creation/create_button
@onready var _error_label: Label = $error/Label
@onready var _warning_panel: Control = $warning
@onready var _close_warning_button: Button = $warning/closewarning


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AppPaths.BACKGROUNDS_DIR)
	_load_background_images()
	_connect_signals()
	reset_form()


## Injected by Main.
func set_profile_manager(pm: ProfileManager) -> void:
	profile_manager = pm


func set_warning_visibility(visible_: bool) -> void:
	_warning_panel.visible = visible_


func reset_form() -> void:
	_error_label.visible = false
	_name_input.text = ""
	_name_preview.text = ""
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
	_file_dialog.filters = ["*.png, *.jpg, *.webp ; Image Files"]
	_file_dialog.file_selected.connect(_on_file_selected)
	_browse_button.pressed.connect(_on_browse_button_pressed)
	_create_button.pressed.connect(_on_create_button_pressed)
	_close_warning_button.pressed.connect(_on_close_warning_pressed)


func _on_create_button_pressed() -> void:
	if not profile_manager:
		_show_error("Internal error: Profile Manager not available.")
		return

	var profile_name := _name_input.text.strip_edges()
	if profile_name.is_empty():
		_show_error("Profile name cannot be empty!")
		return
	if not _preview_background.texture:
		_show_error("Please select or upload a background image!")
		return
	if profile_manager.has_profile(profile_name):
		_show_error("Profile name '%s' already exists!" % profile_name)
		return

	_hide_error()
	var background_path := _resolve_background_path()
	if not profile_manager.add_profile(profile_name, background_path):
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
	if _name_input.text.strip_edges().is_empty():
		_show_error("Please enter a profile name first!")
		return
	_hide_error()
	_file_dialog.popup_centered()


## Copies the picked image into the app's backgrounds folder and previews it.
func _on_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if not extension in ALLOWED_EXTENSIONS:
		_show_error("Invalid file type. Please use PNG, JPG, or WEBP.")
		return

	var base_name := _name_input.text.strip_edges().validate_filename().replace(" ", "_")
	if base_name.is_empty():
		base_name = "untitled_profile"
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


func _on_name_text_changed(new_text: String) -> void:
	_name_preview.text = new_text
	_hide_error()


func _on_close_warning_pressed() -> void:
	_warning_panel.visible = false
	warning_dismissed.emit()


func _show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true


func _hide_error() -> void:
	_error_label.visible = false
