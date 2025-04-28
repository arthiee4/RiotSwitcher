extends GridContainer

# Constants
const ADD_PROFILE_BUTTON_SCENE = preload("res://scenes/components/profile_button.tscn")
const DEFAULT_BG_PATH = "res://assets/backgrounds/default_bg.webp"
const ProfileManager = preload("res://src/profile_manager.gd") # Define ProfileManager type

# Dependencies (Injected from Main)
var profile_manager: ProfileManager
var riot_client_location: String = ""

# State
var active_profile_button = null # Currently running profile button node, if any.

# Public function to set dependencies after instantiation
func set_dependencies(pm: ProfileManager, client_loc: String):
	profile_manager = pm
	riot_client_location = client_loc
	if profile_manager:
		# Connect to profile manager updates AFTER dependency is set
		if not profile_manager.profiles_updated.is_connected(_populate_profile_buttons):
			profile_manager.profiles_updated.connect(_populate_profile_buttons)
		# Initial population
		_populate_profile_buttons()
	else:
		printerr("ProfileGridController: ProfileManager dependency is null!")

# Public function to update riot_client_location if it changes
func update_riot_client_location(client_loc: String):
	riot_client_location = client_loc
	print("ProfileGridController: Riot Client Location updated.")

### --- Grid Population and Button Creation --- ###

# Populates the profile grid based on data from ProfileManager.
func _populate_profile_buttons():
	if not profile_manager:
		printerr("ProfileGridController: Cannot populate, ProfileManager not set.")
		return
	print("ProfileGridController: Populating profile buttons...")
	# Clear existing buttons first
	for child in get_children():
		child.queue_free()

	# Get data from manager and create buttons
	var profiles = profile_manager.get_profiles()
	for profile_data in profiles:
		if profile_data is Dictionary:
			_create_profile_button(profile_data)
	print("ProfileGridController: Finished populating profile buttons. Count: ", profiles.size())

# Instantiates and adds a profile button based on profile data.
func _create_profile_button(profile_data: Dictionary):
	var new_profile = ADD_PROFILE_BUTTON_SCENE.instantiate()
	var profile_name_text = profile_data.get("profile_name", "Unknown Profile")
	new_profile.name = profile_name_text
	print("[ProfileGridController] Creating button. Profile Name Text: ", profile_name_text, " | Node Name SET TO: ", new_profile.name)

	var profile_label = new_profile.find_child("profile_name", true, false)
	if profile_label: profile_label.text = profile_name_text

	var texture_rect = new_profile.get_node_or_null("bg1/Panel/profile_bg")
	if texture_rect:
		var image_path = profile_data.get("custom_background_image", "")
		var profile_texture = _load_texture_from_path(image_path)
		if profile_texture:
			texture_rect.texture = profile_texture
		else:
			texture_rect.texture = load(DEFAULT_BG_PATH) # Use default

	var initial_progress_bar = new_profile.get_node_or_null("bg1/Panel/ProgressBar")
	if initial_progress_bar:
		initial_progress_bar.visible = false
		initial_progress_bar.value = 0

	# Connect signals from the new button instance TO THIS CONTROLLER
	if new_profile.has_signal("client_toggled"):
		new_profile.client_toggled.connect(_on_profile_client_toggled)
	else: printerr("Profile button scene missing 'client_toggled' signal.")
	if new_profile.has_signal("delete_requested"):
		new_profile.delete_requested.connect(_on_profile_delete_requested)
	else: printerr("Profile button scene missing 'delete_requested' signal.")

	add_child(new_profile)

### --- Profile Button Signal Handlers --- ###

# Core logic called when a profile button's state changes (start/stop).
func _on_profile_client_toggled(profile_button, is_starting: bool):
	if not is_instance_valid(profile_button):
		printerr("ProfileGridController: _on_profile_client_toggled called with invalid node.")
		return

	if is_starting:
		_handle_profile_start(profile_button)
	else:
		_handle_profile_stop(profile_button)

# Handles deleting a profile when requested by its button.
func _on_profile_delete_requested(profile_node):
	print("[ProfileGridController] Delete requested for NODE with NAME: ", profile_node.name) # Check the name upon receiving the signal
	if not is_instance_valid(profile_node): 
		printerr("ProfileGridController: Delete request received for an already invalid node.")
		return
	
	if not profile_manager:
		printerr("ProfileGridController: Cannot delete profile, ProfileManager not set.")
		return
		
	var profile_name_to_delete = profile_node.name
	print("ProfileGridController: Handling delete request for profile name: ", profile_name_to_delete)

	# Let ProfileManager handle data and file deletion
	if not profile_manager.delete_profile(profile_name_to_delete):
		printerr("ProfileGridController: Profile deletion failed for '%s'. See ProfileManager logs." % profile_name_to_delete)
		pass # Continue to UI cleanup even if PM reported issues

	# Update Active Profile State if the deleted one was active
	if active_profile_button == profile_node:
		print("ProfileGridController: Deleted profile was active. Resetting state.")
		active_profile_button = null
		_enable_all_buttons()

	# ProfileManager should emit profiles_updated, causing _populate_profile_buttons
	print("ProfileGridController: Deletion processed for node '%s'." % profile_name_to_delete)

### --- Profile Start/Stop Logic --- ###

# Handles the sequence when a profile is started.
func _handle_profile_start(profile_button):
	if not is_instance_valid(profile_button): 
		printerr("ProfileGridController: _handle_profile_start called with invalid node.")
		return
	
	if not profile_manager:
		printerr("ProfileGridController: Cannot start profile, ProfileManager not set.")
		if profile_button.has_method("reset_toggle_state"): profile_button.reset_toggle_state()
		return
		
	# Prevent starting if another profile is already running.
	if active_profile_button != null and active_profile_button != profile_button:
		printerr("ProfileGridController: Another profile is already active ('%s'). Cannot start '%s'" %
			[active_profile_button.name, profile_button.name])
		if profile_button.has_method("reset_toggle_state"):
			profile_button.reset_toggle_state()
		return
	
	print("ProfileGridController: Starting profile: ", profile_button.name)
	active_profile_button = profile_button
	_update_progress_bar(active_profile_button, 0, true)

	# Disable other profile buttons.
	_disable_other_buttons(active_profile_button)

	# Restore Saved Settings or Delete Existing using ProfileManager
	var settings_operation_success = profile_manager.restore_profile_settings(profile_button.name)
	_update_progress_bar(active_profile_button, 45, true)

	# Verify Setup Before Launch
	if not settings_operation_success:
		printerr("ProfileGridController: Launch cancelled: Profile settings restore/delete operation failed.")
		_reset_profile_start_failure()
		return
	if riot_client_location.is_empty():
		printerr("ProfileGridController: Launch cancelled: Riot Client Location is not set.")
		# TODO: Emit signal for Main to show a user-friendly error
		_reset_profile_start_failure()
		return
	var executable_path = riot_client_location.path_join("RiotClientServices.exe")
	if not FileAccess.file_exists(executable_path):
		printerr("ProfileGridController: Launch cancelled: Riot Client executable not found at: ", executable_path)
		# TODO: Emit signal for Main to show a user-friendly error
		_reset_profile_start_failure()
		return

	_update_progress_bar(active_profile_button, 75, true)

	# Launch the Riot Client Process
	print("ProfileGridController: Attempting to launch Riot Client...")
	var arguments = ["--launch-product=league_of_legends", "--launch-patchline=live"]
	var pid = OS.create_process(executable_path, arguments)

	if pid < 0:
		printerr("ProfileGridController: Failed to create Riot Client process. Path: %s, Error Code: %s" % [executable_path, OS.get_process_id()])
		# TODO: Emit signal for Main to show a user-friendly error
		_reset_profile_start_failure()
	else:
		print("ProfileGridController: Riot Client process created successfully (PID: %d) for profile: %s" % [pid, profile_button.name])
		_update_progress_bar(active_profile_button, 100, false)

# Handles the sequence when a profile is stopped.
func _handle_profile_stop(profile_button):
	if not is_instance_valid(profile_button): 
		printerr("ProfileGridController: _handle_profile_stop called with invalid node.")
		return
	
	if not profile_manager:
		printerr("ProfileGridController: Cannot stop profile, ProfileManager not set.")
		_enable_all_buttons() # Enable buttons even if backup fails
		return 

	print("ProfileGridController: Stop signal received for profile: ", profile_button.name)
	_update_progress_bar(profile_button, 0, true)

	# Save Current Riot Client Settings to Profile Folder using ProfileManager
	if not profile_manager.backup_profile_settings(profile_button.name):
		print("ProfileGridController: Warning: Failed to backup settings for profile: ", profile_button.name)

	_update_progress_bar(profile_button, 50, true)

	# Re-enable Buttons
	if active_profile_button == profile_button:
		active_profile_button = null 
	_enable_all_buttons()

	_update_progress_bar(profile_button, 100, false)

### --- Helper Functions --- ###

# Loads a texture safely from res:// or user:// paths.
func _load_texture_from_path(path: String) -> Texture2D:
	if path.is_empty(): return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path): return load(path)
		else: printerr("ProfileGridController: Resource texture path does not exist: ", path); return null
	elif path.begins_with("user://"):
		if FileAccess.file_exists(path):
			var img = Image.load_from_file(path)
			if img: return ImageTexture.create_from_image(img)
			else: printerr("ProfileGridController: Failed to load image from user path: ", path); return null
		else: printerr("ProfileGridController: User texture path does not exist: ", path); return null
	else:
		printerr("ProfileGridController: Invalid or unsupported texture path prefix: ", path)
		return null

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
		if active_profile_button.has_method("reset_toggle_state"):
			active_profile_button.reset_toggle_state()
		active_profile_button = null
	_enable_all_buttons()

# Enables interaction for all profile buttons.
func _enable_all_buttons():
	for child in get_children():
		if child is Control and child.has_method("set_interactable"):
			child.set_interactable(true)
	print("ProfileGridController: All profile buttons enabled.")

# Disables interaction for all profile buttons except the active one.
func _disable_other_buttons(active_button):
	for child in get_children():
		if child is Control and child.has_method("set_interactable"):
			child.set_interactable(child == active_button)
	print("ProfileGridController: Other profile buttons disabled.") 