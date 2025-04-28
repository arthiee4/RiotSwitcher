extends Control

# Signals
signal profile_created_successfully
signal warning_dismissed

# Constants (Consider moving if used elsewhere, but likely specific to add menu)
const DEFAULT_BG_PATH = "res://assets/backgrounds/default_bg.webp"
const CUSTOM_BG_DIR = "user://UserBackground/"

# Dependencies (Injected from Main)
var profile_manager # Must be set externally by main.gd

#region Node References (Assumes script is attached to add_menu node)
@onready var backgrounds_container = $bg_select/backgrounds
@onready var preview_background = $preview/bgexample3/preview_bg
@onready var browser_button = $upload_custom_bg/browser_button
@onready var filedialog = $creation/create_button/FileDialog
@onready var profile_name_input = $profile_name/LineEdit
@onready var profile_name_preview = $preview/preview_profile_name
@onready var create_button = $creation/create_button
@onready var error_label = $error/Label
@onready var warning_main = $warning
@onready var closewarning_button = $warning/closewarning
#endregion

# State Variables
var _current_custom_bg_path: String = ""
var background_images = [] # Holds loaded standard background textures.

func _ready():
	# Ensure the custom background directory exists
	DirAccess.make_dir_recursive_absolute(CUSTOM_BG_DIR) 
		
	load_background_images()
	connect_signals()
	initialize_ui()

func initialize_ui():
	error_label.visible = false
	profile_name_input.text = ""
	profile_name_preview.text = ""
	preview_background.texture = null
	_current_custom_bg_path = ""
	
	# Warning popup visibility is controlled by Main via set_warning_visibility

# Loads the default background images and connects their buttons.
func load_background_images():
	background_images.clear()
	# Assuming buttons are named bgexample1, bgexample2, etc. inside backgrounds_container
	var index = 0
	for child in backgrounds_container.get_children():
		var button = child.get_node_or_null("Button")
		if button:
			index += 1
			var image_path = "res://assets/backgrounds/profiles_bg/{0}.webp".format([index])
			var texture = null
			if ResourceLoader.exists(image_path):
				texture = load(image_path)
				background_images.append(texture)
			else:
				printerr("Background image not found: ", image_path)
				background_images.append(null) # Add null placeholder to keep indices aligned
			
			# Connect with index
			button.pressed.connect(_on_standard_background_selected.bind(index - 1))
		else:
			printerr("Could not find Button node in child: ", child.name)


# Connects internal signals.
func connect_signals():
	profile_name_input.text_changed.connect(_update_profile_name_preview)
	profile_name_input.text_changed.connect(_on_profile_name_text_changed) # Hide error label on type
	filedialog.filters = ["*.png, *.jpg, *.webp ; Image Files"]
	filedialog.file_selected.connect(_on_file_selected)
	browser_button.pressed.connect(_on_browser_button_pressed)
	create_button.pressed.connect(_on_create_button_pressed)
	closewarning_button.pressed.connect(_on_closewarning_pressed) # Still handled here? Or main? Let's keep here for now.

# Called when the "Create" button is pressed.
func _on_create_button_pressed():
	if not profile_manager:
		printerr("ProfileManager dependency not set in AddProfileController!")
		_show_error("Internal error: Profile Manager not available.")
		return

	var profile_name_text = profile_name_input.text.strip_edges()
	var background_texture = preview_background.texture

	# --- Input Validation ---
	if profile_name_text.is_empty():
		_show_error("Profile name cannot be empty!")
		return
	if not background_texture:
		_show_error("Please select or upload a background image!")
		return

	# Check for duplicate profile names using ProfileManager
	for p in profile_manager.get_profiles():
		if p.get("profile_name") == profile_name_text:
			_show_error("Profile name '%s' already exists!" % profile_name_text)
			return
		
	_hide_error() # Hide error if validation passes

	# --- Determine Background Path to Save ---
	var background_path_to_save: String
	if not _current_custom_bg_path.is_empty():
		# Use the user:// path we saved when the file was selected and copied
		background_path_to_save = _current_custom_bg_path 
	elif background_texture and background_texture.resource_path and background_texture.resource_path.begins_with("res://"):
		# It's a standard background, use its res:// path
		background_path_to_save = background_texture.resource_path
	else:
		# Fallback if something went wrong
		printerr("Warning: Could not determine background path. Using default.")
		background_path_to_save = DEFAULT_BG_PATH

	# --- Let ProfileManager handle directory creation and saving data ---
	if not profile_manager.add_profile(profile_name_text, background_path_to_save):
		_show_error("Failed to create profile! Check logs.") # PM logs details
		# emit_signal("profile_creation_failed", "Failed to create profile! Check logs.") # Alternative
		return # Don't proceed if saving failed

	# --- Cleanup and Signal Success --- 
	print("Profile creation succeeded for: ", profile_name_text)
	initialize_ui() # Reset the form
	emit_signal("profile_created_successfully")


# Called when the "Browse..." button for custom backgrounds is pressed.
func _on_browser_button_pressed():
	if profile_name_input.text.strip_edges().is_empty():
		_show_error("Please enter a profile name first!")
		return
	_hide_error()
	filedialog.popup_centered()

# Called when the user selects a file in the FileDialog.
func _on_file_selected(path: String):
	# --- Read the selected image file ---
	var original_file = FileAccess.open(path, FileAccess.READ)
	if not original_file:
		printerr("Error: Cannot read selected file: ", path)
		_show_error("Could not read selected image file.")
		return
	var file_content = original_file.get_buffer(original_file.get_length())
	original_file.close()

	# --- Prepare a unique filename for saving ---
	var base_name = profile_name_input.text.strip_edges().replace(" ", "_").validate_filename()
	if base_name.is_empty(): base_name = "untitled_profile"
	var extension = path.get_extension().to_lower()
	if not extension in ["png", "jpg", "webp"]:
		printerr("Invalid file extension selected: ", extension)
		_show_error("Invalid file type. Please use PNG, JPG, or WEBP.")
		return
	var unique_suffix = str(Time.get_unix_time_from_system())
	var new_file_name = "%s_%s.%s" % [base_name, unique_suffix, extension]

	# --- Save the image to the user://UserBackground/ directory ---
	var destination_path = CUSTOM_BG_DIR.path_join(new_file_name)
	var destination_file = FileAccess.open(destination_path, FileAccess.WRITE)
	if not destination_file:
		printerr("Error: Cannot create or write to destination file: ", destination_path)
		_show_error("Could not save custom background image.")
		return
	destination_file.store_buffer(file_content)
	destination_file.close()

	# --- Load the *copied* image for the preview ---
	var img = Image.load_from_file(destination_path)
	if img:
		var texture = ImageTexture.create_from_image(img)
		preview_background.texture = texture
		_current_custom_bg_path = destination_path # Store user:// path for saving
		print("Custom image loaded and saved to: ", destination_path)
		_hide_error()
	else:
		printerr("Error: Failed to load copied image for preview: ", destination_path)
		_show_error("Failed to load saved custom image.")
		_current_custom_bg_path = "" # Clear path on failure

# Updates the text preview as the user types.
func _update_profile_name_preview(user_input: String):
	profile_name_preview.text = user_input

# Called when one of the standard background buttons is pressed.
func _on_standard_background_selected(index: int):
	if index >= 0 and index < background_images.size():
		var texture = background_images[index]
		if texture:
			preview_background.texture = texture
			_current_custom_bg_path = "" # Clear custom path
			_hide_error()
		else:
			printerr("Selected background button corresponds to a missing image texture (Index: %d)." % index)
			_show_error("Selected background is unavailable.")
	else:
		printerr("Invalid background button index pressed: ", index)


# Hides the error label when the user starts typing in the profile name field.
func _on_profile_name_text_changed(new_text: String):
	if error_label and error_label.visible:
		_hide_error()

# Helper to show an error message.
func _show_error(message: String):
	if error_label:
		error_label.text = message
		error_label.visible = true
	printerr("Add Menu Error: ", message) # Also log it

# Helper to hide the error message.
func _hide_error():
	if error_label: error_label.visible = false

# Handle closing the warning popup - This might need coordination with main/configmanager
func _on_closewarning_pressed():
	print("[AddProfileController] _on_closewarning_pressed: Button pressed.")
	if warning_main:
		warning_main.visible = false
	print("[AddProfileController] Emitting warning_dismissed signal.")
	emit_signal("warning_dismissed")


# Public function to set the ProfileManager dependency
func set_profile_manager(pm):
	profile_manager = pm

# Public function to potentially show/hide the warning panel based on config
func set_warning_visibility(visible: bool):
	if warning_main:
		warning_main.visible = visible 
