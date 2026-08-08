extends GridContainer

## Builds the profile cards and orchestrates starting/stopping profiles.
##
## Starting profile B while profile A was running saves A's session first,
## then restores B's files and launches the client. All blocking work
## (taskkill, file copies) runs on a worker thread; the UI is only touched
## back on the main thread via call_deferred.

const PROFILE_BUTTON_SCENE: PackedScene = preload("res://scenes/components/profile_button.tscn")
const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const CLIENT_EXE := "RiotClientServices.exe"
const LAUNCH_ARGS: Array[String] = ["--launch-product=league_of_legends", "--launch-patchline=live"]

# Config keys (see the settings menu toggles).
const CONFIG_KEY_SYNC_SETTINGS := "SyncGameSettings"
const CONFIG_KEY_SYNC_SOURCE := "SharedSettingsSourceProfile"
const CONFIG_KEY_DIRECT_LAUNCH := "DirectLeagueLaunch"

# Direct-launch watchdog: the launch args are re-sent to the already-running
# Riot Client until the League client actually comes up (a cold start can
# swallow the initial launch request during sign-in). Once the League client
# is up, the Riot Client window is closed. RiotClientServices keeps running
# (it owns the login session).
const LEAGUE_UX_PROCESS := "LeagueClientUx.exe"
const RIOT_UX_PROCESSES: Array[String] = ["RiotClientUx.exe", "RiotClientUxRender.exe"]
const LAUNCH_RETRY_DELAY_MS := 20000
const LAUNCH_MAX_RETRIES := 3
const UX_SETTLE_DELAY_MS := 3000

# Dependencies, injected by Main.
var profile_manager: Node
var riot_client_location: String = ""

var _active_button: Control = null
var _running_profile_name: String = "" # Survives grid repopulation.
var _worker: Thread = null
var _ux_watcher: Thread = null
var _ux_watcher_abort := false
var _progress_tween: Tween = null


func set_dependencies(pm: Node, client_location: String) -> void:
	profile_manager = pm
	riot_client_location = client_location
	if not profile_manager:
		printerr("ProfileGridController: ProfileManager dependency is null!")
		return
	if not profile_manager.profiles_updated.is_connected(_populate_profile_buttons):
		profile_manager.profiles_updated.connect(_populate_profile_buttons)
	_populate_profile_buttons()


func update_riot_client_location(client_location: String) -> void:
	riot_client_location = client_location


## Name of the profile whose client is currently running, or "".
func get_running_profile_name() -> String:
	return _running_profile_name


## Best-effort save of the running profile's session (used before quitting).
func save_running_session() -> void:
	if _running_profile_name.is_empty() or not profile_manager:
		return
	profile_manager.save_profile_session(_running_profile_name, riot_client_location)
	_save_shared_game_settings(_running_profile_name)


#region Grid population

func _populate_profile_buttons() -> void:
	if not profile_manager:
		return
	for child in get_children():
		child.queue_free()
	_active_button = null

	for profile_data: Dictionary in profile_manager.get_profiles():
		_create_profile_button(profile_data)


func _create_profile_button(profile_data: Dictionary) -> void:
	var button: Control = PROFILE_BUTTON_SCENE.instantiate()
	button.profile_data = profile_data
	button.name = "profile_" + profile_data.get("directory_name", "unknown")

	var label := button.find_child("profile_name", true, false)
	if label and label is Label:
		var has_custom_name: bool = profile_data.get("has_custom_name", true)
		label.text = profile_data.get("profile_name", "") if has_custom_name else ""

	var background := button.get_node_or_null("card/Panel/profile_bg")
	if background:
		background.texture = _load_texture(profile_data.get("custom_background_image", ""))

	var progress_bar := button.get_node_or_null("card/Panel/ProgressBar")
	if progress_bar:
		progress_bar.visible = false
		progress_bar.value = 0

	button.client_toggled.connect(_on_profile_client_toggled)
	button.delete_requested.connect(_on_profile_delete_requested)

	add_child(button)

	# If the grid was rebuilt while a client is running, restore its state.
	if profile_data.get("profile_name") == _running_profile_name:
		_active_button = button
		button.confirm_started()
		_disable_other_buttons(button)

#endregion

#region Signal handlers

func _on_profile_client_toggled(button: Control, is_starting: bool) -> void:
	if not is_instance_valid(button) or not profile_manager:
		return
	if _is_busy():
		printerr("ProfileGridController: Another operation is in progress.")
		button.reset_toggle_state()
		return
	if is_starting:
		_begin_start(button)
	else:
		_begin_stop(button)


func _on_profile_delete_requested(button: Control) -> void:
	if not is_instance_valid(button) or not profile_manager:
		return
	var profile_name: String = button.profile_name
	if not profile_manager.delete_profile(profile_name):
		printerr("ProfileGridController: Failed to delete profile '%s'." % profile_name)
	if _active_button == button:
		_active_button = null
		_running_profile_name = ""
		_enable_all_buttons()
	# ProfileManager emits profiles_updated, which rebuilds the grid.

#endregion

#region Start/stop sequences

func _begin_start(button: Control) -> void:
	# Validate everything before touching files or killing processes.
	if riot_client_location.is_empty():
		printerr("ProfileGridController: Riot Client location is not set.")
		button.reset_toggle_state()
		return
	var executable_path := riot_client_location.path_join(CLIENT_EXE)
	if not FileAccess.file_exists(executable_path):
		printerr("ProfileGridController: Riot Client executable not found at: ", executable_path)
		button.reset_toggle_state()
		return
	if not _running_profile_name.is_empty() and _running_profile_name != button.profile_name:
		# Switching directly: the previous session is saved in the worker.
		pass

	var previous_profile := _running_profile_name
	_active_button = button
	_running_profile_name = button.profile_name
	_disable_other_buttons(button)
	_update_progress_bar(button, 15, true)
	_stop_ux_watcher()

	_worker = Thread.new()
	_worker.start(_session_swap_worker.bind(previous_profile, button.profile_name, executable_path))


## Worker thread: stop the client, save the previous session, restore the next one.
func _session_swap_worker(previous_profile: String, next_profile: String, executable_path: String) -> void:
	RiotProcesses.kill_all()
	RiotProcesses.wait_until_all_dead()

	var success := true
	if not previous_profile.is_empty() and previous_profile != next_profile:
		if not profile_manager.save_profile_session(previous_profile, riot_client_location):
			printerr("ProfileGridController: Failed to save session of '%s'." % previous_profile)
			success = false
		_save_shared_game_settings(previous_profile)
	if success and not profile_manager.restore_profile_session(next_profile, riot_client_location):
		printerr("ProfileGridController: Failed to restore session of '%s'." % next_profile)
		success = false
	if success:
		_restore_shared_game_settings()

	call_deferred("_on_swap_finished", next_profile, executable_path, success)


func _on_swap_finished(profile_name: String, executable_path: String, success: bool) -> void:
	_join_worker()
	if not success or not is_instance_valid(_active_button) or _active_button.profile_name != profile_name:
		_fail_start()
		return

	_update_progress_bar(_active_button, 75, true)

	# Direct launch: start LeagueClient.exe itself, skipping the Riot Client
	# window entirely. The watchdog escalates to the classic Riot Client
	# launch command if the League client does not come up.
	var direct_launch := _direct_launch_enabled()
	var launch_path := executable_path
	var launch_args: Array[String] = LAUNCH_ARGS
	if direct_launch:
		var league_exe := _find_league_client_exe()
		if not league_exe.is_empty():
			launch_path = league_exe
			launch_args = []

	var pid := OS.create_process(launch_path, launch_args)
	if pid < 0:
		printerr("ProfileGridController: Failed to launch the client. Error: ", pid)
		_fail_start()
		return

	_active_button.confirm_started()
	profile_manager.mark_profile_opened(profile_name)
	_update_progress_bar(_active_button, 100, false)
	if direct_launch:
		_start_ux_watcher(executable_path)
	print("ProfileGridController: Profile '%s' launched via %s (PID %d)." % [profile_name, launch_path.get_file(), pid])


func _begin_stop(button: Control) -> void:
	_update_progress_bar(button, 0, false)
	_stop_ux_watcher()
	_worker = Thread.new()
	_worker.start(_session_save_worker.bind(button.profile_name))


## Worker thread: stop the client, then save this profile's session.
func _session_save_worker(profile_name: String) -> void:
	RiotProcesses.kill_all()
	RiotProcesses.wait_until_all_dead()
	var success: bool = profile_manager.save_profile_session(profile_name, riot_client_location)
	_save_shared_game_settings(profile_name)
	call_deferred("_on_save_finished", success)


func _on_save_finished(success: bool) -> void:
	_join_worker()
	if not success:
		printerr("ProfileGridController: Session save finished with errors.")
	if is_instance_valid(_active_button):
		_active_button.confirm_stopped()
		_update_progress_bar(_active_button, 0, false)
	_active_button = null
	_running_profile_name = ""
	_enable_all_buttons()

#endregion

#region Helpers

func _fail_start() -> void:
	if is_instance_valid(_active_button):
		_active_button.reset_toggle_state()
		_update_progress_bar(_active_button, 0, false)
	_active_button = null
	_running_profile_name = ""
	_enable_all_buttons()


func _is_busy() -> bool:
	return _worker != null and _worker.is_alive()


func _join_worker() -> void:
	if _worker:
		if _worker.is_alive():
			_worker.wait_to_finish()
		_worker = null


#region Shared game settings / direct launch

func _sync_settings_enabled() -> bool:
	return bool(ConfigManager.get_value(CONFIG_KEY_SYNC_SETTINGS, Constants.DEFAULT_SYNC_GAME_SETTINGS))


func _direct_launch_enabled() -> bool:
	return bool(ConfigManager.get_value(CONFIG_KEY_DIRECT_LAUNCH, Constants.DEFAULT_DIRECT_LAUNCH))


## Captures the live League game settings into the shared backup — but only
## when the session that just ended belongs to the chosen source profile.
func _save_shared_game_settings(profile_name: String) -> void:
	if not _sync_settings_enabled() or profile_name.is_empty():
		return
	var source_profile: String = ConfigManager.get_value(CONFIG_KEY_SYNC_SOURCE, "")
	if source_profile.is_empty() or profile_name != source_profile:
		return
	LeagueSettingsSync.save_shared_settings(LeagueSettingsSync.find_league_dir(riot_client_location))


## Writes the shared game settings into the live League folder (if enabled).
func _restore_shared_game_settings() -> void:
	if not _sync_settings_enabled():
		return
	LeagueSettingsSync.restore_shared_settings(LeagueSettingsSync.find_league_dir(riot_client_location))


## Path to LeagueClient.exe for direct launches, or "" when unavailable.
func _find_league_client_exe() -> String:
	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	if league_dir.is_empty():
		return ""
	var exe := league_dir.path_join("LeagueClient.exe")
	return exe if FileAccess.file_exists(exe) else ""


func _start_ux_watcher(executable_path: String) -> void:
	_stop_ux_watcher()
	_ux_watcher_abort = false
	_ux_watcher = Thread.new()
	_ux_watcher.start(_ux_watch_worker.bind(executable_path))


func _stop_ux_watcher() -> void:
	if _ux_watcher:
		_ux_watcher_abort = true
		if _ux_watcher.is_alive():
			_ux_watcher.wait_to_finish()
		_ux_watcher = null


## Worker thread: makes sure the League client actually launches (re-sending
## the launch command if needed), then closes the Riot Client window so the
## user lands directly in League.
func _ux_watch_worker(executable_path: String) -> void:
	var attempt := 0
	while not _wait_for_league_ux(LAUNCH_RETRY_DELAY_MS):
		if _ux_watcher_abort:
			return
		attempt += 1
		if attempt > LAUNCH_MAX_RETRIES:
			printerr("ProfileGridController: League client did not start; giving up.")
			return
		print("ProfileGridController: League client not up yet; launching through the Riot Client (attempt %d/%d)." % [attempt, LAUNCH_MAX_RETRIES])
		OS.create_process(executable_path, LAUNCH_ARGS)

	if _ux_watcher_abort:
		return
	OS.delay_msec(UX_SETTLE_DELAY_MS) # Let the League client finish hooking the session.
	if _ux_watcher_abort:
		return
	RiotProcesses.kill_names(RIOT_UX_PROCESSES)
	print("ProfileGridController: League client is up; Riot Client window closed.")


## Polls until the League client UX is running. Blocking — worker thread only.
func _wait_for_league_ux(timeout_ms: int) -> bool:
	var elapsed := 0
	while elapsed < timeout_ms:
		if _ux_watcher_abort:
			return false
		if RiotProcesses.is_running(LEAGUE_UX_PROCESS):
			return true
		OS.delay_msec(RiotProcesses.POLL_INTERVAL_MS)
		elapsed += RiotProcesses.POLL_INTERVAL_MS
	return false

#endregion


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return load(DEFAULT_BG_PATH)
	if path.begins_with("res://"):
		return load(path) if ResourceLoader.exists(path) else load(DEFAULT_BG_PATH)
	if path.begins_with("user://") and FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image:
			return ImageTexture.create_from_image(image)
	return load(DEFAULT_BG_PATH)


func _update_progress_bar(button: Control, value: float, bar_visible: bool) -> void:
	if not is_instance_valid(button):
		return
	var progress_bar := button.get_node_or_null("card/Panel/ProgressBar")
	if not progress_bar is ProgressBar:
		return

	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()

	if bar_visible:
		progress_bar.visible = true
		progress_bar.modulate.a = 1.0
		var duration := remap(absf(value - progress_bar.value), 0.0, 100.0, 0.0, 1.2)
		_progress_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_progress_tween.tween_property(progress_bar, "value", value, duration)
	else:
		# Fill to target then fade out.
		var duration := remap(absf(value - progress_bar.value), 0.0, 100.0, 0.0, 1.2)
		_progress_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_progress_tween.tween_property(progress_bar, "value", value, duration)
		_progress_tween.tween_property(progress_bar, "modulate:a", 0.0, 0.3).set_delay(0.15)
		_progress_tween.tween_callback(func(): progress_bar.visible = false)


func _enable_all_buttons() -> void:
	for child in get_children():
		if child.has_method("set_interactable"):
			child.set_interactable(true)


func _disable_other_buttons(active_button: Control) -> void:
	for child in get_children():
		if child.has_method("set_interactable"):
			child.set_interactable(child == active_button)


func _exit_tree() -> void:
	_join_worker()
	_stop_ux_watcher()

#endregion
