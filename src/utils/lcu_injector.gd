class_name LcuInjector
extends Node

## LCU (League Client Update) REST API Injector.
## Continuously watches for active LeagueClientUx process, connects via local REST API,
## pushes game settings & hotkeys from the master snapshot into the active account's
## memory, and triggers Riot Cloud synchronization.

signal injection_finished(success: bool)

enum State {
	IDLE,
	POLLING_LOCKFILE,
	INJECTING,
	DONE
}

var _state: State = State.IDLE
var _polling_timer: Timer = null

var _league_dir: String = ""
var _persisted_settings_path: String = ""
var _attempts: int = 0
var _active_port: int = 0
var _active_token: String = ""
var _active_pid: int = 0
var _lcu_payload: Dictionary = {}
var _payload_tmp_path: String = ""

const MAX_POLL_ATTEMPTS := 80 # 80 * 2.0s = 160s timeout
const POLL_INTERVAL_SEC := 2.0


func _ready() -> void:
	_polling_timer = Timer.new()
	_polling_timer.wait_time = POLL_INTERVAL_SEC
	_polling_timer.one_shot = false
	_polling_timer.timeout.connect(_on_tick)
	add_child(_polling_timer)


## Starts watching for LeagueClient and performs settings injection as soon as it's ready.
func start_injection(league_dir: String, persisted_settings_path: String) -> void:
	stop()
	_league_dir = league_dir
	_persisted_settings_path = persisted_settings_path
	_attempts = 0
	_active_port = 0
	_active_token = ""
	_active_pid = 0
	_lcu_payload = _load_payload()
	if _lcu_payload.is_empty():
		printerr("[GameSettings/LCU] Cannot inject: PersistedSettings payload is empty or invalid.")
		injection_finished.emit(false)
		return

	# Write payload to a temporary file for reliable CLI injection
	_payload_tmp_path = AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("lcu_payload_tmp.json")
	var file := FileAccess.open(_payload_tmp_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_lcu_payload))
		file.close()

	_state = State.POLLING_LOCKFILE
	_polling_timer.start()
	print("[GameSettings/LCU] Watchdog ativo para injetar configuracoes no League Client em: ", _league_dir)


## Stops any active injection or watchdog.
func stop() -> void:
	_state = State.IDLE
	_active_port = 0
	_active_token = ""
	_active_pid = 0
	if _polling_timer and is_instance_valid(_polling_timer):
		_polling_timer.stop()


func _on_tick() -> void:
	if _state == State.IDLE or _state == State.DONE:
		return

	_attempts += 1
	if _attempts > MAX_POLL_ATTEMPTS:
		print("[GameSettings/LCU] Tempo limite atingido aguardando League Client.")
		stop()
		injection_finished.emit(false)
		return

	match _state:
		State.POLLING_LOCKFILE:
			_poll_lockfile()


func _poll_lockfile() -> void:
	var lockfile_path := _league_dir.path_join("lockfile")
	if not FileAccess.file_exists(lockfile_path):
		return

	var content := FileAccess.get_file_as_string(lockfile_path).strip_edges()
	var parts := content.split(":")
	if parts.size() < 4 or parts[0] != "LeagueClient":
		return

	var pid := int(parts[1])
	var port := int(parts[2])
	var token := parts[3]
	if pid <= 0 or port <= 0 or token.is_empty():
		return

	# Verify the process is actually alive to avoid dead lockfile from a closed session
	if not _is_pid_alive(pid):
		return

	_active_pid = pid
	_active_port = port
	_active_token = token
	_state = State.INJECTING
	_perform_injection()


func _perform_injection() -> void:
	var auth := "riot:%s" % _active_token
	var base_url := "https://127.0.0.1:%d" % _active_port
	var global_payload_path := ProjectSettings.globalize_path(_payload_tmp_path).replace("/", "\\")

	# 1. Test readiness: wait until Summoner session is 100% loaded so old cloud data is not downloading
	var test_out: Array = []
	var test_exit := OS.execute("curl.exe", ["-k", "-s", "-o", "NUL", "-w", "%{http_code}", "-u", auth, base_url + "/lol-summoner/v1/current-summoner"], test_out, true, false)
	var http_code: String = str(test_out[0]).strip_edges() if test_out.size() > 0 else ""
	if test_exit != 0 or http_code != "200":
		# Fallback check on /lol-game-settings/v1/game-settings
		var gs_out: Array = []
		var gs_exit := OS.execute("curl.exe", ["-k", "-s", "-o", "NUL", "-w", "%{http_code}", "-u", auth, base_url + "/lol-game-settings/v1/game-settings"], gs_out, true, false)
		var gs_code: String = str(gs_out[0]).strip_edges() if gs_out.size() > 0 else ""
		if gs_exit != 0 or (gs_code != "200" and gs_code != "204"):
			# League Client is still starting or logging in; retry on next tick
			_state = State.POLLING_LOCKFILE
			return

	print("[GameSettings/LCU] League Client 100% conectado e logado (HTTP %s na porta %d). Injetando configuracoes..." % [http_code if http_code == "200" else "200", _active_port])
	OS.delay_msec(250) # Breathing room for LCU to complete internal schema initialization

	# 2. PATCH game-settings
	var patch_out: Array = []
	var patch_exit := OS.execute("curl.exe", ["-k", "-s", "-X", "PATCH", "-u", auth, "-H", "Content-Type: application/json", "--data-binary", "@" + global_payload_path, base_url + "/lol-game-settings/v1/game-settings"], patch_out, true, false)
	OS.delay_msec(150) # Settle memory state

	# 3. POST save (forces Riot Cloud sync for active account)
	var save_out: Array = []
	OS.execute("curl.exe", ["-k", "-s", "-X", "POST", "-u", auth, "-H", "Content-Type: application/json", "-d", "{}", base_url + "/lol-game-settings/v1/save"], save_out, true, false)
	OS.delay_msec(150) # Allow cloud sync negotiation

	# 4. POST reload-post-game (reloads into active game engine)
	var reload_out: Array = []
	OS.execute("curl.exe", ["-k", "-s", "-X", "POST", "-u", auth, "-H", "Content-Type: application/json", "-d", "{}", base_url + "/lol-game-settings/v1/reload-post-game"], reload_out, true, false)
	OS.delay_msec(100) # Settle engine reload

	# 5. Overwrite live input.ini and PersistedSettings.json directly on disk to ensure instant in-game match application
	var live_config := _league_dir.path_join("Config")
	if DirAccess.dir_exists_absolute(live_config):
		var master_input := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("input.ini")
		var target_input := live_config.path_join("input.ini")
		if FileAccess.file_exists(master_input):
			var input_content := FileAccess.get_file_as_string(master_input)
			var fa := FileAccess.open(target_input, FileAccess.WRITE)
			if fa:
				fa.store_string(input_content)
				fa.close()

		var master_persisted := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("PersistedSettings.json")
		var target_persisted := live_config.path_join("PersistedSettings.json")
		if FileAccess.file_exists(master_persisted):
			var persisted_content := FileAccess.get_file_as_string(master_persisted)
			var fa_p := FileAccess.open(target_persisted, FileAccess.WRITE)
			if fa_p:
				fa_p.store_string(persisted_content)
				fa_p.close()

	print("[GameSettings/LCU] SUCESSO: Configuracoes do perfil pai sincronizadas no League Client, disco e nuvem da Riot!")
	_state = State.DONE
	stop()
	injection_finished.emit(true)


func _is_pid_alive(pid: int) -> bool:
	if OS.get_name() != "Windows":
		return true
	var output: Array = []
	var exit_code := OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH"], output, true, false)
	if exit_code == 0 and output.size() > 0:
		var txt: String = output[0]
		return txt.contains(str(pid)) and not txt.contains("No tasks") and not txt.contains("Nenhuma tarefa")
	return false


func _load_payload() -> Dictionary:
	if not FileAccess.file_exists(_persisted_settings_path):
		return {}
	var json_str := FileAccess.get_file_as_string(_persisted_settings_path)
	var json := JSON.new()
	if json.parse(json_str) != OK or not (json.data is Dictionary):
		return {}
	return persisted_settings_to_lcu_dict(json.data)


## Converts PersistedSettings.json schema to LCU Dictionary format:
## { "SectionName": { "SettingName": "Value", ... }, ... }
static func persisted_settings_to_lcu_dict(persisted_json: Dictionary) -> Dictionary:
	var lcu_dict: Dictionary = {}
	if not persisted_json.has("files") or not (persisted_json["files"] is Array):
		return lcu_dict

	for file_entry: Dictionary in persisted_json["files"]:
		if not file_entry.has("sections") or not (file_entry["sections"] is Array):
			continue
		for section: Dictionary in file_entry["sections"]:
			var section_name: String = section.get("name", "")
			if section_name.is_empty():
				continue
			if not lcu_dict.has(section_name):
				lcu_dict[section_name] = {}
			if section.has("settings") and (section["settings"] is Array):
				for setting: Dictionary in section["settings"]:
					var k: String = setting.get("name", "")
					var v: Variant = setting.get("value", "")
					if not k.is_empty():
						lcu_dict[section_name][k] = v
	return lcu_dict


## Triggers POST /lol-game-settings/v1/save on the active League Client to sync with Riot Cloud.
static func trigger_cloud_save(league_dir: String) -> bool:
	if league_dir.is_empty():
		return false
	var lockfile_path := league_dir.path_join("lockfile")
	if not FileAccess.file_exists(lockfile_path):
		return false
	var content := FileAccess.get_file_as_string(lockfile_path).strip_edges()
	var parts := content.split(":")
	if parts.size() < 4 or parts[0] != "LeagueClient":
		return false
	var port := int(parts[2])
	var token := parts[3]
	if port <= 0 or token.is_empty():
		return false

	var auth := "riot:%s" % token
	var base_url := "https://127.0.0.1:%d" % port
	var save_out: Array = []
	var exit_code := OS.execute("curl.exe", ["-k", "-s", "-X", "POST", "-u", auth, "-H", "Content-Type: application/json", "-d", "{}", base_url + "/lol-game-settings/v1/save"], save_out, true, false)
	return exit_code == 0
