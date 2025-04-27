extends Control

# Signal emitted when the user successfully selects and saves the Riot Client location
signal client_location_saved

@onready var icon = $Control/TextureRect
@onready var filedialog = $Control/FileDialog
@onready var browser_button = $Control/Button
@onready var error = $Control/error

var _initial_icon_rotation: float # Store initial rotation
var _icon_tween: Tween

func _ready():
	# Store initial rotation
	_initial_icon_rotation = icon.rotation_degrees
	
	# Configure the FileDialog to select directories
	filedialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	filedialog.title = "Select Riot Client Installation Directory"
	
	# Ensure error message is hidden initially
	if error: error.visible = false
	
	# Connect signals
	browser_button.pressed.connect(_on_browser_button_pressed)
	filedialog.dir_selected.connect(_on_dir_selected)
	
	# Start icon animation
	_animate_icon()

func _animate_icon():
	# Kill existing tween if it exists (useful if called again)
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()

	var sway_angle = 5.0 # Degrees to rotate side-to-side
	var sway_duration = 1.8 # Seconds for one full tilt cycle
	
	_icon_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Simpler sequence: Center -> Right -> Left -> Center 
	var half_duration = sway_duration / 2.0 # Time for one side-to-side swing
	_icon_tween.tween_property(icon, "rotation_degrees", _initial_icon_rotation + sway_angle, half_duration / 2.0) # Center to Right (Quarter duration)
	_icon_tween.tween_property(icon, "rotation_degrees", _initial_icon_rotation - sway_angle, half_duration)      # Right to Left (Half duration)
	_icon_tween.tween_property(icon, "rotation_degrees", _initial_icon_rotation, half_duration / 2.0)         # Left to Center (Quarter duration)

func _on_browser_button_pressed():
	# Open the dialog
	filedialog.popup_centered()

func _on_dir_selected(dir_path: String):
	print("Riot Client directory selected: ", dir_path)
	# Basic validation: Check if RiotClientServices.exe exists in the selected path
	var exe_path = dir_path.path_join("RiotClientServices.exe")
	if not FileAccess.file_exists(exe_path):
		printerr("Error: RiotClientServices.exe not found in the selected directory: ", dir_path)
		# Show the error message to the user
		if error:
			error.text = "RiotClientServices.exe not found in this directory! Please select the correct folder."
			error.visible = true
		return

	# If code reaches here, the path is valid, hide the error message
	if error: error.visible = false 
	
	# Save the valid path to configs.json
	_save_riot_client_location(dir_path)
	
	# Stop the icon animation
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
		print("Icon animation stopped.")
		# Optionally reset rotation to initial state immediately
		icon.rotation_degrees = _initial_icon_rotation
		
	# Optionally, provide feedback or proceed to the next scene
	print("Riot Client location saved successfully.")
	client_location_saved.emit() # Emit the signal!
	
	# Example: Transition to main scene after successful selection
	# get_tree().change_scene_to_file("res://scenes/main.tscn") 


# Reads configs.json, updates the 'RiotClientLocation', and saves it back.
func _save_riot_client_location(new_location: String):
	var config_path = "res://Data/configs.json"
	var config_data = {}

	# Read existing config
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json_parser = JSON.new()
		var error = json_parser.parse(json_string)
		if error == OK:
			var data = json_parser.get_data()
			if data is Dictionary:
				config_data = data
			else:
				printerr("Warning: Existing configs.json is not a valid dictionary. Overwriting.")
		else:
			printerr("Warning: Failed to parse existing configs.json (Error: %s). Overwriting." % json_parser.get_error_message())
	else:
		print("configs.json not found or couldn't be read. Creating new one.")

	# Convert forward slashes to backslashes for Windows path format
	var windows_path = new_location.replace("/", "\\") # Replace / with \
	# Update or add the Riot Client location using the Windows-style path
	config_data["RiotClientLocation"] = windows_path

	# Write the modified data back
	var modified_json_string = JSON.stringify(config_data, "\t") # stringify will now escape the \
	var save_file = FileAccess.open(config_path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(modified_json_string)
		save_file.close()
		print("Updated configs.json with RiotClientLocation = ", windows_path)
	else:
		printerr("Error saving updated configs.json at: ", config_path)
