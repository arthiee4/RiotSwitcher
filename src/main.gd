extends Control

### --- Node References --- ###
# Grab references to the UI elements we'll need to interact with.

# Info Menu Side
@onready var infomenu_side = $infomenu_side
@onready var infomenu_side_anim = $infomenu_side/infomenu_side_anim

# Content Side (Where profile buttons go)
@onready var profiles_grid = $contet_side/GridContainer
const add_profile_button = preload("res://scenes/components/profile_button.tscn") # The template scene for profile buttons

# Left Menu Side Buttons & Panels
@onready var add_prof_button = $leftmenu_side/add_prof_button/Button
@onready var add_prof_button_panel = $leftmenu_side/add_prof_button
@onready var add_icon = $leftmenu_side/add_prof_button/Button/TextureRect

@onready var home_button = $leftmenu_side/home_button/Button
@onready var home_button_panel = $leftmenu_side/home_button
@onready var home_icon = $leftmenu_side/home_button/Button/TextureRect

@onready var settings_button = $leftmenu_side/settings_button/Button
@onready var settings_button_panel = $leftmenu_side/settings_button
@onready var settings_icon = $leftmenu_side/settings_button/Button/TextureRect

# Left Menu Highlight Effect
@onready var icon_highlight = $leftmenu_side/iconhighlight
@onready var glow_color = $leftmenu_side/iconhighlight/glow
@onready var glow_panel_color = $leftmenu_side/iconhighlight/Panel

# Selected Panels (visual indicators for active menu item)
@onready var home_selected_panel = $leftmenu_side/home_button/selected_panel
@onready var settings_selected_panel = $leftmenu_side/settings_button/selected_panel
@onready var add_selected_panel = $leftmenu_side/add_prof_button/selected_panel

# Main Content Views
@onready var settings_menu = $settings_menu
@onready var add_menu = $add_menu

# Add Menu Specifics
@onready var backgrounds = $add_menu/bg_select/backgrounds
@onready var preview_background = $add_menu/preview/bgexample3/preview_bg # Shows the selected background
var background_images = [] # We'll load the standard background images into here

# Background Selection Buttons
# (References bgexample1 to bgexample12)
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

# Custom Image Upload
@onready var browser_button = $add_menu/upload_custom_bg/browser_button # Button to open file dialog
@onready var filedialog = $add_menu/creation/create_button/FileDialog # The actual file dialog

# Profile Name Input/Preview (Add Menu)
@onready var profile_name = $add_menu/profile_name/LineEdit # Where the user types the new profile name
@onready var profile_name_preview = $add_menu/preview/preview_profile_name # Shows the name live on the preview

# Create Button (Add Menu)
@onready var create_button = $add_menu/creation/create_button

# Settings Error Label
@onready var settings_error = $add_menu/error/Label # For showing validation errors in the Add menu


### --- Conditions --- ###
# Simple state flags
var profile_selected = false # Might be useful later? Currently unused.
var info_side_visible = false # Controls the info side panel visibility, also seems unused for now.

### --- Active Profile Tracking --- ###
var active_profile_button = null # Stores a reference to the currently running profile button, if any.

### --- Profile State Variables --- ###
var _current_custom_bg_path: String = "" # Temporarily holds the path if a user uploads a custom background.
var riot_client_location: String = "" # Stores the path to the Riot Client install, loaded from configs.json.

### --- Profile Counter --- ###
var profile_counter: int = 0 # Tracks the number of profiles, used for... well, counting profiles.


### --- Initialization --- ###
func _ready():
	# Make sure the directory for custom backgrounds exists when the app starts.
	DirAccess.make_dir_recursive_absolute("user://UserBackground/")
	# Load up essential data and set up the UI.
	load_configs()
	load_background_images()
	connect_signals()
	initialize_ui()
	load_profiles() # Load existing profiles from JSON
	load_profile_counter() # Get the current profile count
	# Make the error label disappear when the user starts typing a profile name.
	profile_name.text_changed.connect(_on_profile_name_text_changed)

### --- Config Loading --- ###
# Reads settings like the Riot Client path from configs.json.
func load_configs():
	var config_path = "res://Data/configs.json"
	if not FileAccess.file_exists(config_path):
		printerr("Config file not found at: ", config_path) # Uh oh, can't find the config file.
		return
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		printerr("Could not open config file: ", config_path) # Something went wrong opening the file.
		return
	var json_string = file.get_as_text()
	file.close()
	var json_parser = JSON.new()
	var error = json_parser.parse(json_string)
	if error != OK:
		# Log details if the JSON is malformed.
		printerr("Error parsing config JSON (code: %s): %s at line %s" % [error, json_parser.get_error_message(), json_parser.get_error_line()])
		return
	var data = json_parser.get_data()
	if not data is Dictionary:
		printerr("Invalid config JSON format. Root should be a dictionary.") # The JSON structure is wrong.
		return

	# Try to get the Riot Client location.
	if data.has("RiotClientLocation"):
		riot_client_location = data["RiotClientLocation"]
		print("Riot Client Location loaded: ", riot_client_location)
		if riot_client_location.is_empty():
			# This isn't fatal, but the user won't be able to launch the client.
			printerr("Warning: RiotClientLocation in configs.json is empty.") 
	else:
		# Also not fatal, but good to warn about.
		printerr("Warning: RiotClientLocation key not found in configs.json") 

# Figures out how many profiles we already have saved.
func load_profile_counter():
	var json_path = "res://Data/profiles_data.json"
	var json = FileAccess.open(json_path, FileAccess.READ)
	if not json:
		printerr("Error: Could not open profiles_data.json for counting.")
		return
	var json_string = json.get_as_text()
	json.close()
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		printerr("Error interpreting profile JSON for counting.")
		return
	var data = json_parser.get_data()
	# Make sure we have a valid dictionary and a "profiles" array.
	if data is Dictionary and data.has("profiles") and data["profiles"] is Array:
		profile_counter = data["profiles"].size() # Set counter based on the number of existing profiles
	else:
		profile_counter = 0 # If no profiles exist, start from zero

# Loads all saved profile data and creates the buttons in the grid.
func load_profiles():
	var json_path = "res://Data/profiles_data.json"
	var json = FileAccess.open(json_path, FileAccess.READ)
	if not json:
		printerr("Error: Could not load profiles from ", json_path)
		return
	var json_string = json.get_as_text()
	json.close()
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		printerr("Error interpreting profile JSON: ", json_parser.get_error_message())
		return
	var data = json_parser.get_data()
	# Check if the JSON structure is what we expect.
	if not data is Dictionary or not data.has("profiles") or not data["profiles"] is Array:
		print("No profiles found or invalid JSON format in profiles_data.json.") 
		return
	
	# Clear out any old profile buttons first to avoid duplicates if this is called multiple times.
	for child in profiles_grid.get_children():
		child.queue_free()
		
	# Go through each profile entry in the JSON data.
	for profile_data in data["profiles"]:
		if profile_data is Dictionary:
			# Create a new button instance from our template scene.
			var new_profile = add_profile_button.instantiate()
			var profile_name_text = profile_data.get("profile_name", "Unknown Profile") # Get name, or use default.
			new_profile.name = profile_name_text # Set the node's name (useful for finding it later).
			
			# Find the label inside the button scene and set its text.
			var profile_label = new_profile.find_child("profile_name", true, false)
			if profile_label: profile_label.text = profile_name_text
			
			# Find the background image node and set its texture.
			var texture_rect = new_profile.get_node_or_null("bg1/Panel/profile_bg")
			if texture_rect:
				var image_path = profile_data.get("custom_background_image", "")
				var profile_texture = load_texture_from_path(image_path) # This helper handles res:// and user:// paths.
				if profile_texture:
					texture_rect.texture = profile_texture
				else: # load_texture_from_path logs the specific error
					texture_rect.texture = preload("res://default_profile_image.png") # Use a fallback if loading failed.

			# Make sure the progress bar starts hidden.
			var initial_progress_bar = new_profile.get_node_or_null("bg1/Panel/ProgressBar")
			if initial_progress_bar:
				initial_progress_bar.visible = false
				initial_progress_bar.value = 0

			# Connect the button's main signal to our handler function.
			new_profile.client_toggled.connect(_on_profile_client_toggled)
			new_profile.delete_requested.connect(_on_profile_delete_requested)

			# Add the fully configured button to the display grid.
			profiles_grid.add_child(new_profile) 
			print("Profile loaded: ", profile_name_text) 

# Utility to add new data (like a profile) to a JSON file.
func modify_config_json(path: String, key_path: Array, new_value) -> void:
	# Read the existing JSON.
	var json = FileAccess.open(path, FileAccess.READ)
	if not json:
		printerr("Error: JSON file not found or cannot be opened: ", path)
		return
	var json_string = json.get_as_text()
	json.close()
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		printerr("Error parsing JSON in ", path, ": ", json_parser.get_error_message())
		return
	var data = json_parser.get_data()
	# Make sure we have a base dictionary and the "profiles" array exists.
	if not (data is Dictionary): data = {"profiles": []} # If JSON was empty or not a dict, start fresh.
	if not data.has("profiles") or not (data["profiles"] is Array): data["profiles"] = []
	
	# Currently, we only expect to add to the "profiles" array.
	if key_path.size() == 1 and key_path[0] == "profiles":
		data["profiles"].append(new_value) # Add the new profile data.
	else:
		printerr("modify_config_json called with unexpected key_path:", key_path) # Should not happen with current usage.
		return

	# Write the modified data back to the file.
	var modified_json_string = JSON.stringify(data, "\t") # Use tabs for readability.
	var save_file = FileAccess.open(path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(modified_json_string)
		save_file.close()
		print("JSON modified and saved successfully at: ", path)
	else:
		printerr("Error saving JSON at: ", path) # Problem writing the file.

				
### --- Background Image Loading --- ###
# Loads the default background images and connects their buttons.
func load_background_images():
	for i in range(1, 13): # Assuming 12 background images named 1.png, 2.png, etc.
		var image_path = "res://assets/backgrounds/profiles_bg/{0}.png".format([i])
		# Check if the image file actually exists before trying to load it.
		if ResourceLoader.exists(image_path):
			background_images.append(load(image_path)) # Add the loaded texture to our array.
		else:
			printerr("Background image not found: ", image_path) # Warn if an image is missing.
			
		# Find the corresponding button in the scene.
		var button_path = "add_menu/bg_select/backgrounds/bgexample{0}/Button".format([i])
		var button = get_node_or_null(button_path) # Safer way to get node.
		if button:
			# Connect the button's pressed signal to our handler, passing the index.
			button.pressed.connect(on_button_pressed.bind(i - 1)) # Use i-1 because arrays are 0-indexed.
		else:
			printerr("Background button node not found: ", button_path) # Warn if a button node is missing.
			

### --- Signal Connections --- ###
# Connects signals for various UI elements.
func connect_signals():
	profile_name.text_changed.connect(update_profile_name_preview) # Update preview as user types.
	filedialog.filters = ["*.png, *.jpg ; PNG and JPG Files"] # Set allowed file types.
	filedialog.file_selected.connect(_on_file_selected) # Handle file selection.
	browser_button.pressed.connect(_on_browser_button_pressed) # Open file dialog.
	create_button.pressed.connect(_on_create_button_pressed) # Create the new profile.
	add_prof_button.pressed.connect(_on_add_prof_button_pressed) # Switch to the add profile view.
	# Home and Settings buttons are likely connected in the editor, but could be connected here too.

### --- UI Initialization --- ###
# Sets the initial visual state of the UI.
func initialize_ui():
	# Set initial colors and visibility for menu highlights/panels.
	glow_color.color = Color(1, 0, 0, 0.1) # Home color initially
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	home_selected_panel.visible = true # Start on the home screen.
	move_icon_highlight(home_button_panel.position.y) # Position the highlight over the home button.
	# Make sure the error label in the add menu is hidden at start.
	if settings_error: settings_error.visible = false
	else: printerr("Error Label node not found at path: $error/Label") # Check if node path is correct.

### --- Profile Creation --- ###
# Called when the "Create" button in the Add menu is pressed.
func _on_create_button_pressed():
	# Get the entered name and the selected background texture.
	var profile_name_text = profile_name.text.strip_edges() # Remove leading/trailing whitespace.
	var background_texture = preview_background.texture 
	
	# --- Input Validation ---
	if profile_name_text.is_empty():
		printerr("Error: Profile name cannot be empty.")
		if settings_error: # Show visual error if possible.
			settings_error.text = "Profile name cannot be empty!"
			settings_error.visible = true
		return # Stop creation process.
	if not background_texture:
		printerr("Error: Select or upload a background image.")
		if settings_error: # Show visual error.
			settings_error.text = "Please select or upload a background image!"
			settings_error.visible = true
		return # Stop creation process.

	# --- Create Profile Directory ---
	# Make the profile name safe for use as a directory name.
	var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
	if sanitized_profile_name.is_empty(): # If name becomes empty after sanitizing...
		sanitized_profile_name = "profile_" + str(Time.get_unix_time_from_system()) # Create a unique fallback name.
		printerr("Invalid profile name for directory, using fallback: ", sanitized_profile_name)
		
	# Create the directory under user://profiles/	
	var profile_dir_path = "user://profiles/" + sanitized_profile_name 
	var err = DirAccess.make_dir_recursive_absolute(profile_dir_path) # Creates parent folders if needed.
	if err == OK:
		print("Profile directory created in user data: ", profile_dir_path)
	else:
		printerr("Failed to create profile directory for ", profile_name_text, " at ", profile_dir_path, ". Error: ", err)
		# Might want to stop here if directory creation fails, but currently continues.

	# --- Determine Background Path to Save ---
	var background_path_to_save: String
	if not _current_custom_bg_path.is_empty():
		# User uploaded a custom image, use its (user://) path.
		background_path_to_save = _current_custom_bg_path
	elif background_texture and background_texture.resource_path and background_texture.resource_path.begins_with("res://"):
		# User selected a standard (res://) background.
		background_path_to_save = background_texture.resource_path
	else:
		# Fallback if something went wrong determining the path.
		printerr("Warning: Could not determine standard background path. Using default.") 
		background_path_to_save = "res://default_profile_image.png"

	# --- Create and Configure UI Button ---
	var new_profile_instance = add_profile_button.instantiate() # Create from template.
	new_profile_instance.name = profile_name_text # Set node name.
	new_profile_instance.visible = true 
	new_profile_instance.client_toggled.connect(_on_profile_client_toggled) # Connect signal.
	new_profile_instance.delete_requested.connect(_on_profile_delete_requested)
	profiles_grid.add_child(new_profile_instance) # Add to the display grid.

	# Set the text label inside the new button.
	var profile_label = new_profile_instance.find_child("profile_name", true, false)
	if profile_label: profile_label.text = profile_name_text
	# Set the background texture inside the new button.
	var texture_rect = new_profile_instance.get_node_or_null("bg1/Panel/profile_bg")
	if texture_rect:
		var final_texture = load_texture_from_path(background_path_to_save) # Use helper to load.
		if final_texture: texture_rect.texture = final_texture
		else: # If loading fails...
			printerr("Failed setting final texture for profile button: ", profile_name_text)
			texture_rect.texture = preload("res://default_profile_image.png") # Use fallback texture.

	# --- Prepare and Save Data to JSON ---
	var new_profile_data = {
		"profile_name": profile_name_text,
		"custom_background_image": background_path_to_save, # Save the path we determined.
		"first_time_opened": false # New profiles haven't been opened yet.
	}
	# Append this new profile's data to the profiles_data.json file.
	modify_config_json("res://Data/profiles_data.json", ["profiles"], new_profile_data)

	# --- Cleanup and Navigate --- 
	profile_name.text = "" # Clear the input field.
	preview_background.texture = null # Clear the preview image.
	profile_name_preview.text = "" # Clear the preview text.
	_current_custom_bg_path = "" # Clear the temporary custom path.
	profile_counter += 1 # Increment our counter.
	_on_home_button_pressed() # Switch back to the main profile view.
	print("Profile created: ", profile_name_text) 

### --- File Dialog Handling --- ###
# Called when the "Browse..." button for custom backgrounds is pressed.
func _on_browser_button_pressed():
	# Make sure the user has entered a name first, needed for saving the image later.
	if profile_name.text.strip_edges().is_empty():
		if settings_error: # Show the visual error message.
			settings_error.text = "Please enter a profile name first!" 
			settings_error.visible = true 
		else:
			printerr("Error Label node not found, cannot show error.") # Log if the error label is missing.
		return # Don't open the dialog.
		
	# If a name is present, make sure the error message is hidden.
	if settings_error: settings_error.visible = false 
	# Open the file dialog centered on the screen.
	filedialog.popup_centered()

# Called when the user selects a file in the FileDialog.
func _on_file_selected(path: String):
	# --- Read the selected image file ---
	var original_file = FileAccess.open(path, FileAccess.READ)
	if not original_file:
		printerr("Error: Cannot read selected file: ", path)
		return
	var file_content = original_file.get_buffer(original_file.get_length()) # Read the whole file into memory.
	original_file.close()

	# --- Prepare a unique filename for saving ---
	# Sanitize the profile name to use in the filename.
	var base_name = profile_name.text.strip_edges().replace(" ", "_").validate_filename()
	if base_name.is_empty(): base_name = "untitled_profile" # Provide a fallback.
	var extension = path.get_extension().to_lower() # Get the original extension (png, jpg).
	var unique_suffix = str(Time.get_unix_time_from_system()) # Add timestamp to avoid name collisions.
	var new_file_name = "%s_%s.%s" % [base_name, unique_suffix, extension] # Combine parts.
	
	# --- Save the image to the user://UserBackground/ directory --- 
	var destination_dir = "user://UserBackground/"
	var destination_path = destination_dir.path_join(new_file_name)
	# Ensure the destination directory exists.
	DirAccess.make_dir_recursive_absolute(destination_dir)
	# Open the destination file for writing.
	var destination_file = FileAccess.open(destination_path, FileAccess.WRITE)
	if not destination_file:
		printerr("Error: Cannot create or write to destination file: ", destination_path)
		return
	# Write the image data we read earlier.
	destination_file.store_buffer(file_content)
	destination_file.close()

	# --- Load the *copied* image for the preview --- 
	# We load the one we just saved to user:// to ensure it worked correctly.
	var img = Image.load_from_file(destination_path)
	if img:
		var texture = ImageTexture.create_from_image(img) # Create a texture from the Image object.
		preview_background.texture = texture # Display it in the preview area.
		_current_custom_bg_path = destination_path # Store this user:// path to be saved if profile is created.
		print("Custom image loaded and ready for use: ", destination_path) 
	else:
		# If loading the copied image failed, something went wrong.
		printerr("Error: Failed to load copied image for preview: ", destination_path) 
		_current_custom_bg_path = "" # Don't save this path.

### --- Profile Name Update --- ###
# Updates the text preview in the Add menu as the user types.
func update_profile_name_preview(user_input: String):
	profile_name_preview.text = user_input

# Called when one of the standard background buttons is pressed.
func on_button_pressed(i: int): # 'i' is the index passed via bind().
	# Check if the index is valid for our loaded background images array.
	if i >= 0 and i < background_images.size():
		preview_background.texture = background_images[i] # Set the preview texture.
		_current_custom_bg_path = "" # Clear any custom path, as a standard one is now selected.
	else:
		printerr("Invalid background button index pressed: ", i) # Should not happen unless button setup is wrong.

### --- Selected Panel Management --- ###
# Handles switching between Home, Settings, and Add Profile views.
func update_selected_panel(selected_panel: Control, button_panel: Control):
	# Hide all main panels and selection indicators first.
	home_selected_panel.visible = false
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	settings_menu.visible = false # Hide the settings content view.
	add_menu.visible = false # Hide the add profile content view.
	# Reset icon colors.
	settings_icon.modulate = Color(1, 1, 1, 1)
	home_icon.modulate = Color(1, 1, 1, 1)
	add_icon.modulate = Color(1, 1, 1, 1)
	
	# Show the requested panel and move the highlight.
	selected_panel.visible = true
	move_icon_highlight(button_panel.position.y) # Animate the highlight bar.
	
	# Show the specific content view if needed.
	if selected_panel == settings_selected_panel: settings_menu.visible = true
	if selected_panel == add_selected_panel: add_menu.visible = true

### --- Icon Highlight Movement --- ###
# Animates the little highlight bar on the left menu.
func move_icon_highlight(target_y: float):
	var tween = create_tween()
	# Animate the Y position smoothly. Added 9px offset based on original code, adjust if needed.
	tween.tween_property(icon_highlight, "position:y", target_y + 9, 0.1).set_ease(Tween.EASE_OUT_IN)

### --- Button Handlers (Left Menu) --- ###
# These functions handle clicks on the main left menu buttons.
func _on_home_button_pressed():
	update_selected_panel(home_selected_panel, home_button_panel) # Show home panel.
	# Set highlight colors for Home (Red theme).
	glow_color.color = Color(1, 0, 0, 0.1)
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	if styleboxss: styleboxss.bg_color = Color(1, 0, 0, 1) # Check if stylebox exists.
	home_icon.modulate = Color(1, 0, 0, 1)

func _on_settings_button_pressed():
	update_selected_panel(settings_selected_panel, settings_button_panel) # Show settings panel.
	# Set highlight colors for Settings (Orange theme). Use float division for colors.
	glow_color.color = Color(214/255.0, 129/255.0, 0, 0.5) 
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	if styleboxss: styleboxss.bg_color = Color(214/255.0, 129/255.0, 0, 1)
	settings_icon.modulate = Color(214/255.0, 129/255.0, 0, 1)
	
func _on_add_prof_button_pressed():
	update_selected_panel(add_selected_panel, add_prof_button_panel) # Show add profile panel.
	# Set highlight colors for Add (Blue theme).
	glow_color.color = Color(0, 0, 1, 0.5) # Adjusted alpha slightly for consistency.
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	if styleboxss: styleboxss.bg_color = Color(0, 0, 1, 1)
	add_icon.modulate = Color(0, 0, 1, 1)
	

### --- Profile State Management --- ###
# This is the core logic called when a profile button's state changes (start/stop).
func _on_profile_client_toggled(profile_button, is_starting: bool):
	if is_starting:
		# --- Starting a Profile ---
		
		# Prevent starting if another profile is already running.
		if active_profile_button != null and active_profile_button != profile_button:
			printerr("Warning: Another profile is already active.") 
			return # Don't proceed.
			
		# Set this button as active and show its progress bar.
		active_profile_button = profile_button
		_update_progress_bar(active_profile_button, 0, true) # Show bar at 0%
		
		# Disable all *other* profile buttons.
		for child in profiles_grid.get_children():
			if child is Control and child.has_method("set_interactable"):
				if child != active_profile_button: child.set_interactable(false)
				else: child.set_interactable(true) # Keep the active one enabled so it can be stopped.
		_update_progress_bar(active_profile_button, 15, true) # Update progress visually.

		# --- Restore Saved Settings or Delete Existing ---
		# This part handles the RiotGamesPrivateSettings.yaml file.
		var profile_name_text = profile_button.name
		var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
		var local_app_data = OS.get_environment("LOCALAPPDATA") # Get the AppData/Local path.
		var settings_operation_attempted = false # Flag to track if we tried the file operations.
		
		# We need both a valid profile name and the LOCALAPPDATA path to proceed.
		if not sanitized_profile_name.is_empty() and not local_app_data.is_empty():
			settings_operation_attempted = true # Mark that we are trying the operation.
			# Define paths for the saved settings (in user://) and the live settings (in AppData).
			var profile_settings_dir = "user://profiles/" + sanitized_profile_name
			var profile_settings_path = profile_settings_dir.path_join("RiotGamesPrivateSettings.yaml")
			var riot_client_data_path = local_app_data.path_join("Riot Games/Riot Client/Data")
			var riot_client_settings_path = riot_client_data_path.path_join("RiotGamesPrivateSettings.yaml")

			# Check if we have settings saved for this profile.
			if FileAccess.file_exists(profile_settings_path):
				# Yes, try to copy them over the current live settings.
				print("Found saved settings for profile '", profile_name_text, "'. Restoring...") 
				var dir_err = DirAccess.make_dir_recursive_absolute(riot_client_data_path) # Ensure Riot Client Data dir exists.
				if dir_err != OK: printerr("Failed to ensure Riot Client data directory exists: ", riot_client_data_path, ". Error: ", dir_err)
				else:
					# Copy from user://profiles/... to AppData/...
					var copy_err = DirAccess.copy_absolute(profile_settings_path, riot_client_settings_path) 
					if copy_err == OK: print("Settings restored successfully.")
					else: printerr("Failed to restore settings. Error: ", copy_err) # Log copy errors (permissions?).
			else:
				# No saved settings found, so let's delete the current live settings file if it exists.
				print("No saved settings found for '", profile_name_text, "'. Deleting existing...") 
				if FileAccess.file_exists(riot_client_settings_path):
					var del_err = DirAccess.remove_absolute(riot_client_settings_path) # Delete the file in AppData.
					if del_err == OK: print("Existing settings deleted successfully.")
					else: printerr("Failed to delete existing settings. Error: ", del_err) # Log delete errors.
				else: 
					print("No existing settings file found to delete.") # Nothing to do if it's already gone.
		else: 
			# Log why we skipped the settings operation.
			if sanitized_profile_name.is_empty(): printerr("Cannot operate on settings: Invalid profile name.")
			if local_app_data.is_empty(): printerr("Cannot operate on settings: LOCALAPPDATA not found.")

		_update_progress_bar(active_profile_button, 45, true) # Update progress.

		# --- Verify Setup Before Launch ---
		# If we couldn't even attempt the settings operation, abort the launch.
		if not settings_operation_attempted:
			printerr("Launch cancelled: Settings operation skipped.")
			_update_progress_bar(active_profile_button, 0, false) # Hide progress bar.
			active_profile_button = null # Clear active button tracker.
			# Re-enable all profile buttons.
			for child in profiles_grid.get_children():
				if child is Control and child.has_method("set_interactable"): child.set_interactable(true)
			return # Stop the function here.

		# Check if the Riot Client location is configured.
		if riot_client_location.is_empty():
			printerr("Launch cancelled: Riot Client Location is not set.")
			_update_progress_bar(active_profile_button, 0, false) # Hide bar.
			active_profile_button = null 
			for child in profiles_grid.get_children():
				if child is Control and child.has_method("set_interactable"): child.set_interactable(true)
			return
		
		# Check if the Riot Client executable actually exists at the configured location.
		var executable_path = riot_client_location.path_join("RiotClientServices.exe")
		if not FileAccess.file_exists(executable_path):
			printerr("Launch cancelled: Riot Client executable not found at: ", executable_path)
			_update_progress_bar(active_profile_button, 0, false) # Hide bar.
			active_profile_button = null 
			for child in profiles_grid.get_children():
				if child is Control and child.has_method("set_interactable"): child.set_interactable(true)
			return 
		_update_progress_bar(active_profile_button, 75, true) # Progress update.
			
		# --- Launch the Riot Client Process ---
		print("Attempting to launch Riot Client...") 
		var arguments = ["--launch-product=league_of_legends", "--launch-patchline=live"] # Arguments needed by Riot Client.
		var pid = OS.create_process(executable_path, arguments) # Start the external process.
		
		if pid < 0: # create_process returns < 0 on failure to start.
			printerr("Failed to create Riot Client process. Path: %s" % executable_path) 
			_update_progress_bar(active_profile_button, 0, false) # Hide bar on failure.
			active_profile_button = null # Reset state.
			# Re-enable buttons.
			for child in profiles_grid.get_children():
				if child is Control and child.has_method("set_interactable"): child.set_interactable(true)
		else: # Success!
			print("Riot Client process created successfully (PID: %d) for profile: %s" % [pid, profile_button.name]) 
			_update_progress_bar(active_profile_button, 100, false) # Set bar to 100% and hide it.


	else: # is_stopping
		# --- Stopping a Profile ---
		print("Stop signal received for profile: ", profile_button.name) 
		_update_progress_bar(profile_button, 0, true) # Show progress bar for stopping process.

		# --- Save Current Riot Client Settings to Profile Folder ---
		# This copies the file from AppData/... to user://profiles/...
		var profile_name_text = profile_button.name
		var sanitized_profile_name = profile_name_text.validate_filename().replace(" ", "_")
		var local_app_data = OS.get_environment("LOCALAPPDATA")

		# Check if we have the needed info to proceed.
		if not sanitized_profile_name.is_empty() and not local_app_data.is_empty():
			# Define source (AppData) and destination (user://) paths.
			var profile_settings_dir = "user://profiles/" + sanitized_profile_name
			var profile_settings_path = profile_settings_dir.path_join("RiotGamesPrivateSettings.yaml")
			var riot_client_settings_path = local_app_data.path_join("Riot Games/Riot Client/Data/RiotGamesPrivateSettings.yaml")

			print("Attempting to save RIOT CLIENT settings for profile '", profile_name_text, "' to profile folder.") 

			# Check if the source file exists before trying to copy.
			if not FileAccess.file_exists(riot_client_settings_path):
				printerr("Source RIOT CLIENT settings file not found, cannot save settings for this session: ", riot_client_settings_path) 
			else:
				# Make sure the destination profile folder exists.
				var dir_err = DirAccess.make_dir_recursive_absolute(profile_settings_dir)
				if dir_err != OK:
					printerr("Failed to ensure profile destination directory exists: ", profile_settings_dir, ". Error: ", dir_err)
				else:
					# Copy the file, overwriting if it already exists in the profile folder.
					var copy_err = DirAccess.copy_absolute(riot_client_settings_path, profile_settings_path)
					if copy_err == OK: 
						print("Successfully saved RIOT CLIENT settings to profile folder.") 
					else: # Log copy errors (permissions, file in use?).
						printerr("Failed to save RIOT CLIENT settings to profile folder. Error: ", copy_err)
		else:
			# Log why saving was skipped.
			if sanitized_profile_name.is_empty(): printerr("Cannot save settings: Invalid profile name.")
			if local_app_data.is_empty(): printerr("Cannot save settings: LOCALAPPDATA not found.")

		_update_progress_bar(profile_button, 50, true) # Update progress after save attempt.

		# --- Re-enable Buttons ---
		# Only reset state and re-enable if the button being stopped *was* the active one.
		if active_profile_button == profile_button:
			active_profile_button = null # Clear the active button tracker.
			# Go through all profile buttons and make them interactable again.
			for child in profiles_grid.get_children():
				if child is Control and child.has_method("set_interactable"):
					child.set_interactable(true)
		_update_progress_bar(profile_button, 100, false) # Set bar to 100% and hide it.
		
		# Note: The separate thread to kill Riot/LoL processes is started in profile_button.gd 
		# and runs independently of this UI update logic.


### --- Texture Loading Helper --- ###
# Loads textures safely from res:// or user:// paths.
func load_texture_from_path(path: String) -> Texture2D:
	if path.is_empty():
		printerr("Texture path is empty.")
		return null
	if path.begins_with("res://"): # Standard project resource.
		if ResourceLoader.exists(path): return load(path)
		else: printerr("Resource path does not exist: ", path); return null
	elif path.begins_with("user://"): # Image stored in user data directory.
		if FileAccess.file_exists(path):
			var img = Image.load_from_file(path) # Load as Image first.
			if img: return ImageTexture.create_from_image(img) # Then create Texture.
			else: printerr("Failed to load image from user path: ", path); return null
		else: printerr("User path does not exist: ", path); return null
	else: # Path format not recognized.
		printerr("Invalid or unsupported texture path prefix: ", path)
		return null

### --- Function to hide the error label when profile name text changes --- ###
func _on_profile_name_text_changed(new_text: String):
	# Simple check: if the error label is visible, hide it as soon as the user types something.
	if settings_error and settings_error.visible:
		settings_error.visible = false

# Helper function to update the progress bar on a specific profile button node.
func _update_progress_bar(profile_node, value: float, visible: bool):
	if not profile_node:
		printerr("Cannot update progress bar: profile_node is null.") # Should not happen if called correctly.
		return
	# Find the ProgressBar node using its expected path within the profile button scene.
	var progress_bar = profile_node.get_node_or_null("bg1/Panel/ProgressBar")
	if progress_bar is ProgressBar: # Make sure we found the node and it's the correct type.
		progress_bar.value = value
		progress_bar.visible = visible
	# No error log needed here if not found, might be intentional or already logged elsewhere.

### --- Profile Deletion Handling --- ###
func _on_profile_delete_requested(profile_node):
	var profile_name_to_delete = profile_node.name
	print("Handling delete request for profile: ", profile_name_to_delete)

	# --- Step 1: Modify JSON Data ---
	var json_path = "res://Data/profiles_data.json"
	var json_file = FileAccess.open(json_path, FileAccess.READ)
	var custom_bg_path_to_delete = "" # Store potential custom background path

	if not json_file:
		printerr("Error: Could not open profiles_data.json for deletion.")
		return

	var json_string = json_file.get_as_text()
	json_file.close()
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		printerr("Error parsing JSON for deletion: ", json_parser.get_error_message())
		return

	var data = json_parser.get_data()
	if not data is Dictionary or not data.has("profiles") or not data["profiles"] is Array:
		printerr("Invalid JSON structure for deletion.")
		return

	var profiles_array = data["profiles"]
	var profile_found = false
	for i in range(profiles_array.size() - 1, -1, -1): # Iterate backwards for safe removal
		var profile_entry = profiles_array[i]
		if profile_entry is Dictionary and profile_entry.get("profile_name") == profile_name_to_delete:
			# Store the custom background path if it exists and is a user path
			var bg_path = profile_entry.get("custom_background_image", "")
			if bg_path.begins_with("user://UserBackground/"):
				custom_bg_path_to_delete = bg_path
				
			profiles_array.remove_at(i)
			profile_found = true
			print("Removed profile entry from JSON data.")
			break # Assume unique names, stop after finding

	if not profile_found:
		printerr("Profile '", profile_name_to_delete, "' not found in JSON data.")
		# Continue anyway to attempt file/node cleanup, might be an orphaned button

	# Save the modified JSON
	var modified_json_string = JSON.stringify(data, "\t")
	var save_file = FileAccess.open(json_path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(modified_json_string)
		save_file.close()
		print("Saved updated JSON data.")
	else:
		printerr("Error saving updated JSON data after deletion.")
		# Consider stopping here or providing more robust error handling

	# --- Step 2: Delete Profile Directory (Recursively) ---
	var sanitized_profile_name = profile_name_to_delete.validate_filename().replace(" ", "_")
	if sanitized_profile_name.is_empty():
		printerr("Warning: Sanitized profile name is empty for deletion, cannot reliably find directory for: ", profile_name_to_delete)
	else:
		var profile_dir_path = "user://profiles/" + sanitized_profile_name
		if DirAccess.dir_exists_absolute(profile_dir_path):
			var remove_err = _remove_dir_recursive(profile_dir_path) # <-- Call recursive helper
			if remove_err != OK:
				printerr("Failed to recursively delete profile directory: ", profile_dir_path, ". Last Error: ", remove_err)
			else:
				print("Successfully deleted profile directory and its contents: ", profile_dir_path)
		else:
			print("Profile directory not found (already deleted or never created): ", profile_dir_path)

	# --- Step 3: Delete Custom Background Image (if applicable) ---
	if not custom_bg_path_to_delete.is_empty():
		if FileAccess.file_exists(custom_bg_path_to_delete):
			var file_access = FileAccess.open(custom_bg_path_to_delete, FileAccess.READ) # Need instance? Docs unclear, but safer
			if file_access: # Check if we could open it implies it exists and we have *some* access
				file_access.close() # Close immediately
				var remove_err = DirAccess.remove_absolute(custom_bg_path_to_delete) # Try deleting with DirAccess
				if remove_err == OK:
					print("Successfully deleted custom background image: ", custom_bg_path_to_delete)
				else:
					printerr("Failed to delete custom background image: ", custom_bg_path_to_delete, ". Error: ", remove_err)
					# Alternative using FileAccess.remove() - Godot 4 doesn't seem to have this static method
					# var fa = FileAccess.new() # Need instance?
					# var remove_err_fa = fa.remove(custom_bg_path_to_delete) # Does FileAccess.remove() exist and work this way? Check docs/test.
			else:
				printerr("Could not get FileAccess instance for path, cannot delete: ", custom_bg_path_to_delete)

		else:
			print("Custom background image not found (already deleted or path mismatch): ", custom_bg_path_to_delete)

	# --- Step 4: Update Active Profile State (if needed) ---
	if active_profile_button == profile_node:
		print("Deleted profile was the active one. Resetting state.")
		active_profile_button = null
		# Re-enable other buttons if needed (though they should already be enabled unless one was running)
		for child in profiles_grid.get_children():
			if child != profile_node and child is Control and child.has_method("set_interactable"):
				child.set_interactable(true) # Ensure others are interactable

	# --- Step 5: Remove Node from Scene ---
	if is_instance_valid(profile_node): # Check if node still exists before freeing
		print("Removing profile button node from scene.")
		profile_node.queue_free()

	# --- Step 6: Update Counter ---
	profile_counter = max(0, profile_counter - 1) # Decrement, ensuring it doesn't go below 0
	print("Profile count updated to: ", profile_counter)

# <-- New Helper Function -->
# Recursively removes a directory and all its contents.
# Returns OK on success, or the error code from the last failed operation.
func _remove_dir_recursive(path: String) -> Error:
	var dir = DirAccess.open(path)
	if not dir:
		printerr("Recursive remove: Could not open directory: ", path)
		# Check if it doesn't exist anymore (maybe deleted by another recursive call)
		if not DirAccess.dir_exists_absolute(path):
			return OK # Considered success if it's already gone
		return DirAccess.get_open_error() # Return the specific open error

	var current_item = dir.get_next()
	while current_item != "":
		if current_item == "." or current_item == "..":
			current_item = dir.get_next()
			continue # Skip self and parent pointers

		var item_path = path.path_join(current_item)
		var error: Error = OK

		if dir.current_is_dir():
			# Recurse into subdirectory
			error = _remove_dir_recursive(item_path)
			if error != OK:
				printerr("Recursive remove: Error deleting subdirectory ", item_path, ". Error: ", error)
				return error # Abort on error
		else:
			# Remove file directly using the *same* DirAccess instance
			error = dir.remove(item_path) # Use relative path for remove within the open dir context
			# Alternative: Use absolute path with a new DirAccess or the static method if available/reliable
			# error = DirAccess.remove_absolute(item_path)
			if error != OK:
				printerr("Recursive remove: Error deleting file ", item_path, ". Error: ", error)
				return error # Abort on error

		current_item = dir.get_next()

	# --- Explicitly release the directory handle BEFORE removing the directory ---
	dir = null # <--- Add this line to explicitly close the handle

	# After clearing contents and releasing the handle, remove the now-empty directory itself
	var final_remove_err = DirAccess.remove_absolute(path)
	if final_remove_err != OK:
		# Check if it already got deleted in the meantime (unlikely but possible)
		if not DirAccess.dir_exists_absolute(path):
			print("Recursive remove: Directory ", path, " already gone before final remove attempt.")
			return OK # If it's gone, it's a success in this context
			
		printerr("Recursive remove: Failed to remove final empty directory: ", path, ". Error: ", final_remove_err)
		return final_remove_err

	print("Recursive remove: Successfully removed final empty directory: ", path)
	return OK
