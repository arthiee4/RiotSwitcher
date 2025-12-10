extends Control

### --- Constants --- ###
# Constants moved to specific controllers

const ProfileManager = preload("res://src/Managers/profile_manager.gd")
const ConfigManager = preload("res://src/Managers/config_manager.gd")

### --- Node References --- ###
@onready var left_menu_handler = $leftmenu_side
@onready var profile_grid_controller = $contet_side/GridContainer # Assumes script attached
@onready var settings_menu = $settings_menu
@onready var add_menu = $add_menu
@onready var boot_screen = $boot
@onready var add_profile_controller = $add_menu # Assumes script attached

### --- State Variables --- ###
var riot_client_location: String = ""
var profile_manager: ProfileManager
var config_manager: ConfigManager

### --- Initialization --- ###
func _ready():
	print("--- Godot User Data Directory ---: ", OS.get_user_data_dir())
	# Verify boot node reference early
	print("[Main:_ready] Checking $boot node reference...")
	if get_node_or_null("boot") == null:
		printerr("[Main:_ready] ERROR: Node at path 'boot' not found!")
	else:
		print("[Main:_ready] Node at path 'boot' seems valid.")
	
	profile_manager = ProfileManager.new()
	config_manager = ConfigManager.new() 
	# add_child(config_manager) # Moved down
	
	# Connect signal BEFORE adding child to scene tree
	print("[Main:_ready] Attempting to connect config_manager.configs_updated...")
	var err = config_manager.configs_updated.connect(_on_configs_updated)
	if err == OK:
		print("[Main:_ready] Successfully connected configs_updated signal.")
	else:
		printerr("[Main:_ready] FAILED to connect configs_updated signal. Error code: ", err)
		
	# Now add child, which will trigger its _ready and emit the signal
	add_child(config_manager)
	print("[Main:_ready] ConfigManager added as child.")

	if left_menu_handler:
		left_menu_handler.home_selected.connect(_show_home_view)
		left_menu_handler.settings_selected.connect(_show_settings_view)
		left_menu_handler.add_profile_selected.connect(_show_add_profile_view)
	else:
		printerr("Left Menu Handler node not found or script not attached correctly.")

	if add_profile_controller:
		if add_profile_controller.has_method("set_profile_manager"):
			add_profile_controller.set_profile_manager(profile_manager)
		else:
			printerr("AddProfileController is missing set_profile_manager method!")
		if add_profile_controller.has_signal("profile_created_successfully"):
			add_profile_controller.profile_created_successfully.connect(_on_profile_creation_success)
		else:
			printerr("AddProfileController is missing profile_created_successfully signal!")
		if add_profile_controller.has_signal("warning_dismissed"):
			add_profile_controller.warning_dismissed.connect(_on_add_menu_warning_dismissed)
		else:
			printerr("AddProfileController is missing warning_dismissed signal!")
	else:
		printerr("Add Profile Controller node not found or script not attached correctly.")

	if profile_grid_controller:
		if profile_grid_controller.has_method("set_dependencies"):
			profile_grid_controller.set_dependencies(profile_manager, riot_client_location)
		else:
			printerr("ProfileGridController is missing set_dependencies method!")
	else:
		printerr("Profile Grid Controller node not found or script not attached correctly.")

	connect_signals()
	initialize_ui()
	# ProfileManager loads its data; signal connects in ProfileGridController
	profile_manager.load_profiles_data()

	_show_home_view() # Set initial view

### --- Loading & Setup Functions --- ###

func _on_configs_updated(new_config_data: Dictionary):
	print("-----> [Main] _on_configs_updated FUNCTION ENTERED <-----") # Extra check
	print("[Main:_on_configs_updated] Received config update.")
	var old_location = riot_client_location
	riot_client_location = new_config_data.get("RiotClientLocation", "")
	# Use str() or let print handle type conversion for diagnostics
	print("[Main:_on_configs_updated] Riot Client Location read as: ", str(riot_client_location))
	print("[Main:_on_configs_updated] riot_client_location == null is: ", riot_client_location == null)
	print("[Main:_on_configs_updated] riot_client_location is empty string is: ", riot_client_location == "")
	var is_location_empty = (riot_client_location == null or riot_client_location == "") # Explicit check
	print("[Main:_on_configs_updated] Determined is_location_empty: ", is_location_empty)

	if riot_client_location != old_location: # Update grid controller only if changed
		if profile_grid_controller and profile_grid_controller.has_method("update_riot_client_location"):
			profile_grid_controller.update_riot_client_location(riot_client_location)

	if boot_screen:
		boot_screen.visible = is_location_empty
		if is_location_empty:
			print("[Main:_on_configs_updated] Boot screen SHOULD BE VISIBLE.")
		else:
			print("[Main:_on_configs_updated] Boot screen should be hidden.")
	else:
		printerr("[Main:_on_configs_updated] boot_screen node reference is null!")

	var should_show_warning = new_config_data.get("warning_shown", true) # Default to true if missing
	print("[Main:_on_configs_updated] Config 'warning_shown' read as: ", should_show_warning)
	if add_profile_controller and add_profile_controller.has_method("set_warning_visibility"):
		print("[Main:_on_configs_updated] Setting add_profile_controller warning visibility to: ", should_show_warning)
		# Set visibility DIRECTLY based on the flag (no inversion)
		add_profile_controller.set_warning_visibility(should_show_warning)

func connect_signals():
	if boot_screen and boot_screen.has_signal("client_location_saved"):
		boot_screen.client_location_saved.connect(_on_boot_client_location_saved)
	elif boot_screen:
		printerr("Boot screen node does not have 'client_location_saved' signal.")
	else:
		printerr("Boot screen node not found, cannot connect signals.")

func initialize_ui():
	pass # Initialization primarily handled by controllers

### --- View Switching Handlers --- ###
func _show_home_view():
	print("Switching to Home view")
	if settings_menu: settings_menu.visible = false
	if add_menu: add_menu.visible = false

func _show_settings_view():
	print("Switching to Settings view")
	if settings_menu: settings_menu.visible = true
	if add_menu: add_menu.visible = false

func _show_add_profile_view():
	print("Switching to Add Profile view")
	if settings_menu: settings_menu.visible = false
	if add_menu: add_menu.visible = true

### --- Profile Creation Handler --- ###

func _on_profile_creation_success():
	print("Main received profile_created_successfully signal.")
	if left_menu_handler and left_menu_handler.has_method("select_home"):
		left_menu_handler.select_home()
	else:
		_show_home_view() # Fallback

### --- Warning Popup Handlers --- ###

func _on_add_menu_warning_dismissed():
	print("[Main] Received warning_dismissed signal from AddProfileController.")
	# When dismissed, we want to save warning_shown = false
	_save_warning_config_state(false)

func _save_warning_config_state(should_show: bool): # Renamed parameter for clarity
	print("[Main] _save_warning_config_state called with should_show: ", should_show)
	if not config_manager:
		printerr("[Main] ConfigManager reference is null in _save_warning_config_state!")
		return
	print("[Main] Calling config_manager.set_value_and_save('warning_shown', ", should_show, ")")
	if not config_manager.set_value_and_save("warning_shown", should_show):
		printerr("Failed to save warning state via ConfigManager.")
	else:
		# Use the actual saved value in the print message
		print("Updated configs.json with warning_shown = ", should_show)

### --- Boot Screen Handlers --- ###
func _on_boot_client_location_saved():
	print("Client location saved signal received. Hiding boot screen.")
	if boot_screen: boot_screen.visible = false
	pass

### --- System Notifications --- ###

# FPS limiter for when the window is not focused
func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Engine.max_fps = 5
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Engine.max_fps = 60
