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

# Config keys (see the settings menu toggles).
const CONFIG_KEY_SYNC_SETTINGS := "SyncGameSettings"
const CONFIG_KEY_SYNC_SOURCE := "SharedSettingsSourceProfile"

# Dependencies, injected by Main.
var profile_manager: Node
var riot_client_location: String = ""

var _active_button: Control = null
var _running_profile_name: String = "" # Survives grid repopulation.
var _worker: Thread = null
var _progress_tween: Tween = null

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
		child.queue_free()
	_cards.clear()
	_active_button = null

	var profiles: Array = profile_manager.get_profiles()
	for i in range(profiles.size()):
		var profile_data: Dictionary = profiles[i]
		_create_profile_button(profile_data, i)

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
func play_cascade_entrance() -> void:
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

		card.pivot_offset = card_size * 0.5
		card.modulate.a = 0.0
		card.scale = Vector2(0.88, 0.88)

		var delay := i * 0.035 # Crisp stagger (35ms per card)
		var tween := card.create_tween().set_parallel(true)
		_cascade_tweens.append(tween)

		var target_alpha: float = 1.0
		if card.get("_is_interactable") == false and _active_button != null and card != _active_button:
			target_alpha = 0.5

		tween.tween_property(card, "modulate:a", target_alpha, 0.16).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE, 0.20).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	_disable_other_buttons(button)
	_update_progress_bar(button, 15, true)

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
		_restore_shared_game_settings(next_profile)

	call_deferred("_on_swap_finished", next_profile, executable_path, success)


func _on_swap_finished(profile_name: String, executable_path: String, success: bool) -> void:
	_join_worker()
	if not success or not is_instance_valid(_active_button) or _active_button.profile_name != profile_name:
		_fail_start()
		return

	_update_progress_bar(_active_button, 75, true)

	var pid := OS.create_process(executable_path, LAUNCH_ARGS)
	if pid < 0:
		printerr("ProfileGridController: Failed to launch Riot Client. Error: ", pid)
		_fail_start()
		return

	_active_button.confirm_started()
	profile_manager.mark_profile_opened(profile_name)
	_update_progress_bar(_active_button, 100, false)
	print("ProfileGridController: Profile '%s' launched (PID %d)." % [profile_name, pid])


func _begin_stop(button: Control) -> void:
	_update_progress_bar(button, 0, false)
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


#region Shared game settings

func _sync_settings_enabled() -> bool:
	return bool(ConfigManager.get_value(CONFIG_KEY_SYNC_SETTINGS, Constants.DEFAULT_SYNC_GAME_SETTINGS))


## Saves the live game settings into the source profile's backup folder (if enabled).
func _save_shared_game_settings(profile_name: String) -> void:
	if not _sync_settings_enabled() or profile_name.is_empty():
		return
	var source_profile: String = ConfigManager.get_value(CONFIG_KEY_SYNC_SOURCE, "")
	if source_profile.is_empty() or profile_name != source_profile:
		return

	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""

	if not live_config_dir.is_empty() and DirAccess.dir_exists_absolute(live_config_dir):
		LeagueSettingsSync.save_shared_settings_from_dir(live_config_dir)

	if profile_manager and profile_manager.has_method("_get_profile_dir"):
		var profile_dir: String = profile_manager._get_profile_dir(profile_name)
		if not profile_dir.is_empty() and DirAccess.dir_exists_absolute(profile_dir):
			LeagueSettingsSync.restore_shared_settings_to_dir(profile_dir)


## Writes the shared game settings from the source profile into the live League folder and target profile folder.
func _restore_shared_game_settings(next_profile: String = "") -> void:
	if not _sync_settings_enabled():
		return
	var source_profile: String = ConfigManager.get_value(CONFIG_KEY_SYNC_SOURCE, "")
	if source_profile.is_empty():
		return

	# 1. Forcefully capture/refresh shared settings from source profile folder or live config
	var source_dir := ""
	if profile_manager and profile_manager.has_method("_get_profile_dir"):
		var p_dir: String = profile_manager._get_profile_dir(source_profile)
		if not p_dir.is_empty() and DirAccess.dir_exists_absolute(p_dir):
			source_dir = p_dir

	var league_dir := LeagueSettingsSync.find_league_dir(riot_client_location)
	var live_config_dir := league_dir.path_join("Config") if not league_dir.is_empty() else ""

	if source_dir.is_empty() or not FileAccess.file_exists(source_dir.path_join("game.cfg")):
		source_dir = live_config_dir

	if not source_dir.is_empty() and DirAccess.dir_exists_absolute(source_dir):
		LeagueSettingsSync.save_shared_settings_from_dir(source_dir)

	# 2. Restore shared settings into live League Config directory
	if not live_config_dir.is_empty():
		LeagueSettingsSync.restore_shared_settings_to_dir(live_config_dir)

	# 3. Restore shared settings into target profile directory
	if profile_manager and not next_profile.is_empty() and profile_manager.has_method("_get_profile_dir"):
		var target_profile_dir: String = profile_manager._get_profile_dir(next_profile)
		if not target_profile_dir.is_empty():
			LeagueSettingsSync.restore_shared_settings_to_dir(target_profile_dir)


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
	_cleanup_drag()
	_join_worker()

#endregion
