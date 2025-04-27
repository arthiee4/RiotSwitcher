extends Control

signal client_toggled(profile_button, is_starting)
signal delete_requested(profile_button)

## My mouse menu stuff
@onready var mouse_menu = $bg1/mouse_right_menu
@onready var delete_profile_button = $bg1/mouse_right_menu/Panel/delete/TextureButton

@onready var glow_effect = $bg1/bg2/glow

## My profile button stuff
@onready var profile_button = $bg1/bg2/Button
@onready var profile_button_icon_state = $bg1/bg2/Button/TextureRect

@onready var bg1_button = $bg1

@onready var stop_icon = preload("res://assets/user_icons/stop.png")
@onready var play_icon = preload("res://assets/user_icons/play.png")

@onready var profile_loading_progress_bar = $bg1/Panel/ProgressBar

var client_is_running = false
var _is_interactable = true

var first_time_open = false

# My thread variable for killing processes
var _kill_thread: Thread = null

func _ready():
	delete_profile_button.pressed.connect(_on_delete_button_pressed)
	bg1_button.gui_input.connect(_on_bg1_gui_input)

	# I need to make sure the menu is hidden initially
	mouse_menu.visible = false

	# Process input events at the node level (I need this for _input)
	set_process_input(true)

# My hover style logic
func _on_bg_1_mouse_entered() -> void:
	if not _is_interactable: return
	var tween = create_tween()
	tween.tween_property(glow_effect, "modulate", Color(1, 1, 1, 0.4), 0.020).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO) # Animation duration
func _on_bg_1_mouse_exited() -> void:
	if not _is_interactable: return
	# I shouldn't hide the menu immediately on mouse exit,
	# gotta let the user interact with it first.
	# I'll hide it on other actions later if needed.
	var tween = create_tween()
	tween.tween_property(glow_effect, "modulate", Color(1, 1, 1, 0.0), 0.020).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO) # Animation duration

# My input handler for the background area
func _on_bg1_gui_input(event: InputEvent):
	# Check if it's a mouse button event, right button, and pressed down
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# Prevent interaction if the button is disabled
		if not _is_interactable:
			get_viewport().set_input_as_handled() # Still handle it so it doesn't propagate
			return

		print("Right-click detected on profile: ", name)
		# Make the menu visible
		mouse_menu.visible = true
		# Position the menu at the global mouse position
		mouse_menu.global_position = event.global_position
		# Stop the event from propagating further (e.g., to main view)
		get_viewport().set_input_as_handled()
	# Optional: Hide menu on left click on the background IF the menu is visible
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed() and mouse_menu.visible:
		mouse_menu.visible = false
		# Don't handle this event, let the left click pass through if needed

# Global input processing (hides the menu if click is outside)
func _input(event: InputEvent):
	# Only process if the menu is currently visible
	if not mouse_menu.visible:
		return

	# Check for any mouse button press
	if event is InputEventMouseButton and event.is_pressed():
		# Check if the click position is OUTSIDE the menu's global rectangle
		if not mouse_menu.get_global_rect().has_point(event.position):
			print("Click detected outside menu, hiding.")
			mouse_menu.visible = false
			# Optional: Consume the event if I don't want clicks outside
			# the menu to interact with anything else when the menu was open.
			# get_viewport().set_input_as_handled()

## My button functions here
func _on_profile_button_pressed() -> void:
	if first_time_open:
		print("Este perfil já foi aberto antes.")
	else:
		print("Esta é a primeira vez que este perfil está sendo aberto.")

	if not _is_interactable and not client_is_running:
		return

	client_is_running = !client_is_running

	## My client running sequence here
	if client_is_running:
		profile_button_icon_state.texture = stop_icon
		print("starting client... ", name)

		if not first_time_open:
			first_time_open = true

		# The startup logic is now mainly handled by the signal in main.gd
		# I emit the signal immediately when starting
		client_toggled.emit(self, true)

	## My client stopping sequence here
	else:
		profile_button_icon_state.texture = play_icon
		print("stopping client (initiating background task and waiting 2 seconds)...")

		if _kill_thread != null and _kill_thread.is_alive():
			print("Previous kill task still running, waiting...")
			# I should wait for the previous thread to finish BEFORE the new delay/thread
			await _kill_thread.wait_to_finish() # Made the wait asynchronous

		_kill_thread = Thread.new()
		_kill_thread.start(_kill_processes_threaded)

		# I wait 2.5 seconds BEFORE emitting the signal to re-enable other buttons
		await get_tree().create_timer(2.5).timeout # await still works here
		print("2.5-second wait finished. Emitting client_toggled.")

		# Emit the signal AFTER the wait
		client_toggled.emit(self, false)

# My handler for the delete button
func _on_delete_button_pressed():
	# Hide the menu after clicking delete
	mouse_menu.visible = false

	# I should prevent deletion if the client is currently running for this profile
	if client_is_running:
		printerr("Cannot delete profile while client is running.")
		# Optionally: I could add user feedback here (e.g., show a notification)
		return

	print("Delete requested for profile: ", name)
	delete_requested.emit(self)

# This function is executed by the Thread to kill processes
func _kill_processes_threaded():
	print("Background kill task started.")
	var processes_to_kill = [
		"RiotClientServices.exe",
		"RiotClientUx.exe",
		"RiotClientUxRender.exe",
		"LeagueClient.exe",
		"LeagueClientUx.exe",
		"LeagueClientUxRender.exe",
		"LeagueofLegends.exe"
	]

	for process_name in processes_to_kill:
		var arguments_array = ["/IM", process_name, "/F", "/T"]
		print("[Thread] Attempting to terminate process: taskkill with args: ", arguments_array)

		# Use OS.create_process to call taskkill directly
		var pid = OS.create_process("taskkill", arguments_array)

		if pid < 0:
			printerr("[Thread] Failed to *start* taskkill command for %s." % process_name)
		else:
			print("[Thread] Taskkill command initiated for %s (PID: %d)." % [process_name, pid])
			OS.delay_msec(100) # A small delay

	print("Background kill task finished.")
	# No need to emit signal from here anymore

# Function to make sure the thread is finished when exiting the scene/game
func _exit_tree():
	if _kill_thread != null and _kill_thread.is_alive():
		print("Waiting for kill thread to finish on exit...")
		_kill_thread.wait_to_finish()

# My function to visually enable/disable the button with animation
func set_interactable(is_interactable: bool):
	_is_interactable = is_interactable

	var target_modulate: Color
	if is_interactable:
		target_modulate = Color(1, 1, 1, 1) # Normal appearance
		profile_button.disabled = false # Ensure button node is enabled
	else:
		target_modulate = Color(1, 1, 1, 0.5) # Dimmed appearance
		profile_button.disabled = true # Disable button node immediately

	# Animate the modulate property
	var tween = create_tween()
	tween.set_parallel(true) # Allow modulate and glow tweens to run together if needed
	tween.tween_property(self, "modulate", target_modulate, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO) # Animate over 0.1 seconds

	# If disabling, also fade out the glow effect immediately if hovered
	if not is_interactable and $bg1.get_global_rect().has_point(get_global_mouse_position()):
		tween.tween_property(glow_effect, "modulate", Color(1, 1, 1, 0.0), 0.010).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO) # Animation duration

# My function to explicitly hide the context menu (still useful if called externally)
func hide_context_menu():
	if mouse_menu.visible:
		mouse_menu.visible = false
