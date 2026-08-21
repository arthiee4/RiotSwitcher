# This file is part of RiotSwitcher, incorporating concepts and protocols
# adapted from Deceive (https://github.com/molenzwiebel/Deceive).
# Copyright (C) 2018-2024 molenzwiebel and contributors
# Copyright (C) 2026 RiotSwitcher contributors
#
# Licensed under the GNU General Public License v3.0.

class_name XmppFilter
extends RefCounted

## Filters outbound XMPP client traffic to hide user presence while preserving chat and system packets.

# Regex to match presence tags
static var _presence_regex: RegEx = null


static func _get_regex() -> RegEx:
	if _presence_regex == null:
		_presence_regex = RegEx.new()
		# Matches <presence...>...</presence> or <presence.../>
		_presence_regex.compile("(?s)<presence\\b[^>]*>(?:(?!<\\/presence>).)*?<\\/presence>|<presence\\b[^>]*\\/>")
	return _presence_regex


## Processes outbound data from Client to Riot Server.
## Strips or suppresses <presence> stanzas.
static func filter_outbound(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data

	var text := data.get_string_from_utf8()
	if text.is_empty() or not text.contains("<presence"):
		return data

	var regex := _get_regex()
	if not regex.is_valid():
		return data

	var matches := regex.search_all(text)
	if matches.is_empty():
		return data

	var modified := text
	# Process matches in reverse order to keep string indices valid
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var match_str := m.get_string()
		
		# If presence is directed to a room or MUC, we can keep or filter
		# Default Deceive behavior: Suppress presence or replace with unavailable
		var replacement := "<presence type='unavailable'/>"
		if match_str.contains("type='unavailable'"):
			replacement = match_str # Already unavailable, keep
		
		modified = modified.substr(0, m.get_start()) + replacement + modified.substr(m.get_end())

	print("[Presence/XMPP] Filtered %d presence stanza(s) from outbound stream." % matches.size())
	return modified.to_utf8_buffer()
