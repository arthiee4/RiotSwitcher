class_name RiotProcesses
extends RefCounted

# Riot process detection and management.

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


# Sends a single non-blocking taskkill for every known process.
static func kill_all() -> void:
	var arguments: Array[String] = ["/F", "/T"]
	for process_name in PROCESS_NAMES:
		arguments.append("/IM")
		arguments.append(process_name)
	var pid := OS.create_process("taskkill", arguments)
	if pid < 0:
		printerr("RiotProcesses: Failed to start taskkill.")


# Returns true while any known process is still running.
static func are_any_running() -> bool:
	for process_name in PROCESS_NAMES:
		var output: Array = []
		var exit_code := OS.execute("tasklist", ["/FI", "IMAGENAME eq %s" % process_name, "/NH"], output)
		if exit_code == 0 and not output.is_empty():
			var listing: String = output[0]
			if listing.to_lower().contains(process_name.to_lower()):
				return true
	return false


# Polls until every known process is gone or the timeout elapses.
static func wait_until_all_dead(timeout_ms := KILL_TIMEOUT_MS) -> bool:
	var elapsed := 0
	while elapsed < timeout_ms:
		if not are_any_running():
			return true
		OS.delay_msec(POLL_INTERVAL_MS)
		elapsed += POLL_INTERVAL_MS
	printerr("RiotProcesses: Timed out waiting for processes to exit.")
	return false
