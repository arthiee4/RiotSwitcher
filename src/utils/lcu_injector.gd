class_name LcuInjector
extends Node

## LCU (League Client Update) REST API Injector.
## Continuously watches for an active LeagueClientUx process, connects to the local
## REST API, pushes game settings & hotkeys from the master snapshot into the active
## account's memory, and triggers Riot Cloud synchronization.
##
## All LCU traffic rides the engine-native HTTPClient over a single TLS keep-alive
## connection (TLSOptions.client_unsafe() — the LCU self-signed loopback certificate
## is trusted by design on 127.0.0.1, equivalent to the previous "curl -k").
## Nothing spawns curl.exe and nothing blocks the main thread: the request pipeline
## is polled from _process(), so the UI keeps full frame rate even while the League
## Client is still booting.

signal injection_finished(success: bool)
signal summoner_stats_fetched(stats: Dictionary)

enum State {
	IDLE,
	POLLING_LOCKFILE,
	INJECTING,
}

const POLL_INTERVAL_SEC := 2.0
const IDLE_PING_INTERVAL_MSEC := 60000 # 60 seconds ping when sitting in lobby

## Hard deadline for each HTTP exchange (connect + request + response).
const HTTP_STEP_TIMEOUT_SEC := 8.0
## Body chunks drained per rendered frame (bounded: never stalls a frame).
const MAX_BODY_CHUNKS_PER_FRAME := 256
const LCU_HOST := "127.0.0.1"

# Injection pipeline steps.
const STEP_READY_SUMMONER := 0
const STEP_FETCH_RANKED := 1
const STEP_FETCH_CHAT_ME := 2
const STEP_PATCH := 3
const STEP_SAVE := 4
const STEP_RELOAD := 5
const STEP_FINISH := 6

var _state: State = State.IDLE
var _polling_timer: Timer = null
var _captured_stats: Dictionary = {}
var _response_buffer := PackedByteArray()

var _league_dir: String = ""
var _persisted_settings_path: String = ""
var _active_port: int = 0
var _active_token: String = ""
var _active_pid: int = 0
var _lcu_payload: Dictionary = {}
var _payload_json: String = ""

var _stats_captured: bool = false
var _settings_injected: bool = false
var _was_in_game: bool = false
var _last_ping_msec: int = 0

# --- Async HTTP pipeline state (driven from _process) ---
var _http: HTTPClient = null
var _http_tls: TLSOptions = null
var _http_step: int = -1
var _http_connected := false
var _http_request_sent := false
var _http_got_headers := false
var _http_last_code := 0
var _http_elapsed := 0.0
var _http_wait_left := 0.0

## Single shared poster for fire-and-forget cloud saves (child of the scene root).
static var _cloud_saver: Node = null


func _ready() -> void:
	_polling_timer = Timer.new()
	_polling_timer.wait_time = POLL_INTERVAL_SEC
	_polling_timer.one_shot = false
	_polling_timer.timeout.connect(_on_tick)
	add_child(_polling_timer)
	# Register the cloud-save poster on the main thread as early as possible so
	# worker threads can dispatch to it later.
	_get_cloud_saver()


func _exit_tree() -> void:
	stop()


## Starts watching for LeagueClient. Continuously monitors live summoner stats and,
## if a persisted settings path is provided, injects shared game settings.
func start_injection(league_dir: String, persisted_settings_path: String = "") -> void:
	stop()
	_league_dir = league_dir
	_persisted_settings_path = persisted_settings_path
	_active_port = 0
	_active_token = ""
	_active_pid = 0
	_stats_captured = false
	_settings_injected = false
	_was_in_game = false
	_last_ping_msec = 0
	_captured_stats.clear()
	_response_buffer.clear()

	if not _persisted_settings_path.is_empty():
		_lcu_payload = _load_payload()
		_payload_json = JSON.stringify(_lcu_payload) if not _lcu_payload.is_empty() else ""
	else:
		_lcu_payload = {}
		_payload_json = ""

	# Remove legacy temp file if present
	var legacy_tmp := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("lcu_payload_tmp.json")
	if FileAccess.file_exists(legacy_tmp):
		DirAccess.remove_absolute(legacy_tmp)

	_state = State.POLLING_LOCKFILE
	_polling_timer.start()
	print("[LCU/Watchdog] Watchdog ativo em: ", _league_dir)


## Stops any active injection or watchdog.
func stop() -> void:
	_state = State.IDLE
	_active_port = 0
	_active_token = ""
	_active_pid = 0
	_stats_captured = false
	_settings_injected = false
	_was_in_game = false
	_last_ping_msec = 0
	_teardown_http()
	if _polling_timer and is_instance_valid(_polling_timer):
		_polling_timer.stop()


func _on_tick() -> void:
	if _state == State.IDLE or _league_dir.is_empty():
		return

	# 1. In-game match pause: pause all HTTP pings during active match
	var in_game: bool = RiotProcesses.is_running("LeagueofLegends.exe")
	if in_game:
		_was_in_game = true
		return

	if _was_in_game and not in_game:
		# Player just finished a match and returned to the lobby!
		print("[LCU/Watchdog] Partida encerrada. Atualizando estatisticas...")
		_was_in_game = false
		_stats_captured = false # Force immediate refresh

	# 2. Check lockfile on disk
	var lockfile_path := _league_dir.path_join("lockfile")
	if not FileAccess.file_exists(lockfile_path):
		if _active_pid > 0:
			_active_pid = 0
			_active_port = 0
			_active_token = ""
			_stats_captured = false
			_settings_injected = false
			_teardown_http()
		return

	# 3. Read lockfile
	var content := FileAccess.get_file_as_string(lockfile_path).strip_edges()
	var parts := content.split(":")
	if parts.size() < 4 or parts[0] != "LeagueClient":
		return

	var pid := int(parts[1])
	var port := int(parts[2])
	var token := parts[3]
	if pid <= 0 or port <= 0 or token.is_empty():
		return

	_active_pid = pid
	_active_port = port
	_active_token = token

	# 4. If an HTTP request sequence is already in flight, let _process continue
	if _state == State.INJECTING:
		return

	# 5. Check if we need to fetch stats or ping
	var now_ms := Time.get_ticks_msec()
	var needs_stats: bool = not _stats_captured
	var needs_settings: bool = not _payload_json.is_empty() and not _settings_injected
	var needs_ping: bool = _stats_captured and (now_ms - _last_ping_msec > IDLE_PING_INTERVAL_MSEC)

	if needs_stats or needs_settings or needs_ping:
		_state = State.INJECTING
		_begin_injection()


func _begin_injection() -> void:
	_http = HTTPClient.new()
	_http_tls = TLSOptions.client_unsafe() # LCU self-signed cert on loopback
	_http_step = STEP_READY_SUMMONER
	_http_connected = false
	_http_request_sent = false
	_http_got_headers = false
	_http_last_code = 0
	_http_elapsed = 0.0
	_http_wait_left = 0.0
	_captured_stats.clear()
	var err := _http.connect_to_host(LCU_HOST, _active_port, _http_tls)
	if err != OK:
		printerr("[LCU/Watchdog] Failed to start connection to LCU API (error %d)." % err)
		_return_to_polling()


func _process(delta: float) -> void:
	if _state != State.INJECTING or _http == null or _http_step < 0:
		return

	# Inter-step settle delay
	if _http_wait_left > 0.0:
		_http_wait_left -= delta
		var wait_status := _http.get_status()
		if wait_status == HTTPClient.STATUS_RESOLVING or wait_status == HTTPClient.STATUS_CONNECTING:
			_http.poll()
		if _http_wait_left <= 0.0:
			_ensure_connection_ready()
		return

	_http_elapsed += delta
	if _http_elapsed > HTTP_STEP_TIMEOUT_SEC:
		_fail_step("timeout")
		return

	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass # Still handshaking/sending; poll again next frame.
		HTTPClient.STATUS_CONNECTED:
			if _http_request_sent and _http_got_headers:
				# Previous response completed on the keep-alive connection.
				_complete_step(_http_last_code)
			elif not _http_request_sent:
				_http_connected = true
				_send_step_request()
		HTTPClient.STATUS_BODY:
			if not _http_got_headers:
				_http_got_headers = true
				_http_last_code = _http.get_response_code()
			_drain_response_body()
		HTTPClient.STATUS_DISCONNECTED:
			if _http_request_sent and _http_got_headers:
				# Response finished but the server closed the connection.
				_complete_step(_http_last_code)
			else:
				_fail_step("disconnected")
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE:
			_fail_step("cant_connect")
		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail_step("connection_error")


func _drain_response_body() -> void:
	for _i in range(MAX_BODY_CHUNKS_PER_FRAME):
		if _http == null or _http.get_status() != HTTPClient.STATUS_BODY:
			return
		var chunk := _http.read_response_body_chunk()
		if chunk.is_empty():
			return
		_response_buffer.append_array(chunk)


func _ensure_connection_ready() -> void:
	if _http == null or _http_step < 0 or _http_request_sent:
		return
	if _http_step == STEP_FINISH:
		_finish_injection()
		return
	var status := _http.get_status()
	if status == HTTPClient.STATUS_CONNECTED:
		_http_connected = true
		_send_step_request()
	elif status == HTTPClient.STATUS_RESOLVING or status == HTTPClient.STATUS_CONNECTING:
		pass
	else:
		_reconnect()


func _send_step_request() -> void:
	if _http_step == STEP_FINISH:
		_finish_injection()
		return

	_response_buffer.clear()
	var auth_b64 := Marshalls.raw_to_base64(("riot:%s" % _active_token).to_utf8_buffer())
	var headers := PackedStringArray([
		"Authorization: Basic " + auth_b64,
		"Accept: application/json",
	])
	var method := HTTPClient.METHOD_GET
	var path := ""
	var body := ""
	match _http_step:
		STEP_READY_SUMMONER:
			path = "/lol-summoner/v1/current-summoner"
		STEP_FETCH_RANKED:
			path = "/lol-ranked/v1/current-ranked-stats"
		STEP_FETCH_CHAT_ME:
			path = "/lol-chat/v1/me"
		STEP_PATCH:
			method = HTTPClient.METHOD_PATCH
			path = "/lol-game-settings/v1/game-settings"
			headers.append("Content-Type: application/json")
			body = _payload_json
		STEP_SAVE:
			method = HTTPClient.METHOD_POST
			path = "/lol-game-settings/v1/save"
			headers.append("Content-Type: application/json")
			body = "{}"
		STEP_RELOAD:
			method = HTTPClient.METHOD_POST
			path = "/lol-game-settings/v1/reload-post-game"
			headers.append("Content-Type: application/json")
			body = "{}"
		_:
			_finish_injection()
			return

	var err := _http.request(method, path, headers, body)
	if err != OK:
		printerr("[LCU/Watchdog] HTTP request failed to start (error %d)." % err)
		_fail_step("request_error")
		return
	_http_request_sent = true
	_http_got_headers = false
	_http_elapsed = 0.0


func _complete_step(code: int) -> void:
	match _http_step:
		STEP_READY_SUMMONER:
			if code == 200:
				print("[LCU/Watchdog] League Client conectado e autenticado (HTTP %d na porta %d)." % [code, _active_port])
				_parse_summoner_response()
				_advance_step(STEP_FETCH_RANKED, 100)
			else:
				# Client is still at login screen or starting up; retry on next watchdog tick
				_return_to_polling()
		STEP_FETCH_RANKED:
			if code == 200:
				_parse_ranked_response()
				var tier: String = str(_captured_stats.get("rank_tier", "UNRANKED"))
				if tier == "UNRANKED":
					_advance_step(STEP_FETCH_CHAT_ME, 50)
					return
			else:
				_advance_step(STEP_FETCH_CHAT_ME, 50)
				return

			_finish_stats_and_proceed()
		STEP_FETCH_CHAT_ME:
			if code == 200:
				_parse_chat_me_response()
			_finish_stats_and_proceed()
		STEP_PATCH:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] PATCH game-settings respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_SAVE, 150)
		STEP_SAVE:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] POST save respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_RELOAD, 150)
		STEP_RELOAD:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] POST reload-post-game respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_FINISH, 100)


func _finish_stats_and_proceed() -> void:
	if not _captured_stats.is_empty():
		summoner_stats_fetched.emit(_captured_stats.duplicate())
		_stats_captured = true
		_last_ping_msec = Time.get_ticks_msec()

	if not _payload_json.is_empty() and not _settings_injected:
		_advance_step(STEP_PATCH, 150)
	else:
		_advance_step(STEP_FINISH, 50)


func _parse_summoner_response() -> void:
	var body_text := _response_buffer.get_string_from_utf8()
	if body_text.is_empty():
		return
	var json_var = JSON.parse_string(body_text)
	if not json_var is Dictionary:
		return
	var data: Dictionary = json_var
	var g_name := str(data.get("gameName", "")).strip_edges()
	var tag := str(data.get("tagLine", "")).strip_edges()
	var display := str(data.get("displayName", "")).strip_edges()
	var nick := ""
	if not g_name.is_empty() and not tag.is_empty():
		nick = "%s#%s" % [g_name, tag]
	elif not g_name.is_empty():
		nick = g_name
	elif not display.is_empty():
		nick = display

	if not nick.is_empty():
		_captured_stats["summoner_name"] = nick
	var level := int(data.get("summonerLevel", 0))
	if level > 0:
		_captured_stats["summoner_level"] = level
	var icon_id := int(data.get("profileIconId", 0))
	if icon_id > 0:
		_captured_stats["profile_icon_id"] = icon_id
	print("[LCU/Watchdog] Invocador autenticado: %s (Nivel %d)" % [nick, level])


func _parse_ranked_response() -> void:
	var body_text := _response_buffer.get_string_from_utf8()
	if body_text.is_empty():
		return
	var json_var = JSON.parse_string(body_text)
	if not json_var is Dictionary:
		return
	var data: Dictionary = json_var
	var queues = data.get("queues", [])
	var best_queue: Dictionary = {}
	if queues is Array:
		# Priority 1: RANKED_SOLO_5x5
		for q in queues:
			if q is Dictionary and str(q.get("queueType", "")) == "RANKED_SOLO_5x5":
				best_queue = q
				break
		# Priority 2: Fallback to any queue with a valid tier (e.g. RANKED_FLEX_SR)
		if best_queue.is_empty() or str(best_queue.get("tier", "UNRANKED")).to_upper() == "UNRANKED":
			for q in queues:
				if q is Dictionary:
					var t := str(q.get("tier", "")).to_upper()
					if not t.is_empty() and t != "UNRANKED" and t != "NONE" and t != "NA":
						best_queue = q
						break

	var tier := str(best_queue.get("tier", "UNRANKED")).to_upper().strip_edges()
	if tier.is_empty() or tier == "NONE" or tier == "NA":
		tier = "UNRANKED"
	var division := str(best_queue.get("division", "")).to_upper().strip_edges()
	if division == "NA":
		division = ""
	var lp := int(best_queue.get("leaguePoints", 0))

	_captured_stats["rank_tier"] = tier
	_captured_stats["rank_division"] = division
	_captured_stats["rank_lp"] = lp
	print("[LCU/Watchdog] Estatisticas de rank detectadas: %s %s (%d LP)" % [tier, division, lp])


func _parse_chat_me_response() -> void:
	var body_text := _response_buffer.get_string_from_utf8()
	if body_text.is_empty():
		return
	var json_var = JSON.parse_string(body_text)
	if not json_var is Dictionary:
		return
	var data: Dictionary = json_var
	var lol_data = data.get("lol", {})
	if lol_data is Dictionary:
		var tier := str(lol_data.get("rankedLeagueTier", "")).to_upper().strip_edges()
		var division := str(lol_data.get("rankedLeagueDivision", "")).to_upper().strip_edges()
		if not tier.is_empty() and tier != "NONE" and tier != "NA":
			_captured_stats["rank_tier"] = tier
			if division != "NA":
				_captured_stats["rank_division"] = division
			print("[LCU/Watchdog] Rank detectado via chat/me: %s %s" % [tier, division])
		var level_str := str(lol_data.get("level", "0"))
		var level := int(level_str)
		if level > 0 and int(_captured_stats.get("summoner_level", 0)) == 0:
			_captured_stats["summoner_level"] = level


func _advance_step(next_step: int, wait_ms: int) -> void:
	_http_step = next_step
	_http_request_sent = false
	_http_got_headers = false
	_http_last_code = 0
	_http_elapsed = 0.0
	_http_wait_left = float(wait_ms) / 1000.0
	if next_step != STEP_FINISH and _http.get_status() != HTTPClient.STATUS_CONNECTED:
		_reconnect()


func _fail_step(reason: String) -> void:
	if _http_step == STEP_READY_SUMMONER:
		_return_to_polling()
		return
	if _http_step == STEP_FETCH_RANKED:
		_advance_step(STEP_FETCH_CHAT_ME, 50)
		return
	if _http_step == STEP_FETCH_CHAT_ME:
		_finish_stats_and_proceed()
		return
	printerr("[LCU/Watchdog] Falha no passo %d (%s); continuando." % [_http_step, reason])
	_advance_step(_http_step + 1, 100)


func _return_to_polling() -> void:
	_teardown_http()
	_state = State.POLLING_LOCKFILE


func _finish_injection() -> void:
	if not _payload_json.is_empty() and not _settings_injected:
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

		_settings_injected = true
		print("[GameSettings/LCU] SUCESSO: Configuracoes sincronizadas no League Client, disco e nuvem!")
		injection_finished.emit(true)
	else:
		print("[LCU/Watchdog] SUCESSO: Estatisticas sincronizadas com sucesso!")

	_return_to_polling()


func _reconnect() -> void:
	_release_http_client()
	_http = HTTPClient.new()
	_http_tls = TLSOptions.client_unsafe()
	var err := _http.connect_to_host(LCU_HOST, _active_port, _http_tls)
	if err != OK:
		printerr("[GameSettings/LCU] Reconnect failed to start (error %d)." % err)


func _release_http_client() -> void:
	if _http != null:
		_http.close()
		_http = null
	_http_tls = null
	_http_connected = false
	_http_request_sent = false
	_http_got_headers = false
	_http_last_code = 0


func _teardown_http() -> void:
	_release_http_client()
	_http_step = -1
	_http_elapsed = 0.0
	_http_wait_left = 0.0


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


## Triggers POST /lol-game-settings/v1/save on the active League Client to sync
## with Riot Cloud. Fully asynchronous (HTTPClient, TLSOptions.client_unsafe):
## returns true when the request was queued for dispatch on the main thread.
## Safe to call from worker threads (dispatched via thread-safe call_deferred).
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

	var saver := _get_cloud_saver()
	if saver == null or not is_instance_valid(saver):
		return false
	# call_deferred is thread-safe: calls from worker threads land on the main thread.
	saver.call_deferred("enqueue_cloud_save", port, token)
	return true


static func _get_cloud_saver() -> Node:
	if _cloud_saver != null and is_instance_valid(_cloud_saver):
		return _cloud_saver
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		# Never touch the scene tree from a worker thread.
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_cloud_saver = _LcuCloudSaver.new()
	_cloud_saver.name = "_LcuCloudSaver"
	# Deferred: during the main scene setup the root is still adding its own
	# children and would reject a direct add_child().
	tree.root.add_child.call_deferred(_cloud_saver)
	return _cloud_saver


## Fire-and-forget cloud-save poster: keeps one short-lived HTTPClient per job
## and polls it from _process. Never blocks, never spawns external processes.
class _LcuCloudSaver:
	extends Node

	const TIMEOUT_SEC := 5.0
	const MAX_QUEUE := 8

	var _http: HTTPClient = null
	var _tls: TLSOptions = null
	var _queue: Array = []
	var _current_port := 0
	var _current_token := ""
	var _connected := false
	var _request_sent := false
	var _got_headers := false
	var _last_code := 0
	var _elapsed := 0.0


	func enqueue_cloud_save(port: int, token: String) -> void:
		if port <= 0 or token.is_empty():
			return
		# Collapse identical consecutive requests (the watchdog can burst several).
		if not _queue.is_empty():
			var last: Dictionary = _queue[_queue.size() - 1]
			if int(last.get("port", 0)) == port and String(last.get("token", "")) == token:
				return
		_queue.append({"port": port, "token": token})
		if _queue.size() > MAX_QUEUE:
			_queue.pop_front()


	func _process(delta: float) -> void:
		if _http == null:
			if _queue.is_empty():
				return
			_start_next()
			return

		_elapsed += delta
		if _elapsed > TIMEOUT_SEC:
			_discard_current()
			return

		_http.poll()
		match _http.get_status():
			HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
				pass
			HTTPClient.STATUS_CONNECTED:
				if _request_sent and _got_headers:
					_finish_current(_last_code)
				elif not _request_sent:
					_connected = true
					_send_request()
			HTTPClient.STATUS_BODY:
				if not _got_headers:
					_got_headers = true
					_last_code = _http.get_response_code()
				for _i in range(256):
					if _http.get_status() != HTTPClient.STATUS_BODY:
						break
					if _http.read_response_body_chunk().is_empty():
						break
			HTTPClient.STATUS_DISCONNECTED:
				if _request_sent and _got_headers:
					_finish_current(_last_code)
				else:
					_discard_current()
			_:
				_discard_current()


	func _start_next() -> void:
		var job: Dictionary = _queue.pop_front()
		_current_port = int(job.get("port", 0))
		_current_token = String(job.get("token", ""))
		_connected = false
		_request_sent = false
		_got_headers = false
		_last_code = 0
		_elapsed = 0.0
		_http = HTTPClient.new()
		_tls = TLSOptions.client_unsafe()
		_http.connect_to_host(LCU_HOST, _current_port, _tls)


	func _send_request() -> void:
		var auth_b64 := Marshalls.raw_to_base64(("riot:%s" % _current_token).to_utf8_buffer())
		var headers := PackedStringArray([
			"Authorization: Basic " + auth_b64,
			"Accept: application/json",
			"Content-Type: application/json",
		])
		var err := _http.request(HTTPClient.METHOD_POST, "/lol-game-settings/v1/save", headers, "{}")
		if err != OK:
			_discard_current()
			return
		_request_sent = true
		_elapsed = 0.0


	func _finish_current(code: int) -> void:
		if code == 200 or code == 204:
			print("[GameSettings/LCU] Sincronizacao com a nuvem Riot disparada (HTTP %d)." % code)
		else:
			printerr("[GameSettings/LCU] Cloud save respondeu HTTP %d (esperado 200/204)." % code)
		_release_client()
		if not _queue.is_empty():
			_start_next()


	func _discard_current() -> void:
		printerr("[GameSettings/LCU] Cloud save nao entregue (cliente indisponivel ou timeout).")
		_release_client()
		if not _queue.is_empty():
			_start_next()


	func _release_client() -> void:
		if _http != null:
			_http.close()
			_http = null
		_tls = null
		_current_port = 0
		_current_token = ""
		_connected = false
		_request_sent = false
		_got_headers = false
