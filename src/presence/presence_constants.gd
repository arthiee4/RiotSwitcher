# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name PresenceConstants
extends RefCounted

## Configuration key stored in configs.json for Appear Offline toggle
const CONFIG_KEY_APPEAR_OFFLINE := "AppearOffline"

## Loopback address for local proxies
const LOCALHOST_IP := "127.0.0.1"

## Deceive public DNS domain resolving to 127.0.0.1 for SSL host validation
const DECEIVE_LOCALHOST_DOMAIN := "deceive-localhost.molenzwiebel.xyz"

## Official upstream Riot client configuration endpoint
const RIOT_CLIENT_CONFIG_BASE_URL := "https://clientconfig.rpg.riotgames.com"

## Default Riot XMPP chat port over TLS
const DEFAULT_RIOT_CHAT_PORT := 5223

## Stream buffer sizes
const BUFFER_SIZE := 16384

## Process watchdog interval in seconds
const PROCESS_POLL_INTERVAL_SEC := 2.0
