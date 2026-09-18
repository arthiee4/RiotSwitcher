class_name RiotProcesses
extends RefCounted

## Single source of truth for Riot-related process management.
##
## Shell-free detection: ONE throttled `tasklist /FO CSV` snapshot feeds a
## cached PID map, and every liveness check afterwards uses the engine-native
## OS.is_process_running() — which spawns no process and costs microseconds.
##
## The snapshot is NEVER captured while holding the cache mutex: tasklist/ps
## spawns (100-300ms) run lock-free and the parsed map is swapped in atomically,
## so a capture on one thread (a worker rescanning, an authoritative query)
## never stalls the presence watchdog on the UI thread. Stale snapshots are
## rebuilt by a short-lived background thread — call warm_up() at app boot so
## even the first query never has to spawn tasklist on the main thread — and
## wait_until_all_dead() validates PIDs purely in-process while processes die.

const PROCESS_NAMES: Array[String] = [
	"RiotClientServices.exe",
	"RiotClientUx.exe",
	"RiotClientUxRender.exe",
	"LeagueClient.exe",
	"LeagueClientUx.exe",
	"LeagueClientUxRender.exe",
	"LeagueofLegends.exe",
]

const KILL_TIMEOUT_MS := 6000
const POLL_INTERVAL_MS := 250

## Minimum age of the cached snapshot before it is considered stale.
const SNAPSHOT_REFRESH_MS := 2000
## Interval between re-kill attempts inside wait_until_all_dead().
const WAIT_RESCAN_MS := 2000

static var _pids_by_name: Dictionary = {} # String (lowercase name) -> Array[int]
static var _snapshot_msec: int = -1000000 # "never captured yet" marker
static var _refresh_in_flight := false
static var _refresh_thread: Thread = null
static var _mutex := Mutex.new()


## Returns true while the process identified by [param pid] is running.
## Pure in-process check: no shell spawn, sub-millisecond, UI-safe.
static func is_pid_alive(pid: int) -> bool:
	return pid > 0 and OS.is_process_running(pid)


## Kicks a background snapshot refresh as early as possible (call once at app
## boot) so the first watchdog query never has to spawn tasklist on the UI
## thread. Non-blocking; safe to call from anywhere.
static func warm_up() -> void:
	_request_snapshot_refresh()


## Waits for any in-flight snapshot refresh to finish and releases the
## background thread. Call during app shutdown so no orphan thread survives.
static func shutdown() -> void:
	_mutex.lock()
	var thread := _refresh_thread
	_mutex.unlock()
	if thread == null:
		return
	thread.wait_to_finish()
	_mutex.lock()
	if _refresh_thread == thread:
		_refresh_thread = null
	_mutex.unlock()


## Sends a single non-blocking taskkill for every known process.
static func kill_all() -> void:
	kill_names(PROCESS_NAMES)


## Sends a single non-blocking taskkill for the given process names.
static func kill_names(names: Array[String]) -> void:
	if names.is_empty():
		return
	var arguments: Array[String] = ["/F", "/T"]
	for process_name in names:
		arguments.append("/IM")
		arguments.append(process_name)
	var pid := OS.create_process("taskkill", arguments)
	if pid < 0:
		printerr("RiotProcesses: Failed to start taskkill.")


## Returns true while the given process is running.
## Authoritative: blocks only long enough to obtain a fresh snapshot, joining
## an in-flight background refresh instead of spawning a duplicate tasklist.
## Repeated calls inside SNAPSHOT_REFRESH_MS reuse the cached PID map.
static func is_running(process_name: String) -> bool:
	if process_name.is_empty():
		return false
	_await_fresh_snapshot()
	_mutex.lock()
	var pids: Array = (_pids_by_name.get(process_name.to_lower(), []) as Array).duplicate()
	_mutex.unlock()
	return _any_pid_alive(pids)


## Returns true while any known process is still running.
## Hot path (presence watchdog): never spawns tasklist on the calling thread
## and never blocks; a stale (or missing) snapshot is rebuilt by a background
## thread while the current answer comes from cached PIDs validated in-process.
static func are_any_running() -> bool:
	_mutex.lock()
	var pids := _collect_known_pids_locked()
	var stale := Time.get_ticks_msec() - _snapshot_msec >= SNAPSHOT_REFRESH_MS
	_mutex.unlock()
	if stale:
		_request_snapshot_refresh()
	return _any_pid_alive(pids)


## Polls until every known process is gone or the timeout elapses.
## Returns true if all processes exited in time. Blocking — use from a thread.
## Only the initial capture spawns tasklist; the hot poll loop validates PIDs
## purely in-process (OS.is_process_running — zero shell spawns).
##
## Re-scan fires a second kill for survivors / re-spawned children but does NOT
## expand the PID set being waited on — that prevented processes from ever
## being considered "done" when Vanguard respawned new client instances.
static func wait_until_all_dead(timeout_ms := KILL_TIMEOUT_MS) -> bool:
	_await_fresh_snapshot()
	_mutex.lock()
	var pids := _collect_known_pids_locked()
	_mutex.unlock()

	var elapsed := 0
	var last_rekill := 0
	while elapsed < timeout_ms:
		if not _any_pid_alive(pids):
			return true
		OS.delay_msec(POLL_INTERVAL_MS)
		elapsed += POLL_INTERVAL_MS
		# Fire a second kill every 2s for any survivors or Vanguard re-spawns,
		# but do NOT expand pids — adding new PIDs would cause an infinite loop
		# when the client re-spawns helper processes after being killed.
		if elapsed - last_rekill >= WAIT_RESCAN_MS:
			kill_all()
			last_rekill = elapsed
	printerr("RiotProcesses: Timed out waiting for processes to exit.")
	return false


## Synchronously rebuilds the cached snapshot right now.
## Blocking (~100ms tasklist spawn) — call from a worker thread or a context
## where a one-off pause is acceptable.
static func refresh_now() -> void:
	_publish_snapshot(_capture_snapshot())


#region Private helpers

## Blocks until the cached snapshot is fresh enough for an authoritative
## answer: joins an in-flight background refresh when one is running (never
## spawning a duplicate tasklist), otherwise captures synchronously. The
## capture itself runs lock-free, so other threads keep answering meanwhile.
static func _await_fresh_snapshot() -> void:
	_mutex.lock()
	var stale := Time.get_ticks_msec() - _snapshot_msec >= SNAPSHOT_REFRESH_MS
	var thread := _refresh_thread
	var in_flight := _refresh_in_flight
	_mutex.unlock()
	if not stale:
		return
	if in_flight and thread != null:
		thread.wait_to_finish()
		_mutex.lock()
		if _refresh_thread == thread:
			_refresh_thread = null
		_mutex.unlock()
		return
	_publish_snapshot(_capture_snapshot())


## Starts a short-lived background thread to rebuild the snapshot so the
## calling (UI) thread never waits on a tasklist spawn.
static func _request_snapshot_refresh() -> void:
	# Reap any previously finished refresh thread (instant: the thread is dead).
	_mutex.lock()
	var old := _refresh_thread
	_mutex.unlock()
	if old != null and not old.is_alive():
		old.wait_to_finish()
		_mutex.lock()
		if _refresh_thread == old:
			_refresh_thread = null
		_mutex.unlock()

	_mutex.lock()
	if _refresh_in_flight or Time.get_ticks_msec() - _snapshot_msec < SNAPSHOT_REFRESH_MS:
		_mutex.unlock()
		return
	_refresh_in_flight = true
	_mutex.unlock()

	var thread := Thread.new()
	_mutex.lock()
	_refresh_thread = thread
	_mutex.unlock()
	if thread.start(_thread_refresh) != OK:
		_mutex.lock()
		if _refresh_thread == thread:
			_refresh_thread = null
		_refresh_in_flight = false
		_mutex.unlock()
		printerr("RiotProcesses: Failed to start snapshot refresh thread.")


static func _thread_refresh() -> void:
	_publish_snapshot(_capture_snapshot())
	_mutex.lock()
	_refresh_in_flight = false
	_mutex.unlock()


## Spawns tasklist/ps ONCE and parses every process into a fresh map.
## Never touches the cache or the mutex: the caller publishes the result.
static func _capture_snapshot() -> Dictionary:
	var captured: Dictionary = {}
	if OS.get_name() == "Windows":
		_collect_windows_snapshot(captured)
	else:
		_collect_posix_snapshot(captured)
	return captured


## Atomically swaps the captured map into the cache.
static func _publish_snapshot(captured: Dictionary) -> void:
	_mutex.lock()
	_pids_by_name = captured
	_snapshot_msec = Time.get_ticks_msec()
	_mutex.unlock()


## ONE `tasklist /FO CSV /NH` snapshot for ALL processes (never one spawn per name).
static func _collect_windows_snapshot(target: Dictionary) -> void:
	var output: Array = []
	var exit_code := OS.execute("tasklist", ["/FO", "CSV", "/NH"], output, true, false)
	if exit_code != 0:
		return
	for chunk: String in output:
		for line in chunk.split("\n", false):
			_parse_windows_csv_line(line, target)


static func _parse_windows_csv_line(line: String, target: Dictionary) -> void:
	# Columns: "Image Name","PID","Session Name","Session#","Mem Usage"
	# Split capped to the first two fields: the rest of the line is never used.
	var cols := line.split(",", true, 2)
	if cols.size() < 2:
		return
	var raw_name: String = cols[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
	var name := raw_name.to_lower()
	if not name.ends_with(".exe"):
		return
	var raw_pid: String = cols[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
	if not raw_pid.is_valid_int():
		return
	var pid := raw_pid.to_int()
	if pid <= 0:
		return
	if not target.has(name):
		target[name] = []
	(target[name] as Array).append(pid)


## Best-effort POSIX fallback (single `ps` spawn): keeps parity with the old
## per-name tasklist behavior on non-Windows platforms.
static func _collect_posix_snapshot(target: Dictionary) -> void:
	var output: Array = []
	var exit_code := OS.execute("ps", ["-axo", "pid=,comm="], output, true, false)
	if exit_code != 0:
		return
	for chunk: String in output:
		for line in chunk.split("\n", false):
			var cols := line.strip_edges().split(" ", false)
			if cols.size() < 2:
				continue
			var raw_pid: String = cols[0]
			var comm := String(cols[1]).to_lower()
			if not raw_pid.is_valid_int():
				continue
			var pid := raw_pid.to_int()
			if pid <= 0:
				continue
			if not target.has(comm):
				target[comm] = []
			(target[comm] as Array).append(pid)


## IMPORTANT: filter to PROCESS_NAMES only — _pids_by_name holds the FULL
## system process list (explorer.exe, svchost.exe, hundreds of entries).
## Iterating all keys would cause _any_pid_alive to always return true because
## system processes never die, making wait_until_all_dead always time out.
static func _collect_known_pids_locked() -> Array:
	var pids: Array = []
	for name in PROCESS_NAMES:
		var name_lower := name.to_lower()
		if _pids_by_name.has(name_lower):
			pids.append_array(_pids_by_name[name_lower])
	return pids


static func _any_pid_alive(pids: Array) -> bool:
	for pid_v in pids:
		var pid := int(pid_v)
		if pid > 0 and OS.is_process_running(pid):
			return true
	return false

#endregion
