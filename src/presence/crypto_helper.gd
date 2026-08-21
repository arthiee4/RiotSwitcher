# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name CryptoHelper
extends RefCounted

## Utility helper to generate in-memory self-signed TLS certificates for local MITM proxying.

static var _cached_key: CryptoKey = null
static var _cached_cert: X509Certificate = null
static var _cached_tls_options: TLSOptions = null


## Generates or retrieves the cached TLS server options for local chat proxy.
static func get_server_tls_options() -> TLSOptions:
	if _cached_tls_options != null:
		return _cached_tls_options

	var crypto := Crypto.new()
	if _cached_key == null:
		_cached_key = crypto.generate_rsa(2048)

	if _cached_cert == null and _cached_key != null:
		# Format: "CN=deceive-localhost.molenzwiebel.xyz,O=Deceive,C=US"
		var issuer_name := "CN=" + PresenceConstants.DECEIVE_LOCALHOST_DOMAIN + ",O=Deceive,C=US"
		var not_before := "20240101000000"
		var not_after := "20340101000000"
		_cached_cert = crypto.generate_self_signed_certificate(_cached_key, issuer_name, not_before, not_after)

	if _cached_key != null and _cached_cert != null:
		_cached_tls_options = TLSOptions.server(_cached_key, _cached_cert)
		print("[Presence/Crypto] Self-signed TLS certificate generated successfully.")

	return _cached_tls_options


## Clears cached certificates and keys from memory on full shutdown.
static func cleanup() -> void:
	_cached_tls_options = null
	_cached_cert = null
	_cached_key = null
