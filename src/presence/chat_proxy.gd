# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name ChatProxy
extends RefCounted

## Local TCP/TLS MITM proxy that intercepts XMPP traffic between League/Riot Client and Riot Chat Servers.

var _server: TCPServer = null
var _port: int = 0
var _active_sessions: Array[Dictionary] = [] # Array of active client <-> upstream bridge sessions
var _upstream_host: String = "br.chat.si.riotgames.com"
var _upstream_port: int = PresenceConstants.DEFAULT_RIOT_CHAT_PORT

const HANDSHAKE_TIMEOUT_MS := 20000


func _init() -> void:
	_server = TCPServer.new()


## Starts listening for incoming client XMPP connections.
func start(upstream_host: String = "", upstream_port: int = PresenceConstants.DEFAULT_RIOT_CHAT_PORT) -> Error:
	if not upstream_host.is_empty():
		_upstream_host = upstream_host
	_upstream_port = upstream_port

	var err := _server.listen(0, PresenceConstants.LOCALHOST_IP)
	if err != OK:
		printerr("[Presence/ChatProxy] Failed to listen on localhost. Error: ", err)
		return err

	_port = _server.get_local_port()
	print("[Presence/ChatProxy] XMPP Chat Proxy listening on 127.0.0.1:%d (Upstream: %s:%d)" % [_port, _upstream_host, _upstream_port])
	return OK


## Stops the proxy and closes all open bridge connections.
func stop() -> void:
	for session in _active_sessions:
		_close_session(session)
	_active_sessions.clear()

	if _server != null and _server.is_listening():
		_server.stop()
		print("[Presence/ChatProxy] Stopped listening on port %d." % _port)
	_port = 0


func get_port() -> int:
	return _port


## Sets the dynamic upstream Riot chat host discovered from config.
func set_upstream_target(host: String, port: int = PresenceConstants.DEFAULT_RIOT_CHAT_PORT) -> void:
	if not host.is_empty():
		_upstream_host = host
	if port > 0:
		_upstream_port = port
	print("[Presence/ChatProxy] Updated upstream target to %s:%d" % [_upstream_host, _upstream_port])


## Polled each frame by PresenceManager
func poll() -> void:
	if _server == null or not _server.is_listening():
		return

	# Accept new incoming client TCP connections
	while _server.is_connection_available():
		var raw_client_peer := _server.take_connection()
		if raw_client_peer != null:
			_initiate_session(raw_client_peer)

	# Process active sessions
	var surviving_sessions: Array[Dictionary] = []
	for session in _active_sessions:
		if _poll_session(session):
			surviving_sessions.append(session)
		else:
			_close_session(session)

	_active_sessions = surviving_sessions


func _initiate_session(raw_client: StreamPeerTCP) -> void:
	print("[Presence/ChatProxy] Client connected to local XMPP port. Connecting to upstream Riot chat %s:%d..." % [_upstream_host, _upstream_port])

	var raw_upstream := StreamPeerTCP.new()
	raw_upstream.connect_to_host(_upstream_host, _upstream_port)

	var tls_server_options := CryptoHelper.get_server_tls_options()
	var client_tls := StreamPeerTLS.new()

	var session: Dictionary = {
		"state": "CONNECTING_UPSTREAM",
		"raw_client": raw_client,
		"client_tls": client_tls,
		"tls_server_options": tls_server_options,
		"client_handshake_done": false,
		"raw_upstream": raw_upstream,
		"upstream_tls": StreamPeerTLS.new(),
		"upstream_handshake_done": false,
		"created_at": Time.get_ticks_msec()
	}
	_active_sessions.append(session)


func _poll_session(session: Dictionary) -> bool:
	var raw_client: StreamPeerTCP = session.raw_client
	var raw_upstream: StreamPeerTCP = session.raw_upstream
	var client_tls: StreamPeerTLS = session.client_tls
	var upstream_tls: StreamPeerTLS = session.upstream_tls
	var now := Time.get_ticks_msec()

	# Phase 1: Wait for raw upstream TCP connection
	if session.state == "CONNECTING_UPSTREAM":
		raw_client.poll()
		raw_upstream.poll()

		if raw_client.get_status() == StreamPeerTCP.STATUS_ERROR or raw_client.get_status() == StreamPeerTCP.STATUS_NONE:
			return false
		if raw_upstream.get_status() == StreamPeerTCP.STATUS_ERROR or raw_upstream.get_status() == StreamPeerTCP.STATUS_NONE:
			return false

		if (now - session.created_at) > HANDSHAKE_TIMEOUT_MS:
			printerr("[Presence/ChatProxy] Upstream TCP connection timeout.")
			return false

		if raw_upstream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			# Start TLS handshakes
			var accept_err := client_tls.accept_stream(raw_client, session.tls_server_options)
			var connect_err := upstream_tls.connect_to_stream(raw_upstream, _upstream_host, TLSOptions.client_unsafe())
			if accept_err != OK or connect_err != OK:
				printerr("[Presence/ChatProxy] Failed to initialize TLS streams (Client: %d, Upstream: %d)" % [accept_err, connect_err])
				return false
			session.state = "TLS_HANDSHAKE"
			session.handshake_started_at = now
			print("[Presence/ChatProxy] Upstream TCP connected. Starting dual TLS handshakes...")
		return true

	# Phase 2: Complete TLS Handshakes
	if session.state == "TLS_HANDSHAKE":
		var handshake_start: int = int(session.get("handshake_started_at", session.created_at))
		if (now - handshake_start) > HANDSHAKE_TIMEOUT_MS:
			printerr("[Presence/ChatProxy] TLS handshake timeout.")
			return false

		client_tls.poll()
		upstream_tls.poll()

		var c_status := client_tls.get_status()
		var u_status := upstream_tls.get_status()

		if c_status == StreamPeerTLS.STATUS_ERROR or c_status == StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH \
		or u_status == StreamPeerTLS.STATUS_ERROR or u_status == StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH:
			printerr("[Presence/ChatProxy] TLS handshake failed (Client: %d, Upstream: %d)" % [c_status, u_status])
			return false

		if c_status == StreamPeerTLS.STATUS_CONNECTED and u_status == StreamPeerTLS.STATUS_CONNECTED:
			session.state = "CONNECTED"
			print("[Presence/ChatProxy] Dual TLS handshake established! XMPP traffic bridging active.")

		return true

	# Phase 3: Bi-directional Traffic Bridging with Outbound Presence Filtering
	if session.state == "CONNECTED":
		client_tls.poll()
		upstream_tls.poll()

		if client_tls.get_status() != StreamPeerTLS.STATUS_CONNECTED or upstream_tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			return false

		var c_avail := client_tls.get_available_bytes()
		if c_avail > 0:
			var client_data := client_tls.get_partial_data(c_avail)
			if client_data[0] == OK and (client_data[1] as PackedByteArray).size() > 0:
				var filtered := XmppFilter.filter_outbound(client_data[1])
				if not filtered.is_empty():
					upstream_tls.put_data(filtered)

		var u_avail := upstream_tls.get_available_bytes()
		if u_avail > 0:
			var upstream_data := upstream_tls.get_partial_data(u_avail)
			if upstream_data[0] == OK and (upstream_data[1] as PackedByteArray).size() > 0:
				# Pass inbound data (roster, incoming messages, invites) intact to client
				client_tls.put_data(upstream_data[1])

		return true

	return false


func _close_session(session: Dictionary) -> void:
	if session.has("client_tls") and session.client_tls != null:
		var ct: StreamPeerTLS = session.client_tls
		ct.disconnect_from_stream()
	if session.has("upstream_tls") and session.upstream_tls != null:
		var ut: StreamPeerTLS = session.upstream_tls
		ut.disconnect_from_stream()
	if session.has("raw_client") and session.raw_client != null:
		var rc: StreamPeerTCP = session.raw_client
		rc.disconnect_from_host()
	if session.has("raw_upstream") and session.raw_upstream != null:
		var ru: StreamPeerTCP = session.raw_upstream
		ru.disconnect_from_host()
	print("[Presence/ChatProxy] Closed XMPP bridge session.")
