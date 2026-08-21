class_name ProfileGridController
extends GridContainer

## Builds the profile cards and orchestrates starting/stopping profiles.
##
## Starting profile B while profile A was running saves A's session first,
## then restores B's files and launches the client. All blocking work
## (taskkill, file copies) runs on a worker thread; the UI is only touched
## back on the main thread via call_deferred.

signal edit_profile_requested(profile_data: Dictionary)

const PROFILE_BUTTON_SCENE: PackedScene = preload("res://scenes/components/profile_button.tscn")
const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const CLIENT_EXE := "RiotClientServices.exe"
const LAUNCH_ARGS: Array[String] = ["--launch-product=league_of_legends", "--launch-patchline=live"]

@export var card_size: Vector2 = Vector2(181, 50)
const HYSTERESIS_FACTOR := 0.20 # 15px deadband on 75px pitch to completely prevent jitter
const SETTINGS_WATCHDOG_INTERVAL := 2.0

# Config keys (see the settings menu toggles).
const CONFIG_KEY_SYNC_SETTINGS := "SyncGameSettings"
const CONFIG_KEY_SYNC_SOURCE := "SharedSettingsSourceProfile"
const CONFIG_KEY_LAST_RUNNING := "LastRunningProfile"

# Dependencies, injected by Main.
var profile_manager: Node
var riot_client_location: String = ""

var _active_button: Control = null
var _running_profile_name: String = "" # Survives grid repopulation.
var _worker: Thread = null
var _progress_tween: Tween = null
var _lcu_injector: LcuInjector = null

# Live settings watchdog state (watches League/Config while a profile runs)
var _settings_watchdog: Timer = null
var _watchdog_baseline: Dictionary = {}
var _watchdog_pending: Dictionary = {}
var _watchdog_last_warned: Dictionary = {}

# Interactive drag state
var _cards: Array[Control] = []
var _dragged_card: Control = null
var _drag_origin_idx: int = -1
var _current_target_idx: int = -1
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _last_mouse_x: float = 0.0
var _mouse_velocity_x: float = 0.0
var _is_snapping := false
var _card_tweens: Dictionary = {}
var _cascade_tweens: Array[Tween] = []


func _ready() -> void:
	_lcu_injector = LcuInjector.new()
	add_child(_lcu_injector)

	_settings_watchdog = Timer.new()
	_settings_watchdog.wait_time = SETTINGS_WATCHDOG_INTERVAL
	_settings_watchdog.one_shot = false
	_settings_watchdog.timeout.connect(_on_settings_watchdog_tick)
	add_child(_settings_watchdog)


func set_dependencies(pm: Node, client_location: String) -> void:
	profile_manager = pm
	riot_client_location = client_location
	if not profile_manager:
		printerr("ProfileGridController: ProfileManager dependency is null!")
		return
	if not profile_manager.profiles_updated.is_connected(_populate_profile_buttons):
		profile_manager.profiles_updated.connect(_populate_profile_buttons)
	_adopt_running_profile_from_config()
	_populate_profile_buttons()
	if not _running_profile_name.is_empty():
		_start_settings_watchdog()


## If a client was left running when the app last exited (or crashed) and the
## client process is still alive, adopt that profile as "running" so switching
## to another profile saves its session first instead of silently killing it.
func _adopt_running_profile_from_config() -> void:
	var last_running: String = ConfigManager.get_value(CONFIG_KEY_LAST_RUNNING, "")
	if last_running.is_empty():
		return
	if not profile_manager.has_profile(last_running):
		ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
		return
	if not RiotProcesses.is_running(CLIENT_EXE):
		ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
		return
	_running_profile_name = last_running
	print("ProfileGridController: Adopted running profile '%s' from the previous session." % last_running)


func update_riot_client_location(client_location: String) -> void:
	riot_client_location = client_location


## Name of the profile whose client is currently running, or "".
func get_running_profile_name() -> String:
	return _running_profile_name


## Best-effort save of the running profile's session (used before quitting).
## Waits for any in-flight session swap first so the main thread can never
## write over the files a worker thread is currently swapping. Saves only
## when the client was actually confirmed running — otherwise the files on
## disk may not belong to the running profile.
func save_running_session() -> void:
	if not profile_manager:
		return
	_join_worker()

	var confirmed_running: bool = not _running_profile_name.is_empty() and is_instance_valid(_active_button) and _active_button.client_is_running
	if not confirmed_running and not _running_profile_name.is_empty() and not is_instance_valid(_active_button):
		# The button reference was lost (grid rebuilt/torn down), fall back to
		# the process table so a live client's session is still saved.
		confirmed_running = RiotProcesses.is_running(CLIENT_EXE)

	# The live League/Config folder still belongs to the last running profile
	# even when the client already exited, so always capture the shared game
	# settings (source profile updates included) before quitting.
	if not _running_profile_name.is_empty():
		_save_shared_game_settings(_running_profile_name)

	if not confirmed_running:
		ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
		return

	profile_manager.save_profile_session(_running_profile_name, riot_client_location)


#region Grid population & Layout math

func get_columns_count() -> int:
	return columns if columns > 0 else 4


func get_pitch() -> Vector2:
	var h_sep: float = float(get_theme_constant("h_separation"))
	var v_sep: float = float(get_theme_constant("v_separation"))
	var pitch_x := h_sep if h_sep >= card_size.x else (card_size.x + h_sep)
	var pitch_y := v_sep if v_sep >= card_size.y else (card_size.y + v_sep)
	return Vector2(pitch_x, pitch_y)


func get_slot_position(index: int) -> Vector2:
	var cols := get_columns_count()
	var pitch := get_pitch()
	var col := index % cols
	var row := index / cols
	return Vector2(col * pitch.x, row * pitch.y)


func get_slot_center(index: int) -> Vector2:
	return get_slot_position(index) + card_size * 0.5


func _populate_profile_buttons() -> void:
	if not profile_manager:
		return
	_cleanup_drag()
	for child in get_children():
		if child == _lcu_injector or child == _settings_watchdog:
			continue
		child.queue_free()
	_cards.clear()
	_active_button = null

	var profiles: Array = profile_manager.get_profiles()
	var running_still_exists := _running_profile_name.is_empty()
	for i in range(profiles.size()):
		var profile_data: Dictionary = profiles[i]
		if profile_data.get("profile_name") == _running_profile_name:
			running_still_exists = true
		_create_profile_button(profile_data, i)

	# Safety net: the profile backing the running state was removed.
	if not running_still_exists:
		_running_profile_name = ""

	if is_visible_in_tree():
		call_deferred("play_cascade_entrance")


func _create_profile_button(profile_data: Dictionary, slot_index: int) -> void:
	var button: Control = PROFILE_BUTTON_SCENE.instantiate()
	button.profile_data = profile_data
	button.name = "profile_" + profile_data.get("directory_name", "unknown")
	button.position = get_slot_position(slot_index)
	button.custom_minimum_size = card_size
	button.size = card_size

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
	button.edit_requested.connect(_on_profile_edit_requested)

	add_child(button)
	_cards.append(button)

	# If the grid was rebuilt while a client is running, restore its state.
	if profile_data.get("profile_name") == _running_profile_name:
		_active_button = button
		button.confirm_started()
		_disable_other_buttons(button)


## Plays a crisp, staggered cascade entrance animation for all cards in the grid.
func play_cascade_entrance(initial_delay: float = 0.0) -> void:
	for tw in _cascade_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cascade_tweens.clear()

	# Don't interrupt active drag
	if _dragged_card != null or _is_snapping:
		return

	var count := _cards.size()
	for i in range(count):
		var card := _cards[i]
		if not is_instance_valid(card):
			continue

		var has_offset_transform: bool = "offset_transform_enabled" in card
		if has_offset_transform:
			card.set("offset_transform_enabled", true)
			card.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			card.set("offset_transform_scale", Vector2(0.82, 0.82))
			card.set("offset_transform_visual_only", false)
		else:
			card.pivot_offset = card_size * 0.5
			card.scale = Vector2(0.82, 0.82)

		card.modulate.a = 0.0

		var delay: float = initial_delay + (i * 0.05) # Juicy stagger (50ms per card)
		var tween := card.create_tween().set_parallel(true)
		_cascade_tweens.append(tween)

		var target_alpha: float = 1.0
		if card.get("_is_interactable") == false and _active_button != null and card != _active_button:
			target_alpha = 0.5

		tween.tween_property(card, "modulate:a", target_alpha, 0.22).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset_transform:
			tween.tween_property(card, "offset_transform_scale", Vector2.ONE, 0.28).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(card, "scale", Vector2.ONE, 0.28).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

#endregion

#region Drag and drop reordering (Interactive, Smooth & Jitter-Free)

func _input(event: InputEvent) -> void:
	if _dragged_card == null or _is_snapping:
		return

	if event is InputEventMouseMotion:
		_process_card_drag(event.global_position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
		_finish_card_drag()


## Starts dragging the actual card with elevation, bounce scale, and dynamic tilt.
func start_card_drag(card: Control, mouse_pos: Vector2) -> void:
	if _is_busy() or not is_instance_valid(card) or _dragged_card != null or _is_snapping:
		return

	_dragged_card = card
	_drag_origin_idx = _cards.find(card)
	if _drag_origin_idx == -1:
		_dragged_card = null
		return

	_current_target_idx = _drag_origin_idx
	_drag_grab_offset = mouse_pos - card.global_position
	_last_mouse_x = mouse_pos.x
	_mouse_velocity_x = 0.0

	# Elevate the actual card so it renders above all other cards
	var card_global := card.global_position
	card.top_level = true
	card.z_index = 100
	card.pivot_offset = card_size * 0.5
	card.global_position = card_global

	# Juicy lift-up tween: bounce scale, slight glow
	var lift_tween := card.create_tween().set_parallel(true)
	lift_tween.tween_property(card, "scale", Vector2(1.08, 1.08), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var glow = card.get_node_or_null("card/card_inner/glow")
	if glow:
		lift_tween.tween_property(glow, "modulate", Color(1, 1, 1, 0.6), 0.14)


## Updates card position, dynamic rotation tilt, and smoothly shifts other cards in real-time.
func _process_card_drag(mouse_pos: Vector2) -> void:
	if not is_instance_valid(_dragged_card):
		return

	# Card follows mouse directly
	_dragged_card.global_position = mouse_pos - _drag_grab_offset

	# Dynamic rotation tilt based on horizontal velocity
	var dx := mouse_pos.x - _last_mouse_x
	_mouse_velocity_x = lerpf(_mouse_velocity_x, dx, 0.35)
	_last_mouse_x = mouse_pos.x
	var target_tilt := clampf(_mouse_velocity_x * 0.45, -7.0, 7.0)
	_dragged_card.rotation_degrees = lerpf(_dragged_card.rotation_degrees, target_tilt, 0.25)

	# Compute dragged card center in local grid space
	var local_card_center: Vector2 = (_dragged_card.global_position + card_size * 0.5) - global_position

	var cols := get_columns_count()
	var pitch := get_pitch()

	# Continuous lattice candidate projection
	var col_cand: int = clampi(int(round((local_card_center.x - card_size.x * 0.5) / pitch.x)), 0, cols - 1)
	var row_cand: int = maxi(0, int(round((local_card_center.y - card_size.y * 0.5) / pitch.y)))
	var cand_idx: int = clampi(row_cand * cols + col_cand, 0, _cards.size() - 1)

	# 2D Hysteresis / Deadband Check to eliminate 100% of jitter
	if cand_idx != _current_target_idx:
		var d_cand: float = local_card_center.distance_to(get_slot_center(cand_idx))
		var d_curr: float = local_card_center.distance_to(get_slot_center(_current_target_idx))
		var hyst_margin: float = minf(pitch.x, pitch.y) * HYSTERESIS_FACTOR

		if d_cand < d_curr - hyst_margin:
			_current_target_idx = cand_idx
			_update_card_displacements()


## Smoothly tweens all other cards to their new virtual slots when the dragged card hovers over a new slot.
func _update_card_displacements() -> void:
	for i in range(_cards.size()):
		var card := _cards[i]
		if card == _dragged_card:
			continue

		var disp_slot := i
		if _drag_origin_idx < _current_target_idx:
			if i > _drag_origin_idx and i <= _current_target_idx:
				disp_slot = i - 1
		elif _current_target_idx < _drag_origin_idx:
			if i >= _current_target_idx and i < _drag_origin_idx:
				disp_slot = i + 1

		var target_pos := get_slot_position(disp_slot)
		_tween_card_to(card, target_pos)


func _tween_card_to(card: Control, target_pos: Vector2) -> void:
	if not is_instance_valid(card):
		return
	if _card_tweens.has(card) and is_instance_valid(_card_tweens[card]) and _card_tweens[card].is_valid():
		_card_tweens[card].kill()

	var t := card.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(card, "position", target_pos, 0.18)
	_card_tweens[card] = t


## Finishes drag with a smooth snap-to-slot animation and persists the new order.
func _finish_card_drag() -> void:
	if not is_instance_valid(_dragged_card):
		_cleanup_drag()
		return

	_is_snapping = true
	var card := _dragged_card
	var final_target_local := get_slot_position(_current_target_idx)
	var final_target_global := global_position + final_target_local

	# Snap tween: flies smoothly into target slot, un-tilts, scales back to 1.0, glow fades
	var snap_tween := card.create_tween().set_parallel(true)
	snap_tween.tween_property(card, "global_position", final_target_global, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	snap_tween.tween_property(card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.tween_property(card, "rotation_degrees", 0.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var glow = card.get_node_or_null("card/card_inner/glow")
	if glow:
		snap_tween.tween_property(glow, "modulate", Color(1, 1, 1, 0.0), 0.14)

	snap_tween.chain().tween_callback(func():
		if is_instance_valid(card):
			card.top_level = false
			card.z_index = 0
			card.scale = Vector2.ONE
			card.rotation_degrees = 0.0
			card.position = final_target_local

		# Update internal array model
		_cards.remove_at(_drag_origin_idx)
		_cards.insert(_current_target_idx, card)

		# Ensure all cards are firmly at their final slot positions in tree order
		for idx in range(_cards.size()):
			move_child(_cards[idx], idx)
			_cards[idx].position = get_slot_position(idx)

		_dragged_card = null
		_is_snapping = false

		# Persist new order
		var new_order: Array = []
		for c in _cards:
			if "profile_name" in c and not str(c.profile_name).is_empty():
				new_order.append(c.profile_name)

		if profile_manager and profile_manager.has_method("reorder_profiles"):
			profile_manager.reorder_profiles(new_order)
	)


func _cleanup_drag() -> void:
	for t in _card_tweens.values():
		if is_instance_valid(t) and t.is_valid():
			t.kill()
	_card_tweens.clear()

	if is_instance_valid(_dragged_card):
		_dragged_card.top_level = false
		_dragged_card.z_index = 0
		_dragged_card.scale = Vector2.ONE
		_dragged_card.rotation_degrees = 0.0
	_dragged_card = null
	_is_snapping = false


## Directly reorders a card and persists to disk.
func reorder_profile_card(source_card: Control, target_index: int) -> void:
	if not is_instance_valid(source_card) or not profile_manager:
		return
	if _is_busy():
		return

	var current_index := _cards.find(source_card)
	if current_index == -1 or current_index == target_index:
		return

	target_index = clampi(target_index, 0, _cards.size() - 1)
	_cards.remove_at(current_index)
	_cards.insert(target_index, source_card)

	for idx in range(_cards.size()):
		move_child(_cards[idx], idx)
		_cards[idx].position = get_slot_position(idx)

	var new_order: Array = []
	for c in _cards:
		if "profile_name" in c and not str(c.profile_name).is_empty():
			new_order.append(c.profile_name)

	profile_manager.reorder_profiles(new_order)

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


func _on_profile_edit_requested(button: Control) -> void:
	if not is_instance_valid(button) or button.profile_data.is_empty():
		return
	edit_profile_requested.emit(button.profile_data)

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

	var previous_profile := _running_profile_name
	_active_button = button
	_running_profile_name = button.profile_name
	# Lock the settings UI while a swap is in flight: changing the sync toggle
	# or the source profile mid-swap would race with the worker thread.
	ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, button.profile_name)
	_disable_other_buttons(button)
	_update_progress_bar(button, 15, true)

	if PresenceManager != null:
		PresenceManager.stop_proxy()
	if _lcu_injector:
		_lcu_injector.stop()

	_worker = Thread.new()
	_worker.start(_session_swap_worker.bind(previous_profile, button.profile_name, executable_path))


## Worker thread: stop the client, save the previous session, restore the next one.
func _session_swap_worker(previous_profile: String, next_profile: String, executable_path: String) -> void:
	RiotProcesses.kill_all()
	RiotProcesses.wait_until_all_dead()
	OS.delay_msec(250) # Allow Vanguard and Windows OS handles to fully flush and release

	var success := true
	if not previous_profile.is_empty() and previous_profile != next_profile:
		if not profile_manager.save_profile_session(previous_profile, riot_client_location):
			printerr("ProfileGridController: Failed to save session of '%s'." % previous_profile)
			success = false
		_save_shared_game_settings(previous_profile)
		OS.delay_msec(100) # Settle saved files on disk
	if success and not profile_manager.restore_profile_session(next_profile, riot_client_location):
		printerr("ProfileGridController: Failed to restore session of '%s'." % next_profile)
		success = false
	if success:
		_restore_shared_game_settings(next_profile)
		OS.delay_msec(150) # Settle game config files on disk before starting client

	call_deferred("_on_swap_finished", next_profile, executable_path, success)


func _on_swap_finished(profile_name: String, executable_path: String, success: bool) -> void:
	_join_worker()
	if not success or not is_instance_valid(_active_button) or _active_button.profile_name != profile_name:
		ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
		if PresenceManager != null:
			PresenceManager.stop_proxy()
		if _lcu_injector:
			_lcu_injector.stop()
		_fail_start()
		return

	_update_progress_bar(_active_button, 75, true)

	var launch_args: Array[String] = LAUNCH_ARGS.duplicate()
	if PresenceManager != null and PresenceManager.is_appear_offline_enabled():
		if PresenceManager.start_proxy():
			launch_args = PresenceManager.get_launch_args(launch_args)
		else:
			printerr("ProfileGridController: Failed to start PresenceManager proxy.")

	var pid := OS.create_process(executable_path, launch_args)
	if pid < 0:
		printerr("ProfileGridController: Failed to launch Riot Client. Error: ", pid)
		if PresenceManager != null:
			PresenceManager.stop_proxy()
		if _lcu_injector:
			_lcu_injector.stop()
		ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
		_fail_start()
		return

	if PresenceManager != null and PresenceManager.is_appear_offline_enabled():
		PresenceManager.notify_client_started(pid)

	_active_button.confirm_started()
	profile_manager.mark_profile_opened(profile_name)
	ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, profile_name)
	_update_progress_bar(_active_button, 100, false)
	print("ProfileGridController: Profile '%s' launched (PID %d)." % [profile_name, pid])
	_start_settings_watchdog()

	# Trigger real-time LCU API Settings Injection for Secondary Profiles
	if _sync_settings_enabled() and _lcu_injector:
		var source_info := LeagueSettingsSync.resolve_source_profile(profile_manager)
		var p_dir := ""
		if profile_manager and profile_manager.has_method("get_profile_dir"):
			p_dir = profile_manager.get_profile_dir(profile_name)
		var is_secondary: bool = not source_info["is_valid"] or p_dir.get_file() != String(source_info.get("directory_name", ""))
		if is_secondary:
			var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
			var master_persisted := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("PersistedSettings.json")
			if not league_dir.is_empty() and FileAccess.file_exists(master_persisted):
				_lcu_injector.start_injection(league_dir, master_persisted)


func _begin_stop(button: Control) -> void:
	_update_progress_bar(button, 0, false)
	if PresenceManager != null:
		PresenceManager.stop_proxy()
	if _lcu_injector:
		_lcu_injector.stop()
	_worker = Thread.new()
	_worker.start(_session_save_worker.bind(button.profile_name))


## Worker thread: stop the client, then save this profile's session.
func _session_save_worker(profile_name: String) -> void:
	RiotProcesses.kill_all()
	RiotProcesses.wait_until_all_dead()
	OS.delay_msec(250) # Settle OS handles and file locks before session archive
	var success: bool = profile_manager.save_profile_session(profile_name, riot_client_location)
	_save_shared_game_settings(profile_name)
	OS.delay_msec(100) # Clean flush
	call_deferred("_on_save_finished", success)


func _on_save_finished(success: bool) -> void:
	_join_worker()
	_stop_settings_watchdog()
	if PresenceManager != null:
		PresenceManager.stop_proxy()
	if not success:
		printerr("ProfileGridController: Session save finished with errors.")
	# The worker killed the client, so nothing is running anymore.
	ConfigManager.set_value_and_save(CONFIG_KEY_LAST_RUNNING, "")
	if is_instance_valid(_active_button):
		_active_button.confirm_stopped()
		_update_progress_bar(_active_button, 0, false)
	_active_button = null
	_running_profile_name = ""
	_enable_all_buttons()

#endregion

#region Helpers

func _fail_start() -> void:
	_stop_settings_watchdog()
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


#region Shared game settings

func _sync_settings_enabled() -> bool:
	return bool(ConfigManager.get_value(CONFIG_KEY_SYNC_SETTINGS, Constants.DEFAULT_SYNC_GAME_SETTINGS))


#region Live settings watchdog

## Starts polling the live League/Config files after a profile launch.
func _start_settings_watchdog() -> void:
	if not _settings_watchdog or not _sync_settings_enabled():
		return
	_watchdog_baseline = {}
	_watchdog_pending = {}
	_watchdog_last_warned = {}
	_settings_watchdog.start()
	print("[GameSettings] Watching League settings for live changes (poll every %.0fs)." % SETTINGS_WATCHDOG_INTERVAL)


func _stop_settings_watchdog() -> void:
	if _settings_watchdog:
		_settings_watchdog.stop()
	_watchdog_baseline = {}
	_watchdog_pending = {}
	_watchdog_last_warned = {}


## Polls the live League/Config files while a profile is running.
## When the SOURCE profile changes anything in-game (hotkeys, video, audio...)
## the change is printed immediately and the master snapshot is captured as
## soon as the files stabilize — no need to close the profile, and the change
## can never be lost to a crash.
func _on_settings_watchdog_tick() -> void:
	if _is_busy() or _running_profile_name.is_empty():
		return

	if not _sync_settings_enabled():
		_watchdog_baseline = {}
		_watchdog_pending = {}
		_watchdog_last_warned = {}
		return

	var source_info := LeagueSettingsSync.resolve_source_profile(profile_manager)
	if not source_info["is_valid"]:
		return

	var live_config_dir := _live_league_config_dir()
	if live_config_dir.is_empty() or not LeagueSettingsSync.has_valid_settings(live_config_dir):
		return

	var sig := _compute_live_settings_signature(live_config_dir)
	if sig.is_empty():
		return

	# First observation after (re)start: baseline silently, no false positives.
	if _watchdog_baseline.is_empty():
		_watchdog_baseline = sig
		return

	var p_dir := ""
	if profile_manager and profile_manager.has_method("get_profile_dir"):
		p_dir = profile_manager.get_profile_dir(_running_profile_name)
	var is_source_running: bool = p_dir.get_file() == String(source_info.get("directory_name", ""))

	if not is_source_running:
		return

	if sig == _watchdog_baseline:
		_watchdog_pending = {}
		return

	var changed_files := _diff_signature_files(_watchdog_baseline, sig)

	if sig != _watchdog_pending:
		# Files changed: League is writing modifications
		print("[GameSettings] ALTERACAO DETECTADA: O perfil pai '%s' modificou as configuracoes no League (Arquivos: %s)!" % [_running_profile_name, ", ".join(changed_files)])
		_watchdog_pending = sig
		return

	# Stable for two consecutive polls: capture now.
	print("[GameSettings] Atualizando snapshot mestre com as novas configuracoes do perfil pai '%s'..." % _running_profile_name)
	var capture_res := LeagueSettingsSync.capture_master_snapshot(live_config_dir, source_info["directory_name"], source_info["display_name"])
	if capture_res == LeagueSettingsSync.CaptureResult.SUCCESS:
		if not String(source_info["profile_dir"]).is_empty():
			LeagueSettingsSync.copy_settings(live_config_dir, source_info["profile_dir"])
		_watchdog_baseline = sig
		var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
		LcuInjector.trigger_cloud_save(league_dir)
		print("[GameSettings] SUCESSO: Snapshot mestre atualizado a partir de '%s'! Todas as contas secundarias agora usarao essas novas configuracoes." % _running_profile_name)
	else:
		printerr("[GameSettings] Live capture failed (Error: %d). Will retry on the next poll." % capture_res)
	_watchdog_pending = {}


func _live_league_config_dir() -> String:
	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	return league_dir.path_join("Config") if not league_dir.is_empty() else ""


## Hashes every tracked settings file inside the live League config.
func _compute_live_settings_signature(live_config_dir: String) -> Dictionary:
	var sig: Dictionary = {}
	for filename in LeagueSettingsSync.SHARED_FILES:
		var path := live_config_dir.path_join(filename)
		if FileAccess.file_exists(path):
			sig[filename] = FileAccess.get_sha256(path)
	return sig


func _diff_signature_files(old_sig: Dictionary, new_sig: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	var seen: Dictionary = {}
	for key in old_sig.keys():
		seen[key] = true
	for key in new_sig.keys():
		seen[key] = true
	var names: Array = seen.keys()
	names.sort()
	for name in names:
		if str(old_sig.get(name, "")) != str(new_sig.get(name, "")):
			changed.append(str(name))
	return changed

#endregion


## Saves the live game settings into the source profile's backup folder (if enabled)
## or saves the profile's own settings when sync is disabled.
func _save_shared_game_settings(profile_name: String) -> void:
	if profile_name.is_empty():
		return

	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""
	if live_config_dir.is_empty() or not LeagueSettingsSync.has_valid_settings(live_config_dir):
		return

	var sync_enabled := _sync_settings_enabled()

	if sync_enabled:
		var source_info := LeagueSettingsSync.resolve_source_profile(profile_manager)
		if not source_info["is_valid"]:
			return

		var p_dir := ""
		if profile_manager and profile_manager.has_method("get_profile_dir"):
			p_dir = profile_manager.get_profile_dir(profile_name)

		var closed_dir_name := p_dir.get_file()

		# Only the Source Profile may update the master shared snapshot!
		if closed_dir_name == source_info["directory_name"]:
			var capture_res := LeagueSettingsSync.capture_master_snapshot(live_config_dir, source_info["directory_name"], source_info["display_name"])
			if capture_res == LeagueSettingsSync.CaptureResult.SUCCESS:
				if not source_info["profile_dir"].is_empty():
					LeagueSettingsSync.copy_settings(live_config_dir, source_info["profile_dir"])
				LcuInjector.trigger_cloud_save(league_dir)
				print("[GameSettings] ENCERRAMENTO DO PAI: Configuracoes finais do perfil pai '%s' salvas no snapshot mestre!" % profile_name)
			else:
				printerr("[GameSettings] Failed to update master settings from source profile '%s' (Error: %d). Previous snapshot preserved." % [profile_name, capture_res])
		else:
			print("[GameSettings] Secondary profile '%s' closed: master shared snapshot preserved unchanged." % profile_name)
	else:
		# Sync is disabled: save this profile's own settings into its directory
		if profile_manager and profile_manager.has_method("get_profile_dir"):
			var profile_dir: String = profile_manager.get_profile_dir(profile_name)
			if not profile_dir.is_empty():
				LeagueSettingsSync.copy_settings(live_config_dir, profile_dir)


## Restores game settings into live League/Config before launch.
func _restore_shared_game_settings(next_profile: String = "") -> void:
	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""
	if live_config_dir.is_empty():
		return

	var sync_enabled := _sync_settings_enabled()

	if sync_enabled:
		var source_info := LeagueSettingsSync.resolve_source_profile(profile_manager)
		var next_p_dir := ""
		if profile_manager and profile_manager.has_method("get_profile_dir"):
			next_p_dir = profile_manager.get_profile_dir(next_profile)
		var next_dir_name := next_p_dir.get_file()

		var is_source_profile: bool = bool(source_info.get("is_valid", false)) and next_dir_name == String(source_info.get("directory_name", ""))
		var enforce_readonly: bool = not is_source_profile

		if is_source_profile:
			# For the Source Profile: deploy master snapshot and ensure read-write for live editing
			LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)
			if LeagueSettingsSync.has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
				LeagueSettingsSync.copy_settings(AppPaths.SHARED_GAME_SETTINGS_DIR, live_config_dir)
			elif not next_p_dir.is_empty() and LeagueSettingsSync.has_valid_settings(next_p_dir):
				LeagueSettingsSync.copy_settings(next_p_dir, live_config_dir)
				LeagueSettingsSync.capture_master_snapshot(next_p_dir, source_info["directory_name"], source_info["display_name"])
			LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)
			print("[GameSettings] INICIANDO PERFIL PAI '%s' (Arquivos destravados para edicao e salvamento in-game)." % next_profile)
		else:
			# For Secondary Profiles: deploy master shared snapshot cleanly
			LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)
			if LeagueSettingsSync.has_valid_settings(AppPaths.SHARED_GAME_SETTINGS_DIR):
				LeagueSettingsSync.copy_settings(AppPaths.SHARED_GAME_SETTINGS_DIR, live_config_dir)
			elif not source_info["profile_dir"].is_empty() and LeagueSettingsSync.has_valid_settings(source_info["profile_dir"]):
				LeagueSettingsSync.copy_settings(source_info["profile_dir"], live_config_dir)
			LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)
			print("[GameSettings] INICIANDO PERFIL SECUNDARIO '%s' (Configuracoes do pai '%s' aplicadas com sucesso)." % [next_profile, source_info["display_name"]])
	else:
		# Sync is disabled: remove Read-Only and restore the profile's own settings if available
		LeagueSettingsSync.cleanup_readonly_flags(live_config_dir)
		if profile_manager and not next_profile.is_empty() and profile_manager.has_method("get_profile_dir"):
			var target_profile_dir: String = profile_manager.get_profile_dir(next_profile)
			if not target_profile_dir.is_empty() and LeagueSettingsSync.has_valid_settings(target_profile_dir):
				LeagueSettingsSync.copy_settings(target_profile_dir, live_config_dir)


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
	var idx := 0
	for child in get_children():
		if child.has_method("set_interactable"):
			child.set_interactable(true, idx * 0.03)
			idx += 1


func _disable_other_buttons(active_button: Control) -> void:
	var idx := 0
	for child in get_children():
		if child.has_method("set_interactable"):
			if child == active_button:
				child.set_interactable(true, 0.0)
			else:
				child.set_interactable(false, idx * 0.025)
				idx += 1


func _exit_tree() -> void:
	_cleanup_drag()
	_join_worker()
	_stop_settings_watchdog()

#endregion
