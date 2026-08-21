# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name ConfigProxy
extends RefCounted

## Local HTTP server that intercepts Riot Client configuration requests and patches chat host/port.

signal chat_host_discovered(host: String, port: int)

var _server: TCPServer = null
var _port: int = 0
var _target_chat_port: int = 0
var _active_connections: Array[Dictionary] = [] # Array of { peer: StreamPeerTCP, buffer: PackedByteArray, http_req: HTTPRequest, created_at: int }
var _owner_node: Node = null

const HTTP_CONNECTION_TIMEOUT_MS := 15000


func _init(owner_node: Node) -> void:
	_owner_node = owner_node
	_server = TCPServer.new()


## Starts the local HTTP config listener on an ephemeral port.
func start(target_chat_port: int) -> Error:
	_target_chat_port = target_chat_port
	var err := _server.listen(0, PresenceConstants.LOCALHOST_IP)
	if err != OK:
		printerr("[Presence/ConfigProxy] Failed to listen on localhost. Error: ", err)
		return err

	_port = _server.get_local_port()
	print("[Presence/ConfigProxy] HTTP Config Server listening on 127.0.0.1:%d (forwarding to ChatProxy port %d)" % [_port, _target_chat_port])
	return OK


## Stops the server and closes all active client connections.
func stop() -> void:
	for conn in _active_connections:
		if conn.has("peer") and conn.peer != null:
			var peer: StreamPeerTCP = conn.peer
			peer.disconnect_from_host()
		if conn.has("http_req") and conn.http_req != null and is_instance_valid(conn.http_req):
			conn.http_req.queue_free()
	_active_connections.clear()

	if _server != null and _server.is_listening():
		_server.stop()
		print("[Presence/ConfigProxy] Stopped listening on port %d." % _port)
	_port = 0


func get_port() -> int:
	return _port


## Polled each frame by PresenceManager
func poll() -> void:
	if _server == null or not _server.is_listening():
		return

	var now := Time.get_ticks_msec()

	# Accept new incoming HTTP connections
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_active_connections.append({
				"peer": peer,
				"buffer": PackedByteArray(),
				"http_req": null,
				"request_sent": false,
				"created_at": now
			})

	# Process existing connections
	var remaining_connections: Array[Dictionary] = []
	for conn in _active_connections:
		var peer: StreamPeerTCP = conn.peer
		peer.poll()

		var status := peer.get_status()
		var is_timeout: bool = (now - conn.created_at) > HTTP_CONNECTION_TIMEOUT_MS

		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE or is_timeout:
			if conn.http_req and is_instance_valid(conn.http_req):
				conn.http_req.queue_free()
			peer.disconnect_from_host()
			continue

		var available_bytes := peer.get_available_bytes()
		if available_bytes > 0:
			var chunk := peer.get_partial_data(available_bytes)
			if chunk[0] == OK:
				conn.buffer.append_array(chunk[1])

		# Check if we have received complete HTTP headers (\r\n\r\n)
		var req_text := (conn.buffer as PackedByteArray).get_string_from_utf8()
		if not conn.request_sent and req_text.contains("\r\n\r\n"):
			conn.request_sent = true
			_handle_http_request(conn, req_text)

		# Keep connection if not finished
		if conn.has("done") and conn.done:
			peer.disconnect_from_host()
			if conn.http_req and is_instance_valid(conn.http_req):
				conn.http_req.queue_free()
		else:
			remaining_connections.append(conn)

	_active_connections = remaining_connections


func _handle_http_request(conn: Dictionary, req_text: String) -> void:
	var lines := req_text.split("\r\n")
	if lines.is_empty():
		_send_http_error(conn, 400, "Bad Request")
		return

	var first_line := lines[0].split(" ")
	if first_line.size() < 2:
		_send_http_error(conn, 400, "Bad Request")
		return

	var method := first_line[0]
	var path := first_line[1]

	# Sanitize path: strip absolute URL scheme/host if client sends proxy-style URLs
	if path.begins_with("http://") or path.begins_with("https://"):
		var slash_pos := path.find("/", 8)
		if slash_pos != -1:
			path = path.substr(slash_pos)
		else:
			path = "/"

	# Build upstream URL
	var target_url := PresenceConstants.RIOT_CLIENT_CONFIG_BASE_URL + path
	print("[Presence/ConfigProxy] Intercepted %s %s -> Forwarding to %s" % [method, path, target_url])

	var http_req := HTTPRequest.new()
	conn.http_req = http_req
	if _owner_node != null and is_instance_valid(_owner_node):
		_owner_node.add_child(http_req)

	# Extract relevant headers
	var custom_headers: PackedStringArray = []
	for i in range(1, lines.size()):
		var line := lines[i]
		if line.is_empty():
			break
		var lower_line := line.to_lower()
		if not lower_line.begins_with("host:") and not lower_line.begins_with("connection:"):
			custom_headers.append(line)

	custom_headers.append("Host: clientconfig.rpg.riotgames.com")
	custom_headers.append("Connection: close")

	http_req.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		_on_upstream_completed(conn, result, response_code, headers, body)
	)

	var err := http_req.request(target_url, custom_headers, HTTPClient.METHOD_GET)
	if err != OK:
		printerr("[Presence/ConfigProxy] Upstream request failed with error: ", err)
		_send_http_error(conn, 502, "Bad Gateway")


func _on_upstream_completed(conn: Dictionary, result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		printerr("[Presence/ConfigProxy] Upstream HTTP fetch failed. Result code: ", result)
		_send_http_error(conn, 502, "Bad Gateway")
		return

	var body_text := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_err := json.parse(body_text)

	if parse_err != OK or not (json.data is Dictionary):
		# If not JSON, forward raw body intact
		_send_http_response(conn, response_code, "application/json", body)
		return

	var config_dict: Dictionary = json.data
	_patch_client_config(config_dict)

	var patched_json_str := JSON.stringify(config_dict)
	var patched_body := patched_json_str.to_utf8_buffer()

	print("[Presence/ConfigProxy] Successfully patched Riot Client Config with local ChatProxy port %d." % _target_chat_port)
	_send_http_response(conn, response_code, "application/json", patched_body)


func _patch_client_config(config: Dictionary) -> void:
	# 1. Extract original regional chat host before patching
	var orig_host: String = ""
	var orig_port: int = PresenceConstants.DEFAULT_RIOT_CHAT_PORT
	if config.has("chat.host") and config["chat.host"] is String:
		orig_host = config["chat.host"]
	if config.has("chat.port") and (config["chat.port"] is int or config["chat.port"] is float):
		orig_port = int(config["chat.port"])

	if not orig_host.is_empty() and orig_host != PresenceConstants.DECEIVE_LOCALHOST_DOMAIN and orig_host != PresenceConstants.LOCALHOST_IP:
		print("[Presence/ConfigProxy] Discovered upstream Riot chat host: %s:%d" % [orig_host, orig_port])
		chat_host_discovered.emit(orig_host, orig_port)

	# 2. Patch top-level chat properties to point to local proxy
	config["chat.host"] = PresenceConstants.DECEIVE_LOCALHOST_DOMAIN
	config["chat.port"] = _target_chat_port
	config["chat.allow_bad_cert.enabled"] = true
	config["chat.use_tls.enabled"] = true

	# 3. Patch chat affinities to force local connection
	if config.has("chat.affinities") and config["chat.affinities"] is Dictionary:
		var affinities: Dictionary = config["chat.affinities"]
		for key in affinities.keys():
			affinities[key] = PresenceConstants.DECEIVE_LOCALHOST_DOMAIN
		config["chat.affinities"] = affinities


func _send_http_response(conn: Dictionary, status_code: int, content_type: String, body: PackedByteArray) -> void:
	var peer: StreamPeerTCP = conn.peer
	var header := "HTTP/1.1 %d OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n" % [
		status_code,
		content_type,
		body.size()
	]
	peer.put_data(header.to_utf8_buffer())
	if not body.is_empty():
		peer.put_data(body)
	conn.done = true


func _send_http_error(conn: Dictionary, status_code: int, message: String) -> void:
	var body := message.to_utf8_buffer()
	var peer: StreamPeerTCP = conn.peer
	var header := "HTTP/1.1 %d %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status_code,
		message,
		body.size()
	]
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)
	conn.done = true
