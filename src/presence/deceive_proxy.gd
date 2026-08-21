# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name DeceiveProxy
extends RefCounted

## Coordinator managing the ConfigProxy HTTP server and ChatProxy TCP/TLS server.

var _config_proxy: ConfigProxy = null
var _chat_proxy: ChatProxy = null
var _is_running: bool = false
var _owner_node: Node = null


func _init(owner_node: Node) -> void:
	_owner_node = owner_node
	_config_proxy = ConfigProxy.new(_owner_node)
	_chat_proxy = ChatProxy.new()
	_config_proxy.chat_host_discovered.connect(_on_chat_host_discovered)


func _on_chat_host_discovered(host: String, port: int) -> void:
	if _chat_proxy != null:
		_chat_proxy.set_upstream_target(host, port)


## Starts both the Chat Proxy and Config Proxy on local ephemeral ports.
func start() -> Error:
	if _is_running:
		return OK

	# 1. Start Chat Proxy first to get assigned TCP port
	var err := _chat_proxy.start()
	if err != OK:
		printerr("[Presence/DeceiveProxy] Failed to start ChatProxy. Error: ", err)
		return err

	var chat_port := _chat_proxy.get_port()

	# 2. Start Config Proxy passing the chat port for JSON patching
	err = _config_proxy.start(chat_port)
	if err != OK:
		printerr("[Presence/DeceiveProxy] Failed to start ConfigProxy. Error: ", err)
		_chat_proxy.stop()
		return err

	_is_running = true
	print("[Presence/DeceiveProxy] Both proxies started successfully. Config: %d, Chat: %d" % [_config_proxy.get_port(), chat_port])
	return OK


## Stops both proxies and frees sockets.
func stop() -> void:
	if not _is_running:
		return

	if _config_proxy != null:
		_config_proxy.stop()
	if _chat_proxy != null:
		_chat_proxy.stop()

	_is_running = false
	print("[Presence/DeceiveProxy] Both proxies stopped.")


func poll() -> void:
	if not _is_running:
		return
	if _config_proxy != null:
		_config_proxy.poll()
	if _chat_proxy != null:
		_chat_proxy.poll()


func get_config_port() -> int:
	return _config_proxy.get_port() if _config_proxy != null else 0


func get_chat_port() -> int:
	return _chat_proxy.get_port() if _chat_proxy != null else 0


func is_running() -> bool:
	return _is_running
