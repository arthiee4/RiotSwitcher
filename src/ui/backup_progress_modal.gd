class_name BackupProgressModal
extends Control

## Modal that dims the screen and shows a single status line with animated
## trailing dots plus an anti-aliased rounded Riot-red progress bar.

signal closed

@onready var _backdrop: ColorRect = $backdrop
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/VBoxContainer/title_label
@onready var _progress_bar: ProgressBar = $Panel/VBoxContainer/ProgressBar
@onready var _action_button: Button = $Panel/VBoxContainer/action_button

var _is_active := false
var _dot_timer := 0.0
var _dot_count := 0
var _status_text := ""
var _progress_tween: Tween = null


func _ready() -> void:
	_ensure_nodes()
	visible = false
	modulate.a = 0.0
	if _action_button and not _action_button.pressed.is_connected(_on_action_button_pressed):
		_action_button.pressed.connect(_on_action_button_pressed)


func _ensure_nodes() -> void:
	if not _backdrop:
		_backdrop = get_node_or_null("backdrop") as ColorRect
	if not _panel:
		_panel = get_node_or_null("Panel") as Panel
	if not _title_label and _panel:
		_title_label = _panel.get_node_or_null("VBoxContainer/title_label") as Label
	if not _progress_bar and _panel:
		_progress_bar = _panel.get_node_or_null("VBoxContainer/ProgressBar") as ProgressBar
	if not _action_button and _panel:
		_action_button = _panel.get_node_or_null("VBoxContainer/action_button") as Button


func _process(delta: float) -> void:
	if not _is_active or not visible:
		return

	_dot_timer += delta
	if _dot_timer >= 0.25:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		_render_status(_current_dots())


func _current_dots() -> String:
	var dots := ""
	for i in range(_dot_count):
		dots += "."
	return dots


func _render_status(dots: String) -> void:
	if is_instance_valid(_title_label):
		_title_label.text = _status_text + dots


func open_modal(is_import: bool) -> void:
	_ensure_nodes()
	_is_active = true
	_status_text = tr("Importing") if is_import else tr("Exporting")
	_dot_count = 3
	_dot_timer = 0.0

	if _title_label:
		_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_render_status(_current_dots())

	if _progress_bar:
		_progress_bar.value = 0.0

	if _action_button:
		_action_button.visible = false

	# Center and animate entrance
	visible = true
	SfxManager.open()
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_progress(percent: float, message: String) -> void:
	if not visible:
		return

	if message != "":
		_status_text = message
		_render_status("...")

	if is_instance_valid(_progress_bar):
		var target_val: float = clampf(percent * 100.0, 0.0, 100.0)
		if _progress_tween and _progress_tween.is_valid():
			_progress_tween.kill()
		_progress_tween = create_tween()
		_progress_tween.tween_property(_progress_bar, "value", target_val, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func finish_success(message: String) -> void:
	_is_active = false
	SfxManager.confirm()
	if _progress_bar:
		_progress_bar.value = 100.0

	if _title_label:
		_status_text = message if message != "" else tr("Success!")
		_title_label.text = _status_text
		_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))

	# Wait a brief moment to show success, then fade out smoothly
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(self, "modulate:a", 0.0, 0.20)
	tw.finished.connect(func():
		visible = false
		closed.emit()
	)


func finish_error(error_message: String) -> void:
	_is_active = false
	SfxManager.error()

	if _title_label:
		_status_text = error_message if error_message != "" else tr("Error")
		_title_label.text = _status_text
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.04, 0.14, 1.0))

	if _action_button:
		_action_button.text = tr("Close")
		_action_button.visible = true


func _on_action_button_pressed() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.finished.connect(func():
		visible = false
		closed.emit()
	)
