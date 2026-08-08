class_name RiotProcesses
extends RefCounted

## Single source of truth for Riot-related process management.
## The polling helpers block, so call them from a worker thread,
## never from the main/UI thread.

const PROCESS_NAMES: Array[String] = [
	"RiotClientServices.exe",
	"RiotClientUx.exe",
	"RiotClientUxRender.exe",
	"LeagueClient.exe",
	"LeagueClientUx.exe",
	"LeagueClientUxRender.exe",
	"LeagueofLegends.exe",
]

const KILL_TIMEOUT_MS := 10000
const POLL_INTERVAL_MS := 250


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


## Returns true while the given process is running. Blocking — use from a thread.
static func is_running(process_name: String) -> bool:
	var output: Array = []
	var exit_code := OS.execute("tasklist", ["/FI", "IMAGENAME eq %s" % process_name, "/NH"], output)
	if exit_code == 0 and not output.is_empty():
		var listing: String = output[0]
		if listing.to_lower().contains(process_name.to_lower()):
			return true
	return false


## Returns true while any known process is still running. Blocking — use from a thread.
static func are_any_running() -> bool:
	for process_name in PROCESS_NAMES:
		if is_running(process_name):
			return true
	return false


## Polls until every known process is gone or the timeout elapses.
## Returns true if all processes exited in time. Blocking — use from a thread.
static func wait_until_all_dead(timeout_ms := KILL_TIMEOUT_MS) -> bool:
	var elapsed := 0
	while elapsed < timeout_ms:
		if not are_any_running():
			return true
		OS.delay_msec(POLL_INTERVAL_MS)
		elapsed += POLL_INTERVAL_MS
	printerr("RiotProcesses: Timed out waiting for processes to exit.")
	return false
