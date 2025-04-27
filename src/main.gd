extends Control

### --- Constants --- ###
const ADD_PROFILE_BUTTON_SCENE = preload("res://scenes/components/profile_button.tscn")
const CONFIG_PATH = "res://Data/configs.json"
const PROFILES_PATH = "res://Data/profiles_data.json"
const DEFAULT_BG_PATH = "res://assets/backgrounds/default_bg.webp"
const PROFILE_DIR_BASE = "user://profiles/"
const CUSTOM_BG_DIR = "user://UserBackground/"

### --- Node References --- ###

#region Left Menu & Highlight
@onready var add_prof_button = $leftmenu_side/add_prof_button/Button
@onready var add_prof_button_panel = $leftmenu_side/add_prof_button
@onready var add_icon = $leftmenu_side/add_prof_button/Button/TextureRect
@onready var add_selected_panel = $leftmenu_side/add_prof_button/selected_panel

@onready var home_button = $leftmenu_side/home_button/Button
@onready var home_button_panel = $leftmenu_side/home_button
@onready var home_icon = $leftmenu_side/home_button/Button/TextureRect
@onready var home_selected_panel = $leftmenu_side/home_button/selected_panel

@onready var settings_button = $leftmenu_side/settings_button/Button
@onready var settings_button_panel = $leftmenu_side/settings_button
@onready var settings_icon = $leftmenu_side/settings_button/Button/TextureRect
@onready var settings_selected_panel = $leftmenu_side/settings_button/selected_panel

@onready var icon_highlight = $leftmenu_side/iconhighlight
@onready var glow_color = $leftmenu_side/iconhighlight/glow
@onready var glow_panel_color = $leftmenu_side/iconhighlight/Panel
#endregion

#region Content Area
@onready var profiles_grid = $contet_side/GridContainer
#endregion

#region Main Views / Popups
@onready var settings_menu = $settings_menu
@onready var add_menu = $add_menu
@onready var boot_screen = $boot
#endregion

#region Add Menu Specifics
@onready var backgrounds = $add_menu/bg_select/backgrounds
@onready var preview_background = $add_menu/preview/bgexample3/preview_bg
@onready var browser_button = $add_menu/upload_custom_bg/browser_button
@onready var filedialog = $add_menu/creation/create_button/FileDialog
@onready var profile_name = $add_menu/profile_name/LineEdit
@onready var profile_name_preview = $add_menu/preview/preview_profile_name
@onready var create_button = $add_menu/creation/create_button
@onready var add_menu_error_label = $add_menu/error/Label # Renamed from settings_error for clarity
@onready var warning_main = $add_menu/warning
@onready var closewarning = $add_menu/warning/closewarning

# Background selection buttons (consider putting in an array if modified often)
@onready var bgexample1 = $add_menu/bg_select/backgrounds/bgexample1/Button
@onready var bgexample2 = $add_menu/bg_select/backgrounds/bgexample2/Button
@onready var bgexample3 = $add_menu/bg_select/backgrounds/bgexample3/Button
@onready var bgexample4 = $add_menu/bg_select/backgrounds/bgexample4/Button
@onready var bgexample5 = $add_menu/bg_select/backgrounds/bgexample5/Button
@onready var bgexample6 = $add_menu/bg_select/backgrounds/bgexample6/Button
@onready var bgexample7 = $add_menu/bg_select/backgrounds/bgexample7/Button
@onready var bgexample8 = $add_menu/bg_select/backgrounds/bgexample8/Button
@onready var bgexample9 = $add_menu/bg_select/backgrounds/bgexample9/Button
@onready var bgexample10 = $add_menu/bg_select/backgrounds/bgexample10/Button
@onready var bgexample11 = $add_menu/bg_select/backgrounds/bgexample11/Button
@onready var bgexample12 = $add_menu/bg_select/backgrounds/bgexample12/Button
#endregion

### --- State Variables --- ###
var active_profile_button = null # Stores a reference to the currently running profile button, if any.
var _current_custom_bg_path: String = "" # Holds path if user uploads a custom background for a new profile.
var riot_client_location: String = "" # Stores the path to the Riot Client install, loaded from configs.json.
var profile_counter: int = 0 # Tracks the number of profiles.
var background_images = [] # Holds loaded standard background textures.


### --- Initialization --- ###
func _ready():
	# Ensure necessary user directories exist.
	DirAccess.make_dir_recursive_absolute(CUSTOM_BG_DIR)
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR_BASE)
	
	load_configs()
	load_background_images()
	connect_signals()
	initialize_ui()
	load_profile_counter()
	load_profiles()


### --- Loading & Setup Functions --- ###

# Reads settings from configs.json and applies them.
func load_configs():
	var config_data = _load_json_data(CONFIG_PATH)
	if not config_data:
		printerr("Failed to load or parse config file. Using defaults.")
		config_data = {} # Ensure data is a dictionary even on failure
	
	# Load Riot Client Location
	riot_client_location = config_data.get("RiotClientLocation", "")
	if riot_client_location.is_empty():
		printerr("Warning: RiotClientLocation not found or empty in configs.json")
	else:
		print("Riot Client Location loaded: ", riot_client_location)
	
	# Handle boot screen visibility based on client location
	if boot_screen:
		boot_screen.visible = riot_client_location.is_empty()
		if boot_screen.visible: print("Riot Client location not set. Showing boot screen.")
		else: print("Riot Client location found. Hiding boot screen.")

	# Handle warning popup visibility
	var warning_dismissed = config_data.get("warning_shown", false)
	if warning_main:
		warning_main.visible = not warning_dismissed
		if warning_main.visible: print("Warning popup will be shown.")
		else: print("Warning popup already dismissed.")

# Sets the profile counter based on data in profiles_data.json.
func load_profile_counter():
	var profile_data = _load_json_data(PROFILES_PATH)
	if profile_data and profile_data.has("profiles") and profile_data["profiles"] is Array:
		profile_counter = profile_data["profiles"].size()
	else:
		profile_counter = 0
	print("Initial profile count: ", profile_counter)

# Loads all saved profile data and creates the buttons in the grid.
func load_profiles():
	var data = _load_json_data(PROFILES_PATH)
	if not data or not data.has("profiles") or not data["profiles"] is Array:
		print("No profiles found or invalid format in profiles_data.json.")
		return

	# Clear out any old profile buttons first.
	for child in profiles_grid.get_children():
		child.queue_free()

	# Create buttons for each profile entry.
	for profile_data in data["profiles"]:
		if profile_data is Dictionary:
			_create_profile_button(profile_data)

# Loads the default background images and connects their buttons.
func load_background_images():
	background_images.clear()
	for i in range(1, 13):
		var image_path = "res://assets/backgrounds/profiles_bg/{0}.webp".format([i])
		if ResourceLoader.exists(image_path):
			background_images.append(load(image_path))
		else:
			printerr("Background image not found: ", image_path)

		var button_path = "add_menu/bg_select/backgrounds/bgexample{0}/Button".format([i])
		var button = get_node_or_null(button_path)
		if button:
			# Connect with index - make sure array is populated first if used
			if i-1 < background_images.size():
				button.pressed.connect(on_button_pressed.bind(i - 1))
			else:
				# Fallback if image didn't load but button exists
				button.pressed.connect(on_button_pressed.bind(-1)) # Indicate invalid index
		else:
			printerr("Background button node not found: ", button_path)

# Connects signals for various UI elements.
func connect_signals():
	# Add Menu
	profile_name.text_changed.connect(update_profile_name_preview)
	profile_name.text_changed.connect(_on_profile_name_text_changed) # Hide error label on type
	filedialog.filters = ["*.png, *.jpg, *.webp ; Image Files"]
	filedialog.file_selected.connect(_on_file_selected)
	browser_button.pressed.connect(_on_browser_button_pressed)
	create_button.pressed.connect(_on_create_button_pressed)
	closewarning.pressed.connect(_on_closewarning_pressed)

	# Left Menu (Connections made in the editor are redundant here)
	# home_button.pressed.connect(_on_home_button_pressed)
	# settings_button.pressed.connect(_on_settings_button_pressed)
	add_prof_button.pressed.connect(_on_add_prof_button_pressed)

	# Boot Screen
	if boot_screen:
		if boot_screen.has_signal("client_location_saved"): # Check if signal exists before connecting
			boot_screen.client_location_saved.connect(_on_boot_client_location_saved)
		else:
			printerr("Boot screen node does not have 'client_location_saved' signal.")
	else:
		printerr("Boot screen node not found, cannot connect signals.")

# Sets the initial visual state of the UI.
func initialize_ui():
	glow_color.color = Color(1, 0, 0, 0.1) # Home color initially
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	home_selected_panel.visible = true # Start on the home screen.
	move_icon_highlight(home_button_panel.position.y) # Position the highlight.
	if add_menu_error_label: add_menu_error_label.visible = false
	else: printerr("Add Menu Error Label node not found.")


### --- Left Menu Button Handlers --- ###
func _on_home_button_pressed():
	update_selected_panel(home_selected_panel, home_button_panel)
	# Set highlight colors for Home (Red theme).
	glow_color.color = Color(1, 0, 0, 0.1)
	var stylebox = glow_panel_color.get_theme_stylebox("panel")
	if stylebox: stylebox.bg_color = Color(1, 0, 0, 1)
	home_icon.modulate = Color(1, 0, 0, 1)

func _on_settings_button_pressed():
	update_selected_panel(settings_selected_panel, settings_button_panel)
	# Set highlight colors for Settings (Orange theme).
	glow_color.color = Color(214/255.0, 129/255.0, 0, 0.5)
	var stylebox = glow_panel_color.get_theme_stylebox("panel")
	if stylebox: stylebox.bg_color = Color(214/255.0, 129/255.0, 0, 1)
	settings_icon.modulate = Color(214/255.0, 129/255.0, 0, 1)

func _on_add_prof_button_pressed():
	update_selected_panel(add_selected_panel, add_prof_button_panel)
	# Set highlight colors for Add (Blue theme).
	glow_color.color = Color(0, 0, 1, 0.5)
	var stylebox = glow_panel_color.get_theme_stylebox("panel")
	if stylebox: stylebox.bg_color = Color(0, 0, 1, 1)
	add_icon.modulate = Color(0, 0, 1, 1)


### --- Add Profile Menu Handlers --- ###

# Called when the "Create" button is pressed.
func _on_create_button_pressed():
	var profile_name_text = profile_name.text.strip_edges()
	var background_texture = preview_background.texture

	# --- Input Validation ---
	if profile_name_text.is_empty():
		_show_add_menu_error("Profile name cannot be empty!")
		return
	if not background_texture:
		_show_add_menu_error("Please select or upload a background image!")
		return
	_hide_add_menu_error() # Hide error if validation passes

	# --- Create Profile Directory ---
	var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
	if sanitized_profile_name.is_empty():
		sanitized_profile_name = "profile_" + str(Time.get_unix_time_from_system())
		printerr("Invalid profile name for directory, using fallback: ", sanitized_profile_name)
	var profile_dir_path = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
	var err = DirAccess.make_dir_recursive_absolute(profile_dir_path)
	if err != OK:
		printerr("Failed to create profile directory: ", profile_dir_path, ". Error: ", err)
		_show_add_menu_error("Failed to create profile directory!")
		return

	# --- Determine Background Path to Save ---
	var background_path_to_save: String
	if not _current_custom_bg_path.is_empty():
		background_path_to_save = _current_custom_bg_path
	elif background_texture and background_texture.resource_path and background_texture.resource_path.begins_with("res://"):
		background_path_to_save = background_texture.resource_path
	else:
		printerr("Warning: Could not determine standard background path. Using default.")
		background_path_to_save = DEFAULT_BG_PATH

	# --- Prepare Profile Data ---
	var new_profile_data = {
		"profile_name": profile_name_text,
		"custom_background_image": background_path_to_save,
		"first_time_opened": false # Assume Riot client manages first time state
	}

	# --- Save Data to JSON ---
	if not _append_to_json_array(PROFILES_PATH, "profiles", new_profile_data):
		_show_add_menu_error("Failed to save profile data!")
		return # Don't create the button if saving failed

	# --- Create UI Button --- (Only after successful save)
	_create_profile_button(new_profile_data)

	# --- Cleanup and Navigate ---
	profile_name.text = ""
	preview_background.texture = null
	profile_name_preview.text = ""
	_current_custom_bg_path = ""
	profile_counter += 1
	_on_home_button_pressed()
	print("Profile created: ", profile_name_text)

# Called when the "Browse..." button for custom backgrounds is pressed.
func _on_browser_button_pressed():
	if profile_name.text.strip_edges().is_empty():
		_show_add_menu_error("Please enter a profile name first!")
		return
	_hide_add_menu_error()
	filedialog.popup_centered()

# Called when the user selects a file in the FileDialog.
func _on_file_selected(path: String):
	# --- Read the selected image file ---
	var original_file = FileAccess.open(path, FileAccess.READ)
	if not original_file:
		printerr("Error: Cannot read selected file: ", path)
		_show_add_menu_error("Could not read selected image file.")
		return
	var file_content = original_file.get_buffer(original_file.get_length())
	original_file.close()

	# --- Prepare a unique filename for saving ---
	var base_name = profile_name.text.strip_edges().replace(" ", "_").validate_filename()
	if base_name.is_empty(): base_name = "untitled_profile"
	var extension = path.get_extension().to_lower()
	# Ensure only allowed extensions are used (redundant check maybe)
	if not extension in ["png", "jpg", "webp"]:
		printerr("Invalid file extension selected: ", extension)
		_show_add_menu_error("Invalid file type. Please use PNG, JPG, or WEBP.")
		return
	var unique_suffix = str(Time.get_unix_time_from_system())
	var new_file_name = "%s_%s.%s" % [base_name, unique_suffix, extension]

	# --- Save the image to the user://UserBackground/ directory ---
	var destination_path = CUSTOM_BG_DIR.path_join(new_file_name)
	# Ensure the destination directory exists (should already from _ready).
	#DirAccess.make_dir_recursive_absolute(CUSTOM_BG_DIR)
	var destination_file = FileAccess.open(destination_path, FileAccess.WRITE)
	if not destination_file:
		printerr("Error: Cannot create or write to destination file: ", destination_path)
		_show_add_menu_error("Could not save custom background image.")
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
	else:
		printerr("Error: Failed to load copied image for preview: ", destination_path)
		_show_add_menu_error("Failed to load saved custom image.")
		_current_custom_bg_path = "" # Clear path on failure

# Updates the text preview as the user types.
func update_profile_name_preview(user_input: String):
	profile_name_preview.text = user_input

# Called when one of the standard background buttons is pressed.
func on_button_pressed(i: int):
	if i == -1: # Handle case where image didn't load
		printerr("Selected background button corresponds to a missing image.")
		_show_add_menu_error("Selected background is unavailable.")
		return
	if i >= 0 and i < background_images.size():
		preview_background.texture = background_images[i]
		_current_custom_bg_path = "" # Clear custom path
		_hide_add_menu_error()
	else:
		printerr("Invalid background button index pressed: ", i)

# Hides the error label in the Add menu when the user starts typing.
func _on_profile_name_text_changed(new_text: String):
	if add_menu_error_label and add_menu_error_label.visible:
		add_menu_error_label.visible = false

# Helper to show an error message in the Add menu.
func _show_add_menu_error(message: String):
	if add_menu_error_label:
		add_menu_error_label.text = message
		add_menu_error_label.visible = true
	printerr("Add Menu Error: ", message) # Also log it

# Helper to hide the error message in the Add menu.
func _hide_add_menu_error():
	if add_menu_error_label: add_menu_error_label.visible = false


### --- Profile Button Handlers --- ###

# Core logic called when a profile button's state changes (start/stop).
func _on_profile_client_toggled(profile_button, is_starting: bool):
	if not profile_button: printerr("_on_profile_client_toggled called with null button."); return

	if is_starting:
		_handle_profile_start(profile_button)
	else:
		_handle_profile_stop(profile_button)

# Handles the sequence when a profile is started.
func _handle_profile_start(profile_button):
	# Prevent starting if another profile is already running.
	if active_profile_button != null and active_profile_button != profile_button:
		printerr("Warning: Another profile is already active ('%s'). Cannot start '%s'" %
			[active_profile_button.name, profile_button.name])
		# Maybe provide user feedback here?
		return
	
	print("Starting profile: ", profile_button.name)
	active_profile_button = profile_button
	_update_progress_bar(active_profile_button, 0, true)

	# Disable other profile buttons.
	for child in profiles_grid.get_children():
		if child is Control and child.has_method("set_interactable"):
			child.set_interactable(child == active_profile_button)

	# --- Restore Saved Settings or Delete Existing --- #
	var profile_name_text = profile_button.name
	var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
	var local_app_data = OS.get_environment("LOCALAPPDATA")
	var settings_operation_success = false

	if not sanitized_profile_name.is_empty() and not local_app_data.is_empty():
		var profile_settings_dir = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
		var profile_settings_path = profile_settings_dir.path_join("RiotGamesPrivateSettings.yaml")
		var riot_client_data_path = local_app_data.path_join("Riot Games/Riot Client/Data")
		var riot_client_settings_path = riot_client_data_path.path_join("RiotGamesPrivateSettings.yaml")

		if FileAccess.file_exists(profile_settings_path):
			print("Restoring saved settings for profile '", profile_name_text, "'...")
			var dir_err = DirAccess.make_dir_recursive_absolute(riot_client_data_path)
			if dir_err == OK:
				var copy_err = DirAccess.copy_absolute(profile_settings_path, riot_client_settings_path)
				if copy_err == OK: settings_operation_success = true
				else: printerr("Failed to restore settings. Error: ", copy_err)
			else: printerr("Failed to ensure Riot Client data directory exists: ", riot_client_data_path)
		else:
			print("No saved settings found for '", profile_name_text, "'. Deleting existing if present...")
			if FileAccess.file_exists(riot_client_settings_path):
				var del_err = DirAccess.remove_absolute(riot_client_settings_path)
				if del_err == OK: settings_operation_success = true
				else: printerr("Failed to delete existing settings. Error: ", del_err)
			else:
				print("No existing settings file to delete.")
				settings_operation_success = true # Considered success if nothing needed deleting
	else:
		if sanitized_profile_name.is_empty(): printerr("Cannot handle settings: Invalid profile name.")
		if local_app_data.is_empty(): printerr("Cannot handle settings: LOCALAPPDATA not found.")

	_update_progress_bar(active_profile_button, 45, true)

	# --- Verify Setup Before Launch --- #
	if not settings_operation_success:
		printerr("Launch cancelled: Settings operation failed or was skipped.")
		_reset_profile_start_failure()
		return
	if riot_client_location.is_empty():
		printerr("Launch cancelled: Riot Client Location is not set.")
		_reset_profile_start_failure()
		return
	var executable_path = riot_client_location.path_join("RiotClientServices.exe")
	if not FileAccess.file_exists(executable_path):
		printerr("Launch cancelled: Riot Client executable not found at: ", executable_path)
		_reset_profile_start_failure()
		return

	_update_progress_bar(active_profile_button, 75, true)

	# --- Launch the Riot Client Process --- #
	print("Attempting to launch Riot Client...")
	var arguments = ["--launch-product=league_of_legends", "--launch-patchline=live"]
	var pid = OS.create_process(executable_path, arguments)

	if pid < 0:
		printerr("Failed to create Riot Client process. Path: %s" % executable_path)
		_reset_profile_start_failure()
	else:
		print("Riot Client process created successfully (PID: %d) for profile: %s" % [pid, profile_button.name])
		_update_progress_bar(active_profile_button, 100, false)

# Handles the sequence when a profile is stopped.
func _handle_profile_stop(profile_button):
	print("Stop signal received for profile: ", profile_button.name)
	_update_progress_bar(profile_button, 0, true)

	# --- Save Current Riot Client Settings to Profile Folder --- #
	var profile_name_text = profile_button.name
	var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
	var local_app_data = OS.get_environment("LOCALAPPDATA")

	if not sanitized_profile_name.is_empty() and not local_app_data.is_empty():
		var profile_settings_dir = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
		var profile_settings_path = profile_settings_dir.path_join("RiotGamesPrivateSettings.yaml")
		var riot_client_settings_path = local_app_data.path_join("Riot Games/Riot Client/Data/RiotGamesPrivateSettings.yaml")

		print("Attempting to save current Riot Client settings for profile '", profile_name_text, "'...")

		if not FileAccess.file_exists(riot_client_settings_path):
			printerr("Source Riot Client settings file not found, cannot save settings: ", riot_client_settings_path)
		else:
			var dir_err = DirAccess.make_dir_recursive_absolute(profile_settings_dir)
			if dir_err == OK:
				var copy_err = DirAccess.copy_absolute(riot_client_settings_path, profile_settings_path)
				if copy_err == OK: print("Successfully saved Riot Client settings to profile folder.")
				else: printerr("Failed to save Riot Client settings. Error: ", copy_err)
			else: printerr("Failed to ensure profile destination directory exists: ", profile_settings_dir)
	else:
		if sanitized_profile_name.is_empty(): printerr("Cannot save settings: Invalid profile name.")
		if local_app_data.is_empty(): printerr("Cannot save settings: LOCALAPPDATA not found.")

	_update_progress_bar(profile_button, 50, true)

	# --- Re-enable Buttons --- #
	if active_profile_button == profile_button:
		active_profile_button = null # Clear active button tracker.
	# Re-enable all profile buttons regardless (in case state got weird).
	for child in profiles_grid.get_children():
		if child is Control and child.has_method("set_interactable"):
			child.set_interactable(true)

	_update_progress_bar(profile_button, 100, false)

	# Note: Killing Riot/LoL processes is handled by profile_button.gd

# Handles deleting a profile when requested by its button.
func _on_profile_delete_requested(profile_node):
	if not is_instance_valid(profile_node): return # Node already gone?
	var profile_name_to_delete = profile_node.name
	print("Handling delete request for profile: ", profile_name_to_delete)

	# --- Step 1: Modify JSON Data --- #
	var data = _load_json_data(PROFILES_PATH)
	var custom_bg_path_to_delete = ""
	var profile_found_in_json = false
	if data and data.has("profiles") and data["profiles"] is Array:
		var profiles_array = data["profiles"]
		for i in range(profiles_array.size() - 1, -1, -1):
			var profile_entry = profiles_array[i]
			if profile_entry is Dictionary and profile_entry.get("profile_name") == profile_name_to_delete:
				var bg_path = profile_entry.get("custom_background_image", "")
				if bg_path.begins_with(CUSTOM_BG_DIR):
					custom_bg_path_to_delete = bg_path
				profiles_array.remove_at(i)
				profile_found_in_json = true
				print("Removed profile entry from JSON data.")
				break
		if profile_found_in_json:
			if not _save_json_data(PROFILES_PATH, data):
				printerr("Failed to save JSON after removing profile entry!")
				# Decide how to proceed - maybe don't delete files/node?
		else:
			printerr("Profile '%s' not found in JSON data for deletion." % profile_name_to_delete)
	else:
		printerr("Could not load or parse JSON data for deletion.")

	# --- Step 2: Delete Profile Directory --- #
	var sanitized_profile_name = profile_name_to_delete.validate_filename().replace(" ", "_")
	if not sanitized_profile_name.is_empty():
		var profile_dir_path = PROFILE_DIR_BASE.path_join(sanitized_profile_name)
		if DirAccess.dir_exists_absolute(profile_dir_path):
			var remove_err = _remove_dir_recursive(profile_dir_path)
			if remove_err != OK:
				printerr("Failed to recursively delete profile directory: ", profile_dir_path)
			else:
				print("Successfully deleted profile directory: ", profile_dir_path)
		else:
			print("Profile directory not found for deletion: ", profile_dir_path)
	else:
		printerr("Cannot delete profile directory: Invalid sanitized name for '%s'" % profile_name_to_delete)

	# --- Step 3: Delete Custom Background Image --- #
	if not custom_bg_path_to_delete.is_empty():
		if FileAccess.file_exists(custom_bg_path_to_delete):
			var remove_err = DirAccess.remove_absolute(custom_bg_path_to_delete)
			if remove_err == OK:
				print("Successfully deleted custom background image: ", custom_bg_path_to_delete)
			else:
				printerr("Failed to delete custom background image: ", custom_bg_path_to_delete)
		else:
			print("Custom background image not found for deletion: ", custom_bg_path_to_delete)

	# --- Step 4: Update Active Profile State --- #
	if active_profile_button == profile_node:
		print("Deleted profile was active. Resetting state.")
		active_profile_button = null
		# Ensure other buttons are interactable
		for child in profiles_grid.get_children():
			if child != profile_node and child is Control and child.has_method("set_interactable"):
				child.set_interactable(true)

	# --- Step 5: Remove Node from Scene --- #
	print("Removing profile button node from scene.")
	profile_node.queue_free()

	# --- Step 6: Update Counter --- #
	profile_counter = max(0, profile_counter - 1)
	print("Profile count updated to: ", profile_counter)


### --- Warning Popup Handlers --- ###
func _on_closewarning_pressed():
	print("Closing warning popup and saving state.")
	if warning_main:
		warning_main.visible = false
	_save_warning_config_state(true)

# Reads configs.json, updates the 'warning_shown' flag, and saves it back.
func _save_warning_config_state(was_shown: bool):
	var config_data = _load_json_data(CONFIG_PATH)
	if not config_data: config_data = {}
	config_data["warning_shown"] = was_shown
	if not _save_json_data(CONFIG_PATH, config_data):
		printerr("Failed to save warning state to configs.json")
	else:
		print("Updated configs.json with warning_shown = ", was_shown)


### --- Boot Screen Handlers --- ###
func _on_boot_client_location_saved():
	print("Client location saved signal received. Hiding boot screen.")
	if boot_screen: boot_screen.visible = false
	# Need to reload the location variable now that it's saved
	load_configs()


### --- Helper & Utility Functions --- ###

# Instantiates and adds a profile button based on profile data.
func _create_profile_button(profile_data: Dictionary):
	var new_profile = ADD_PROFILE_BUTTON_SCENE.instantiate()
	var profile_name_text = profile_data.get("profile_name", "Unknown Profile")
	new_profile.name = profile_name_text

	var profile_label = new_profile.find_child("profile_name", true, false)
	if profile_label: profile_label.text = profile_name_text

	var texture_rect = new_profile.get_node_or_null("bg1/Panel/profile_bg")
	if texture_rect:
		var image_path = profile_data.get("custom_background_image", "")
		var profile_texture = load_texture_from_path(image_path)
		if profile_texture:
			texture_rect.texture = profile_texture
		else:
			texture_rect.texture = load(DEFAULT_BG_PATH) # Use default

	var initial_progress_bar = new_profile.get_node_or_null("bg1/Panel/ProgressBar")
	if initial_progress_bar:
		initial_progress_bar.visible = false
		initial_progress_bar.value = 0

	# Connect signals (ensure the button script has these signals)
	if new_profile.has_signal("client_toggled"):
		new_profile.client_toggled.connect(_on_profile_client_toggled)
	else: printerr("Profile button scene missing 'client_toggled' signal.")
	if new_profile.has_signal("delete_requested"):
		new_profile.delete_requested.connect(_on_profile_delete_requested)
	else: printerr("Profile button scene missing 'delete_requested' signal.")

	profiles_grid.add_child(new_profile)
	#print("Created button for profile: ", profile_name_text) # Reduced print

# Loads a texture safely from res:// or user:// paths.
func load_texture_from_path(path: String) -> Texture2D:
	if path.is_empty(): return null # Don't print error for empty path, might be intentional
	if path.begins_with("res://"):
		if ResourceLoader.exists(path): return load(path)
		else: printerr("Resource texture path does not exist: ", path); return null
	elif path.begins_with("user://"):
		if FileAccess.file_exists(path):
			var img = Image.load_from_file(path)
			if img: return ImageTexture.create_from_image(img)
			else: printerr("Failed to load image from user path: ", path); return null
		else: printerr("User texture path does not exist: ", path); return null
	else:
		printerr("Invalid or unsupported texture path prefix: ", path)
		return null

# Handles switching between Home, Settings, and Add Profile views.
func update_selected_panel(selected_panel: Control, button_panel: Control):
	# Hide all main panels and selection indicators first.
	home_selected_panel.visible = false
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	settings_menu.visible = false
	add_menu.visible = false
	# Reset icon colors.
	settings_icon.modulate = Color(1, 1, 1, 1)
	home_icon.modulate = Color(1, 1, 1, 1)
	add_icon.modulate = Color(1, 1, 1, 1)

	# Show the requested panel and move the highlight.
	selected_panel.visible = true
	move_icon_highlight(button_panel.position.y)

	# Show the specific content view if needed.
	if selected_panel == settings_selected_panel: settings_menu.visible = true
	if selected_panel == add_selected_panel: add_menu.visible = true

# Animates the highlight bar on the left menu.
func move_icon_highlight(target_y: float):
	var tween = create_tween().set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(icon_highlight, "position:y", target_y + 9, 0.1)

# Updates the progress bar on a specific profile button node.
func _update_progress_bar(profile_node, value: float, visible: bool):
	if not is_instance_valid(profile_node): return
	var progress_bar = profile_node.get_node_or_null("bg1/Panel/ProgressBar")
	if progress_bar is ProgressBar:
		progress_bar.value = value
		progress_bar.visible = visible

# Resets UI state after a profile start attempt fails.
func _reset_profile_start_failure():
	if active_profile_button:
		_update_progress_bar(active_profile_button, 0, false)
		active_profile_button = null
	# Re-enable all buttons
	for child in profiles_grid.get_children():
		if child is Control and child.has_method("set_interactable"):
			child.set_interactable(true)

# Utility to load and parse JSON data from a file.
# Returns the parsed data (usually a Dictionary) or null on error.
func _load_json_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		printerr("JSON file not found at: ", path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("Could not open JSON file: ", path)
		return null
	var json_string = file.get_as_text()
	file.close()
	var json_parser = JSON.new()
	var error = json_parser.parse(json_string)
	if error != OK:
		printerr("Error parsing JSON (code: %s) in %s: %s at line %s" %
			[error, path.get_file(), json_parser.get_error_message(), json_parser.get_error_line()])
		return null
	return json_parser.get_data()

# Utility to save data to a JSON file.
# Returns true on success, false on failure.
func _save_json_data(path: String, data: Variant) -> bool:
	var json_string = JSON.stringify(data, "\t")
	var save_file = FileAccess.open(path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(json_string)
		save_file.close()
		#print("JSON data saved successfully to: ", path) # Reduced print
		return true
	else:
		printerr("Error saving JSON data to: ", path)
		return false

# Utility to append a value to an array within a JSON file.
# Assumes the root of the JSON is a Dictionary.
# Returns true on success, false on failure.
func _append_to_json_array(path: String, array_key: String, new_value) -> bool:
	var data = _load_json_data(path)
	if data == null: data = {} # Start fresh if load failed or file empty
	if not data is Dictionary: 
		printerr("Cannot append to JSON array: Root is not a Dictionary in ", path)
		return false
	if not data.has(array_key) or not data[array_key] is Array:
		data[array_key] = [] # Create the array if it doesn't exist
	data[array_key].append(new_value)
	return _save_json_data(path, data)

# Recursively removes a directory and all its contents.
func _remove_dir_recursive(path: String) -> Error:
	var dir = DirAccess.open(path)
	if not dir:
		if not DirAccess.dir_exists_absolute(path): return OK # Already gone
		printerr("Recursive remove: Could not open directory: ", path)
		return DirAccess.get_open_error()

	var current_item = dir.get_next()
	while current_item != "":
		if current_item == "." or current_item == "..":
			current_item = dir.get_next()
			continue

		var item_path = path.path_join(current_item)
		var error: Error = OK

		if dir.current_is_dir():
			error = _remove_dir_recursive(item_path)
		else:
			error = DirAccess.remove_absolute(item_path)
			# Add a tiny delay after removing a file, just in case
			if error == OK:
				OS.delay_msec(10) 
			else:
				printerr("Recursive remove: Failed to remove file ", item_path, ". Error: ", error)


		if error != OK:
			printerr("Recursive remove: Error processing item ", item_path, ". Error: ", error)
			# Ensure handle is released before returning error
			# dir.close() # dir.close() is not needed in Godot 3/4 for DirAccess.open
			return error # Return immediately on error

		current_item = dir.get_next()

	# Ensure handle is released before attempting final remove
	# dir.close() # dir.close() is not needed in Godot 3/4 for DirAccess.open
	dir = null # Allow garbage collection

	# --- Add Delay and Retry for final directory removal ---
	var max_retries = 3
	var retry_delay_ms = 100 # Wait 100ms between retries
	var final_remove_err: Error = FAILED # Initialize with a failure code

	for i in range(max_retries):
		# Wait before attempting/retrying the final removal (except first attempt)
		if i > 0:
			print("Recursive remove: Retrying final directory removal for ", path, " (Attempt ", i + 1, ")")
			OS.delay_msec(retry_delay_ms)

		final_remove_err = DirAccess.remove_absolute(path)

		if final_remove_err == OK:
			# Successfully removed
			break 
		elif not DirAccess.dir_exists_absolute(path):
			# It somehow got removed between the check and the attempt, or doesn't exist
			final_remove_err = OK 
			break
		else:
			# Log the error for this attempt
			printerr("Recursive remove: Attempt ", i + 1, " failed to remove final directory: ", path, ". Error: ", final_remove_err)

	# --- End of Retry Logic ---

	if final_remove_err != OK:
		printerr("Recursive remove: Failed to remove final directory after ", max_retries, " attempts: ", path, ". Final Error: ", final_remove_err)
		return final_remove_err

	#print("Recursive remove: Successfully removed directory: ", path) # Reduced print
	return OK
