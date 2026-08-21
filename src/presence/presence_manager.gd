# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

extends Node

## Singleton manager coordinating the Deceive presence masking lifecycle, state, and client launch injection.

enum State {
	DISABLED,   # Appear Offline = OFF or proxies inactive
	STARTING,   # Initializing certificates and binding local ports
	READY,      # Proxies listening and ready to accept incoming client
	RUNNING,    # Riot Client/Game active and presence being filtered
	STOPPING,   # Tearing down sockets and freeing resources
	FAILED      # Failed to initialize or bind ports
}

signal state_changed(new_state: State, old_state: State)
signal proxy_error(error_message: String)

var _current_state: State = State.DISABLED
var _deceive_proxy: DeceiveProxy = null
var _watchdog_timer: float = 0.0
var _tracked_pid: int = -1


func _ready() -> void:
	_deceive_proxy = DeceiveProxy.new(self)
	print("[Presence/Manager] Initialized in state: ", _state_name(_current_state))


func _exit_tree() -> void:
	stop_proxy()
	CryptoHelper.cleanup()


func _process(delta: float) -> void:
	if _current_state == State.READY or _current_state == State.RUNNING:
		if _deceive_proxy != null:
			_deceive_proxy.poll()

	# Process Watchdog when running
	if _current_state == State.RUNNING:
		_watchdog_timer += delta
		if _watchdog_timer >= PresenceConstants.PROCESS_POLL_INTERVAL_SEC:
			_watchdog_timer = 0.0
			_check_processes_watchdog()


## Checks whether Appear Offline is enabled in configs.json.
func is_appear_offline_enabled() -> bool:
	if ConfigManager != null:
		return bool(ConfigManager.get_value(PresenceConstants.CONFIG_KEY_APPEAR_OFFLINE, false))
	return false


## Returns the current lifecycle state.
func get_state() -> State:
	return _current_state


## Starts the local proxies before launching the client.
func start_proxy() -> bool:
	if not is_appear_offline_enabled():
		return false

	# If already running (e.g. from previous account session), stop cleanly first
	if _current_state == State.RUNNING or _current_state == State.STARTING or _current_state == State.STOPPING:
		stop_proxy()
	elif _current_state == State.READY:
		return true

	_set_state(State.STARTING)
	print("[Presence/Manager] Starting Deceive proxy layer...")

	var err := _deceive_proxy.start()
	if err != OK:
		printerr("[Presence/Manager] Failed to start Deceive proxy. Error: ", err)
		_set_state(State.FAILED)
		proxy_error.emit("Failed to bind local proxy ports.")
		return false

	_set_state(State.READY)
	return true


## Stops the proxies and releases all local ports.
func stop_proxy() -> void:
	if _current_state == State.DISABLED:
		return

	_set_state(State.STOPPING)
	print("[Presence/Manager] Stopping Deceive proxy layer...")

	if _deceive_proxy != null:
		_deceive_proxy.stop()

	_tracked_pid = -1
	_set_state(State.DISABLED)


## Prepares client launch arguments with injected config URL if active.
func get_launch_args(base_args: Array[String]) -> Array[String]:
	if not is_appear_offline_enabled() or (_current_state != State.READY and _current_state != State.RUNNING):
		return base_args.duplicate()

	var args := base_args.duplicate()
	var config_port := _deceive_proxy.get_config_port()
	if config_port > 0:
		args.append("--client-config-url=http://%s:%d" % [PresenceConstants.LOCALHOST_IP, config_port])
		print("[Presence/Manager] Injected launch argument: --client-config-url=http://%s:%d" % [PresenceConstants.LOCALHOST_IP, config_port])
	return args


## Notifies the manager that the client process was launched successfully.
func notify_client_started(pid: int) -> void:
	_tracked_pid = pid
	_set_state(State.RUNNING)
	print("[Presence/Manager] Tracked Riot Client started with PID: %d" % pid)


## Watchdog routine that detects when Riot processes are closed by the user.
## Uses fast non-blocking OS.is_process_running first to prevent UI freezing.
func _check_processes_watchdog() -> void:
	if _tracked_pid > 0 and OS.is_process_running(_tracked_pid):
		return

	# If tracked PID has exited (e.g. launcher passed execution to LeagueClientUx.exe),
	# check if any game process is still active.
	if not RiotProcesses.are_any_running():
		print("[Presence/Manager] No Riot processes detected. Shutting down proxy.")
		stop_proxy()


func _set_state(new_state: State) -> void:
	if _current_state == new_state:
		return
	var old_state := _current_state
	_current_state = new_state
	print("[Presence/Manager] State changed: %s -> %s" % [_state_name(old_state), _state_name(new_state)])
	state_changed.emit(new_state, old_state)


func _state_name(state: State) -> String:
	match state:
		State.DISABLED: return "DISABLED"
		State.STARTING: return "STARTING"
		State.READY: return "READY"
		State.RUNNING: return "RUNNING"
		State.STOPPING: return "STOPPING"
		State.FAILED: return "FAILED"
		_: return "UNKNOWN"
