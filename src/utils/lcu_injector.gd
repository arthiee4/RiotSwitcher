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

enum State {
	IDLE,
	POLLING_LOCKFILE,
	INJECTING,
	DONE
}

const MAX_POLL_ATTEMPTS := 80 # 80 * 2.0s = 160s timeout
const POLL_INTERVAL_SEC := 2.0

## Hard deadline for each HTTP exchange (connect + request + response).
const HTTP_STEP_TIMEOUT_SEC := 8.0
## Body chunks drained per rendered frame (bounded: never stalls a frame).
const MAX_BODY_CHUNKS_PER_FRAME := 256
const LCU_HOST := "127.0.0.1"

# Injection pipeline steps.
const STEP_READY_SUMMONER := 0
const STEP_READY_FALLBACK := 1
const STEP_PATCH := 2
const STEP_SAVE := 3
const STEP_RELOAD := 4
const STEP_FINISH := 5

var _state: State = State.IDLE
var _polling_timer: Timer = null

var _league_dir: String = ""
var _persisted_settings_path: String = ""
var _attempts: int = 0
var _active_port: int = 0
var _active_token: String = ""
var _active_pid: int = 0
var _lcu_payload: Dictionary = {}
var _payload_json: String = ""

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
	_payload_json = JSON.stringify(_lcu_payload)

	# Remove the temp file written by previous curl-based builds; the payload now
	# travels in memory straight into the PATCH body.
	var legacy_tmp := AppPaths.SHARED_GAME_SETTINGS_DIR.path_join("lcu_payload_tmp.json")
	if FileAccess.file_exists(legacy_tmp):
		DirAccess.remove_absolute(legacy_tmp)

	_state = State.POLLING_LOCKFILE
	_polling_timer.start()
	print("[GameSettings/LCU] Watchdog ativo para injetar configuracoes no League Client em: ", _league_dir)


## Stops any active injection or watchdog.
func stop() -> void:
	_state = State.IDLE
	_active_port = 0
	_active_token = ""
	_active_pid = 0
	_teardown_http()
	if _polling_timer and is_instance_valid(_polling_timer):
		_polling_timer.stop()


func _on_tick() -> void:
	if _state != State.POLLING_LOCKFILE:
		return

	_attempts += 1
	if _attempts > MAX_POLL_ATTEMPTS:
		print("[GameSettings/LCU] Tempo limite atingido aguardando League Client.")
		stop()
		injection_finished.emit(false)
		return

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

	# Verify the process is actually alive to avoid a dead lockfile from a
	# closed session. In-process check: no tasklist spawn, no blocking.
	if not RiotProcesses.is_pid_alive(pid):
		return

	_active_pid = pid
	_active_port = port
	_active_token = token
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
	var err := _http.connect_to_host(LCU_HOST, _active_port, _http_tls)
	if err != OK:
		printerr("[GameSettings/LCU] Failed to start connection to LCU API (error %d)." % err)
		_return_to_polling()


func _process(delta: float) -> void:
	if _state != State.INJECTING or _http == null or _http_step < 0:
		return

	# Inter-step settle delay (replaces the old blocking OS.delay_msec calls).
	# The client keeps being polled during the pause so a reconnect started
	# between steps can finish while we wait — otherwise the next step would
	# tear it down and connect a second time for the same exchange.
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
		if _http.read_response_body_chunk().is_empty():
			return


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
		pass # Connect still in progress: _process() keeps polling it.
	else:
		# Connection dropped between steps (or the previous connect failed):
		# open a fresh one for the next exchange.
		_reconnect()


func _send_step_request() -> void:
	if _http_step == STEP_FINISH:
		_finish_injection()
		return

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
		STEP_READY_FALLBACK:
			path = "/lol-game-settings/v1/game-settings"
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
			# Unknown step: nothing left to send.
			_finish_injection()
			return

	var err := _http.request(method, path, headers, body)
	if err != OK:
		printerr("[GameSettings/LCU] HTTP request failed to start (error %d)." % err)
		_fail_step("request_error")
		return
	_http_request_sent = true
	_http_got_headers = false
	_http_elapsed = 0.0


func _complete_step(code: int) -> void:
	match _http_step:
		STEP_READY_SUMMONER:
			if code == 200:
				print("[GameSettings/LCU] League Client 100%% conectado e logado (HTTP %d na porta %d). Injetando configuracoes..." % [code, _active_port])
				_advance_step(STEP_PATCH, 250) # Breathing room for LCU schema initialization
			else:
				# Still logging in: probe the game-settings endpoint as fallback.
				_advance_step(STEP_READY_FALLBACK, 0)
		STEP_READY_FALLBACK:
			if code == 200 or code == 204:
				print("[GameSettings/LCU] League Client 100%% conectado e logado (HTTP %d na porta %d). Injetando configuracoes..." % [code, _active_port])
				_advance_step(STEP_PATCH, 250)
			else:
				# League Client is still starting or logging in; retry on next tick.
				_return_to_polling()
		STEP_PATCH:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] PATCH game-settings respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_SAVE, 150) # Settle memory state
		STEP_SAVE:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] POST save respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_RELOAD, 150) # Allow cloud sync negotiation
		STEP_RELOAD:
			if code != 200 and code != 204:
				printerr("[GameSettings/LCU] POST reload-post-game respondeu HTTP %d (esperado 200/204)." % code)
			_advance_step(STEP_FINISH, 100) # Settle engine reload


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
	if _http_step == STEP_READY_SUMMONER or _http_step == STEP_READY_FALLBACK:
		# League Client is still starting or logging in: fall back to lockfile
		# polling and retry on the next tick.
		_return_to_polling()
		return
	# Mutation steps are best-effort (same policy as the previous curl client):
	# log the failure and continue the sequence on a fresh connection.
	printerr("[GameSettings/LCU] Falha de conexao no passo %d (%s); continuando sequencia." % [_http_step, reason])
	_advance_step(_http_step + 1, 100)


func _return_to_polling() -> void:
	_teardown_http()
	_state = State.POLLING_LOCKFILE


func _finish_injection() -> void:
	# 5. Overwrite live input.ini and PersistedSettings.json directly on disk
	# to ensure instant in-game match application.
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
	_teardown_http()
	stop()
	injection_finished.emit(true)


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
