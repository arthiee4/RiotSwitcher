class_name CleanLogsController
extends Control

## Settings view controller for purging Riot Client & League log files and crash dumps.
## Runs scanning and deletion asynchronously on a worker thread to keep the UI smooth.

@onready var _clean_button: Button = $Panel/Button if has_node("Panel/Button") else (find_child("Button", true, false) as Button)
@onready var _status_label: Label = $Panel/status_label if has_node("Panel/status_label") else (find_child("status_label", true, false) as Label)

var _worker: Thread = null
var _is_cleaning := false


func _ready() -> void:
	if _clean_button:
		_clean_button.pressed.connect(_on_clean_pressed)
		_clean_button.set_meta("sfx", &"confirm")
		_clean_button.text = tr("Clean")

	if _status_label:
		_status_label.text = ""
		_status_label.pivot_offset = Vector2(0, 10)

	# Initial asynchronous scan to report available space to be cleaned
	_run_in_thread(_scan_initial_size)


func _exit_tree() -> void:
	if _worker:
		_worker.wait_to_finish()
		_worker = null


func _run_in_thread(task: Callable) -> void:
	if _worker and _worker.is_alive():
		return
	if _worker:
		_worker.wait_to_finish()
		_worker = null
	_worker = Thread.new()
	_worker.start(task)


func _scan_initial_size() -> void:
	var res := RiotDiskCleaner.calculate_cleanable_size()
	var bytes: int = int(res.get("total_bytes", 0))
	call_deferred("_on_initial_scan_finished", bytes)


func _on_initial_scan_finished(bytes: int) -> void:
	if _worker and not _worker.is_alive():
		_worker.wait_to_finish()
		_worker = null

	if not is_inside_tree() or not _status_label or _is_cleaning:
		return
	if bytes > 0:
		_status_label.text = "(%s)" % RiotDiskCleaner.format_bytes(bytes)
		_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	else:
		_status_label.text = tr("Already clean (0 B)")
		_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))


func _on_clean_pressed() -> void:
	if _is_cleaning:
		return
	_is_cleaning = true

	if _clean_button:
		_clean_button.disabled = true
		_clean_button.text = tr("Cleaning...")

	if _status_label:
		_status_label.text = tr("Cleaning...")
		_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))

	_run_in_thread(_execute_clean)


func _execute_clean() -> void:
	var res := RiotDiskCleaner.clean_logs()
	var freed_bytes: int = int(res.get("freed_bytes", 0))
	call_deferred("_on_clean_finished", freed_bytes)


func _on_clean_finished(freed_bytes: int) -> void:
	if _worker and not _worker.is_alive():
		_worker.wait_to_finish()
		_worker = null

	_is_cleaning = false

	if _clean_button and is_instance_valid(_clean_button):
		_clean_button.disabled = false
		_clean_button.text = tr("Clean")

	if _status_label and is_instance_valid(_status_label):
		if freed_bytes > 0:
			var formatted := RiotDiskCleaner.format_bytes(freed_bytes)
			_status_label.text = tr("Freed %s") % formatted
			_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

			# Punchy pop animation on the status label
			_status_label.pivot_offset = _status_label.size * 0.5
			_status_label.scale = Vector2(1.18, 1.18)
			var tw := create_tween()
			tw.tween_property(_status_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			_status_label.text = tr("Already clean (0 B)")
			_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
