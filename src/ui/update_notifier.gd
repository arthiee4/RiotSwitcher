extends Control

## Bottom-right notifier that checks GitHub for a newer release and, when one
## exists, shows a clickable "Update available (x.x.x)" label that opens the
## releases page. Everything is authored in main.tscn; this only does the fetch.

const REQUEST_DELAY := 3.0

@onready var _button: Button = $update_label
@onready var _http: HTTPRequest = $http

var _release_url: String = Constants.GITHUB_RELEASES_PAGE


func _ready() -> void:
	_button.visible = false
	_button.pressed.connect(_on_button_pressed)
	_http.request_completed.connect(_on_request_completed)

	# Delay the check so it never competes with startup work.
	var timer := get_tree().create_timer(REQUEST_DELAY)
	timer.timeout.connect(_check_for_update)


func _check_for_update() -> void:
	if not is_inside_tree():
		return

	var headers := PackedStringArray([
		"User-Agent: RiotSwitcher",
		"Accept: application/vnd.github+json",
	])
	_http.request(Constants.GITHUB_RELEASES_API, headers, HTTPClient.METHOD_GET)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return

	var data: Dictionary = json.data
	var latest_version := _extract_version(str(data.get("tag_name", "")))
	if latest_version.is_empty():
		return

	_release_url = str(data.get("html_url", Constants.GITHUB_RELEASES_PAGE))
	if _is_newer(latest_version, Constants.APP_VERSION):
		_button.text = tr("Update available (%s)") % latest_version
		_button.visible = true


## Pulls "0.3.4" out of tags like "Ana-0.3.4" or "v0.3.4".
func _extract_version(tag: String) -> String:
	var regex := RegEx.new()
	regex.compile("(\\d+(?:\\.\\d+)+)")
	var found := regex.search(tag)
	return found.get_string(1) if found else ""


func _is_newer(latest: String, current: String) -> bool:
	var a := _parse_version(latest)
	var b := _parse_version(current)
	for i in range(maxi(a.size(), b.size())):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


func _parse_version(version: String) -> Array[int]:
	var parts: Array[int] = []
	for part in version.split("."):
		parts.append(part.to_int())
	return parts


func _on_button_pressed() -> void:
	OS.shell_open(_release_url)
