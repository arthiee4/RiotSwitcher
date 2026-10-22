class_name BackupProgressModal
extends Control

# Modal that dims the screen and shows a single status line with animated trailing dots plus an anti-aliased rounded Riot-red progress bar.
# Before a backup runs it can also ask for the backup password or confirm importing a legacy backup.

signal closed
signal prompt_confirmed(password: String)
signal prompt_cancelled

enum PromptMode { NONE, EXPORT_PASSWORD, IMPORT_PASSWORD, LEGACY_NOTICE }

const MIN_PASSWORD_LENGTH := 8
const PANEL_HALF_WIDTH := 210.0
const PANEL_HALF_HEIGHT := 70.0
const COLOR_TEXT := Color(0.9412, 0.902, 0.8235, 1.0)
const COLOR_HINT := Color(0.6275, 0.6078, 0.549, 1.0)
const COLOR_ERROR := Color(0.9098, 0.251, 0.3412, 1.0)

@onready var _backdrop: ColorRect = $backdrop
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/VBoxContainer/title_label
@onready var _progress_bar: ProgressBar = $Panel/VBoxContainer/ProgressBar
@onready var _action_button: Button = $Panel/VBoxContainer/action_button


func set_accent_color(accent: Color) -> void:
	if not _progress_bar:
		return
	var fill := _progress_bar.get_theme_stylebox("fill")
	if not fill:
		return
	var fill_copy := fill.duplicate(true) as StyleBox
	if fill_copy is StyleBoxFlat:
		var fill_flat := fill_copy as StyleBoxFlat
		var alpha := fill_flat.bg_color.a
		fill_flat.bg_color = accent
		fill_flat.bg_color.a = alpha if alpha > 0.01 else 0.9
		_progress_bar.add_theme_stylebox_override("fill", fill_copy)
var _is_active := false
var _dot_timer := 0.0
var _dot_count := 0
var _status_text := ""
var _progress_tween: Tween = null
var _prompt_mode := PromptMode.NONE
var _password_input: LineEdit = null
var _confirm_input: LineEdit = null
var _hint_label: Label = null
var _prompt_buttons: HBoxContainer = null
var _cancel_button: Button = null
var _continue_button: Button = null
# Pending fade-out; a new prompt or operation must cancel it or it would hide the modal mid-use.
var _close_tween: Tween = null


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
	_kill_close_tween()
	_set_prompt_visible(false)
	_is_active = true
	_status_text = tr("Importing") if is_import else tr("Exporting")
	_dot_count = 3
	_dot_timer = 0.0

	if _title_label:
		_title_label.add_theme_color_override("font_color", Color(0.9412, 0.902, 0.8235, 1.0))
		_render_status(_current_dots())

	if _progress_bar:
		_progress_bar.value = 0.0
		_progress_bar.visible = true

	if _action_button:
		_action_button.visible = false

	_fit_panel()
	if visible and modulate.a > 0.99:
		return # Already on screen after a prompt; just switch content.

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
		_title_label.add_theme_color_override("font_color", Color(0.9412, 0.902, 0.8235, 1.0))

	# Wait a brief moment to show success, then fade out smoothly
	_fade_out(0.20, 0.9)


func finish_error(error_message: String) -> void:
	_is_active = false
	SfxManager.error()

	if _title_label:
		_status_text = error_message if error_message != "" else tr("Error")
		_title_label.text = _status_text
		_title_label.add_theme_color_override("font_color", Color(0.9098, 0.251, 0.3412, 1.0))

	if _action_button:
		_action_button.text = tr("Close")
		_action_button.visible = true


# Asks for the password that protects (export) or unlocks (import) a backup. Emits prompt_confirmed or prompt_cancelled.
func prompt_password(for_import: bool) -> void:
	_show_prompt(PromptMode.IMPORT_PASSWORD if for_import else PromptMode.EXPORT_PASSWORD)


# Warns that a v1 backup is not protected before importing it. Emits prompt_confirmed("") or prompt_cancelled.
func prompt_legacy_notice() -> void:
	_show_prompt(PromptMode.LEGACY_NOTICE)


func _show_prompt(mode: PromptMode) -> void:
	_ensure_nodes()
	_kill_close_tween()
	_build_prompt_nodes()
	# Set texts on every prompt so a language change in Settings applies.
	_password_input.placeholder_text = tr("Password")
	_confirm_input.placeholder_text = tr("Confirm password")
	_cancel_button.text = tr("Cancel")
	_continue_button.text = tr("Continue")
	_prompt_mode = mode
	_is_active = false

	match mode:
		PromptMode.EXPORT_PASSWORD:
			_status_text = tr("Set a password for this backup")
			_set_hint(tr("You will need it to import the backup. It cannot be recovered."), false)
		PromptMode.IMPORT_PASSWORD:
			_status_text = tr("Enter the backup password")
			_set_hint("", false)
		PromptMode.LEGACY_NOTICE:
			_status_text = tr("Old backup format")
			_set_hint(tr("This backup is not password-protected. After importing, export a new backup and delete this file."), false)

	if _title_label:
		_title_label.text = _status_text
		_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	if _progress_bar:
		_progress_bar.visible = false
	if _action_button:
		_action_button.visible = false

	_set_prompt_visible(true)
	_password_input.text = ""
	_confirm_input.text = ""
	_password_input.visible = mode != PromptMode.LEGACY_NOTICE
	_confirm_input.visible = mode == PromptMode.EXPORT_PASSWORD
	_fit_panel()
	_fit_panel.call_deferred()

	visible = true
	SfxManager.open()
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _password_input.visible:
		_password_input.grab_focus.call_deferred()


func _build_prompt_nodes() -> void:
	if _prompt_buttons:
		return
	var vbox := _panel.get_node("VBoxContainer") as VBoxContainer
	var insert_at := _title_label.get_index() + 1

	_password_input = _make_password_input()
	_confirm_input = _make_password_input()
	_password_input.text_submitted.connect(func(_t: String): _on_prompt_continue())
	_confirm_input.text_submitted.connect(func(_t: String): _on_prompt_continue())

	_hint_label = Label.new()
	_hint_label.name = "prompt_hint"
	_hint_label.custom_minimum_size = Vector2(340, 0)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)

	_prompt_buttons = HBoxContainer.new()
	_prompt_buttons.name = "prompt_buttons"
	_prompt_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_buttons.add_theme_constant_override("separation", 12)
	_cancel_button = _make_prompt_button(_on_prompt_cancel)
	_continue_button = _make_prompt_button(_on_prompt_continue)
	_prompt_buttons.add_child(_cancel_button)
	_prompt_buttons.add_child(_continue_button)

	for node: Control in [_password_input, _confirm_input, _hint_label, _prompt_buttons]:
		vbox.add_child(node)
		vbox.move_child(node, insert_at)
		insert_at += 1


func _make_password_input() -> LineEdit:
	var input := LineEdit.new()
	input.secret = true
	input.custom_minimum_size = Vector2(300, 34)
	input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	input.max_length = 128
	return input


func _make_prompt_button(on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(110, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(on_pressed)
	return button


func _set_prompt_visible(is_shown: bool) -> void:
	if not is_shown:
		_prompt_mode = PromptMode.NONE
		if _password_input:
			_password_input.text = ""
			_confirm_input.text = ""
		if _hint_label:
			_hint_label.visible = false # Shown only through _set_hint, so an empty hint takes no space.
	for node in [_password_input, _confirm_input, _prompt_buttons]:
		if node:
			node.visible = is_shown


func _set_hint(text: String, is_error: bool) -> void:
	_hint_label.text = text
	_hint_label.visible = text != ""
	_hint_label.add_theme_color_override("font_color", COLOR_ERROR if is_error else COLOR_HINT)
	_fit_panel()
	_fit_panel.call_deferred() # Wrapped label height is only final after a layout pass.


# Grows the panel around its content; the scene's fixed size only fits the progress layout.
func _fit_panel() -> void:
	if not _panel:
		return
	var vbox := _panel.get_node_or_null("VBoxContainer") as VBoxContainer
	var half_height := PANEL_HALF_HEIGHT
	if vbox and _prompt_mode != PromptMode.NONE:
		half_height = maxf(PANEL_HALF_HEIGHT, (vbox.get_combined_minimum_size().y + 48.0) * 0.5)
	_panel.offset_left = -PANEL_HALF_WIDTH
	_panel.offset_right = PANEL_HALF_WIDTH
	_panel.offset_top = -half_height
	_panel.offset_bottom = half_height


func _on_prompt_continue() -> void:
	if _prompt_mode == PromptMode.NONE:
		return
	var password := ""
	if _prompt_mode != PromptMode.LEGACY_NOTICE:
		password = _password_input.text
		if _prompt_mode == PromptMode.EXPORT_PASSWORD:
			if password.length() < MIN_PASSWORD_LENGTH:
				_set_hint(tr("Use at least %d characters.") % MIN_PASSWORD_LENGTH, true)
				SfxManager.error()
				return
			if password != _confirm_input.text:
				_set_hint(tr("Passwords do not match."), true)
				SfxManager.error()
				return
		elif password.is_empty():
			_set_hint(tr("Enter the password."), true)
			SfxManager.error()
			return
	_set_prompt_visible(false)
	prompt_confirmed.emit(password)


func _on_prompt_cancel() -> void:
	if _prompt_mode == PromptMode.NONE:
		return
	_set_prompt_visible(false)
	# Emit right away so the caller re-enables its buttons even if the fade is cut short.
	prompt_cancelled.emit()
	_fade_out(0.15)


func _on_action_button_pressed() -> void:
	_fade_out(0.15)


func _fade_out(duration: float, delay: float = 0.0) -> void:
	_kill_close_tween()
	_close_tween = create_tween()
	if delay > 0.0:
		_close_tween.tween_interval(delay)
	_close_tween.tween_property(self, "modulate:a", 0.0, duration)
	_close_tween.finished.connect(func():
		_close_tween = null
		visible = false
		closed.emit()
	)


func _kill_close_tween() -> void:
	if _close_tween and _close_tween.is_valid():
		_close_tween.kill()
	_close_tween = null
