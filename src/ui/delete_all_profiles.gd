extends Control

const FONT_DISPLAY: FontFile = preload("res://assets/fonts/BeaufortforLoL-Bold.otf")
const FONT_BODY: FontFile = preload("res://assets/fonts/Spiegel-Regular.otf")
const DIVIDER_TEX: Texture2D = preload("res://assets/icons/hextech/title_divider.png")

const ACCENT_PRESETS := {
	"red": Color("#ff0000"), "white": Color("#f0e6d2"),
	"blue": Color("#4f8fd8"), "gold": Color("#c8aa6e"),
	"green": Color("#45b878"), "violet": Color("#9b70d8"),
	"cyan": Color("#39c6c8"), "orange": Color("#e08a3e"),
	"pink": Color("#d96b9b"), "gray": Color("#858b95"),
}


func _accent_from_key(key: String) -> Color:
	return ACCENT_PRESETS.get(key, Color("#f0e6d2"))

@onready var _delete_button: Button = $Panel/Button if has_node("Panel/Button") else find_child("Button", true, false)

var _modal: Control = null
var _backdrop: ColorRect = null
var _panel: Panel = null
var _title_label: Label = null
var _title_divider: TextureRect = null
var _desc_label: Label = null
var _cancel_button: Button = null
var _confirm_button: Button = null
var _is_open: bool = false
var _anim_tween: Tween = null


func _ready() -> void:
	if _delete_button:
		_delete_button.pressed.connect(_on_delete_all_pressed)
		_delete_button.set_meta("sfx", &"open")
	_build_confirm_modal()
	_update_translations()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_translations()


func _build_confirm_modal() -> void:
	_modal = Control.new()
	_modal.name = "delete_confirm_modal"
	_modal.visible = false
	_modal.z_index = 200
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP

	_backdrop = ColorRect.new()
	_backdrop.name = "backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0039, 0.02, 0.04, 0.82)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	_modal.add_child(_backdrop)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -220.0
	_panel.offset_top = -105.0
	_panel.offset_right = 220.0
	_panel.offset_bottom = 105.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var panel_sb := StyleBoxFancy.new()
	panel_sb.color = Color(0.0039, 0.0392, 0.0745, 0.98)
	panel_sb.corner_detail = 8
	panel_sb.corner_radius_top_left = 24
	panel_sb.corner_radius_top_right = 0
	panel_sb.corner_radius_bottom_right = 24
	panel_sb.corner_radius_bottom_left = 0
	panel_sb.corner_curvature_top_left = 0.0
	panel_sb.corner_curvature_top_right = -7.0
	panel_sb.corner_curvature_bottom_right = 0.0
	panel_sb.corner_curvature_bottom_left = -7.0
	panel_sb.shadow_color = Color(0, 0, 0, 0.85)
	panel_sb.shadow_blur = 16
	var b_outer := StyleBorder.new()
	b_outer.color = Color(0.55, 0.42, 0.18, 1.0)
	b_outer.width_left = 2
	b_outer.width_top = 1
	b_outer.width_right = 1
	b_outer.width_bottom = 1
	var b_inner := StyleBorder.new()
	b_inner.color = Color(0.7843, 0.6667, 0.4314, 0.25)
	b_inner.set_width_all(1)
	b_inner.set_inset_all(3)
	var panel_borders: Array[StyleBorder] = [b_outer, b_inner]
	panel_sb.borders = panel_borders
	_panel.add_theme_stylebox_override("panel", panel_sb)
	_modal.add_child(_panel)

	_title_label = Label.new()
	_title_label.name = "title"
	_title_label.offset_left = 28.0
	_title_label.offset_top = 22.0
	_title_label.offset_right = 412.0
	_title_label.offset_bottom = 54.0
	_title_label.add_theme_font_override("font", FONT_DISPLAY)
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.9412, 0.902, 0.8235, 1.0))
	_panel.add_child(_title_label)

	_title_divider = TextureRect.new()
	_title_divider.name = "title_divider"
	_title_divider.offset_left = 28.0
	_title_divider.offset_top = 56.0
	_title_divider.offset_right = 260.0
	_title_divider.offset_bottom = 62.0
	_title_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_divider.texture = DIVIDER_TEX
	_title_divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_divider.modulate = Color(0.784314, 0.666667, 0.431373, 0.6)
	_panel.add_child(_title_divider)

	_desc_label = Label.new()
	_desc_label.name = "desc_label"
	_desc_label.offset_left = 28.0
	_desc_label.offset_top = 70.0
	_desc_label.offset_right = 412.0
	_desc_label.offset_bottom = 136.0
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_override("font", FONT_BODY)
	_desc_label.add_theme_font_size_override("font_size", 14)
	_desc_label.add_theme_color_override("font_color", Color(0.6275, 0.6078, 0.549, 1.0))
	_panel.add_child(_desc_label)

	var actions := HBoxContainer.new()
	actions.name = "actions"
	actions.offset_left = 28.0
	actions.offset_top = 150.0
	actions.offset_right = 412.0
	actions.offset_bottom = 184.0
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	_panel.add_child(actions)

	_cancel_button = _create_modal_button("cancel_button", true)
	_cancel_button.set_meta("sfx", &"cancel")
	_cancel_button.pressed.connect(close_modal)
	actions.add_child(_cancel_button)

	_confirm_button = _create_modal_button("confirm_delete_button", false)
	_confirm_button.set_meta("sfx", &"cancel")
	_confirm_button.pressed.connect(_on_confirm_delete_pressed)
	actions.add_child(_confirm_button)

	# Defer adding to root so the scene tree is fully ready.
	_reparent_modal_to_settings.call_deferred()


func _reparent_modal_to_settings() -> void:
	if not _modal or not is_instance_valid(_modal):
		return
	if _modal.get_parent():
		return  # already parented
	# Add to the scene root so it covers the full viewport.
	var root := get_tree().root
	root.add_child(_modal)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.offset_left = 0.0
	_modal.offset_top = 0.0
	_modal.offset_right = 0.0
	_modal.offset_bottom = 0.0
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = 0.0
	_backdrop.offset_top = 0.0
	_backdrop.offset_right = 0.0
	_backdrop.offset_bottom = 0.0


func _create_modal_button(btn_name: String, is_left: bool) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.custom_minimum_size = Vector2(110.0, 34.0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", FONT_DISPLAY)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.8039, 0.7451, 0.5686, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.9412, 0.902, 0.8235, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.9412, 0.902, 0.8235, 1.0))

	var sb_normal := _make_btn_stylebox(is_left, false)
	var sb_hover := _make_btn_stylebox(is_left, true)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover.duplicate(true))
	btn.add_theme_stylebox_override("hover_pressed", sb_hover.duplicate(true))
	return btn


func _make_btn_stylebox(is_left: bool, is_hover: bool) -> StyleBoxFancy:
	var sb := StyleBoxFancy.new()
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.color = Color(0.1725, 0.1608, 0.1333, 1.0) if is_hover else Color(0.1176, 0.1373, 0.1569, 1.0)
	if is_left:
		sb.corner_radius_top_left = 6
		sb.corner_radius_bottom_left = 6
	else:
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
	var border := StyleBorder.new()
	border.color = Color(0.82, 0.72, 0.48, 0.85) if is_hover else Color(0.4706, 0.3529, 0.1569, 1.0)
	border.width_left = 2 if is_left else 1
	border.width_top = 1
	border.width_right = 1 if is_left else 2
	border.width_bottom = 1
	var borders_arr: Array[StyleBorder] = [border]
	sb.borders = borders_arr
	return sb


func apply_accent_color(accent: Color) -> void:
	if not _panel or not is_instance_valid(_panel):
		return
	var ui_style := String(ConfigManager.get_value("UIStyle", "clean")).to_lower()
	var is_clean: bool = (ui_style == "clean")
	var is_league: bool = (ui_style == "league_client")

	# --- Panel ---
	var panel_sb := StyleBoxFancy.new()
	panel_sb.shadow_color = Color(0, 0, 0, 0.85)
	panel_sb.shadow_blur = 16
	if is_clean:
		panel_sb.color = Color(0.07058824, 0.07058824, 0.07058824, 0.98)
		panel_sb.corner_detail = 12
		panel_sb.corner_radius_top_left = 8
		panel_sb.corner_radius_top_right = 8
		panel_sb.corner_radius_bottom_right = 8
		panel_sb.corner_radius_bottom_left = 8
		panel_sb.corner_curvature_top_left = 1.0
		panel_sb.corner_curvature_top_right = 1.0
		panel_sb.corner_curvature_bottom_right = 1.0
		panel_sb.corner_curvature_bottom_left = 1.0
		var cb := StyleBorder.new()
		cb.set_width_all(1)
		cb.color = Color(1.0, 1.0, 1.0, 0.18)
		var cb_arr: Array[StyleBorder] = [cb]
		panel_sb.borders = cb_arr
	elif is_league:
		panel_sb.color = Color(0.0039, 0.0392, 0.0745, 0.98)
		var lb_o := StyleBorder.new()
		lb_o.color = Color(0.55, 0.42, 0.18, 1.0)
		lb_o.width_left = 2
		lb_o.width_top = 1
		lb_o.width_right = 1
		lb_o.width_bottom = 1
		var lb_i := StyleBorder.new()
		lb_i.color = Color(0.7843, 0.6667, 0.4314, 0.25)
		lb_i.set_width_all(1)
		lb_i.set_inset_all(3)
		var lb_arr: Array[StyleBorder] = [lb_o, lb_i]
		panel_sb.borders = lb_arr
	else:
		panel_sb.color = Color(0.0039, 0.0392, 0.0745, 0.98)
		panel_sb.corner_detail = 8
		panel_sb.corner_radius_top_left = 24
		panel_sb.corner_radius_bottom_right = 24
		panel_sb.corner_curvature_top_right = -7.0
		panel_sb.corner_curvature_bottom_left = -7.0
		var b_o := StyleBorder.new()
		b_o.color = Color(accent.r * 0.70, accent.g * 0.63, accent.b * 0.42, 1.0)
		b_o.width_left = 2
		b_o.width_top = 1
		b_o.width_right = 1
		b_o.width_bottom = 1
		var b_i := StyleBorder.new()
		b_i.color = Color(accent.r, accent.g, accent.b, 0.25)
		b_i.set_width_all(1)
		b_i.set_inset_all(3)
		var b_arr: Array[StyleBorder] = [b_o, b_i]
		panel_sb.borders = b_arr
	_panel.add_theme_stylebox_override("panel", panel_sb)

	# --- Divider ---
	if _title_divider:
		if is_clean:
			_title_divider.visible = false
		else:
			_title_divider.visible = true
			_title_divider.modulate = Color(0.784314, 0.666667, 0.431373, 0.6) if is_league else Color(accent.r, accent.g, accent.b, 0.6)

	# --- Title ---
	if _title_label:
		_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0) if is_clean else Color(0.9412, 0.902, 0.8235, 1.0))

	# --- Desc ---
	if _desc_label:
		_desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0) if is_clean else Color(0.6275, 0.6078, 0.549, 1.0))

	# --- Buttons ---
	if _cancel_button:
		_restyle_modal_btn(_cancel_button, true, accent, is_clean, is_league)
	if _confirm_button:
		_restyle_modal_btn(_confirm_button, false, accent, is_clean, is_league)

	# --- Backdrop ---
	if _backdrop:
		_backdrop.color = Color(0.0, 0.0, 0.0, 0.72) if is_clean else Color(0.0039, 0.02, 0.04, 0.82)


func _restyle_modal_btn(btn: Button, is_left: bool, accent: Color, is_clean: bool, is_league: bool) -> void:
	var bn: Color
	var bh: Color
	var bgn: Color
	var bgh: Color
	var rtl := 0
	var rtr := 0
	var rbl := 0
	var rbr := 0
	var curv := 0.0
	if is_clean:
		bn = Color(1.0, 1.0, 1.0, 0.22)
		bh = Color(1.0, 1.0, 1.0, 0.55)
		bgn = Color(0.07058824, 0.07058824, 0.07058824, 1.0)
		bgh = Color(0.115, 0.115, 0.115, 1.0)
		rtl = 8; rtr = 8; rbl = 8; rbr = 8; curv = 1.0
	elif is_league:
		bn = Color(0.62, 0.48, 0.22, 0.95)
		bh = Color(0.9412, 0.902, 0.8235, 1.0)
		bgn = Color(0.1176, 0.1373, 0.1569, 0.96)
		bgh = Color(0.165, 0.19, 0.22, 0.98)
	else:
		bn = Color(accent.r * 0.60, accent.g * 0.53, accent.b * 0.20, 1.0)
		bh = Color(accent.r * 0.82, accent.g * 0.72, accent.b * 0.48, 0.85)
		bgn = Color(0.1176, 0.1373, 0.1569, 1.0)
		bgh = Color(0.1725, 0.1608, 0.1333, 1.0)
		if is_left:
			rtl = 6; rbl = 6
		else:
			rtr = 6; rbr = 6
	for is_hov in [false, true]:
		var sb := StyleBoxFancy.new()
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.color = bgh if is_hov else bgn
		sb.corner_radius_top_left = rtl
		sb.corner_radius_top_right = rtr
		sb.corner_radius_bottom_right = rbr
		sb.corner_radius_bottom_left = rbl
		sb.corner_curvature_top_left = curv
		sb.corner_curvature_top_right = curv
		sb.corner_curvature_bottom_right = curv
		sb.corner_curvature_bottom_left = curv
		var b := StyleBorder.new()
		b.color = bh if is_hov else bn
		b.width_left = 2 if is_left else 1
		b.width_top = 1
		b.width_right = 1 if is_left else 2
		b.width_bottom = 1
		var sb_arr: Array[StyleBorder] = [b]
		sb.borders = sb_arr
		if is_hov:
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb.duplicate(true) as StyleBox)
			btn.add_theme_stylebox_override("hover_pressed", sb.duplicate(true) as StyleBox)
		else:
			btn.add_theme_stylebox_override("normal", sb)

	# Font colors
	if is_clean:
		btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	elif is_league:
		btn.add_theme_color_override("font_color", Color(0.8039, 0.7451, 0.5686, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.9412, 0.902, 0.8235, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.9412, 0.902, 0.8235, 1.0))
	else:
		btn.add_theme_color_override("font_color", Color(accent.r * 0.80, accent.g * 0.74, accent.b * 0.57, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.9412, 0.902, 0.8235, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.9412, 0.902, 0.8235, 1.0))


func _is_profile_running_or_busy() -> bool:
	var grid := _find_profile_grid()
	if grid:
		if grid.has_method("get_running_profile_name") and not str(grid.get_running_profile_name()).is_empty():
			return true
		if grid.has_method("_is_busy") and grid._is_busy():
			return true
	return false


func _update_translations() -> void:
	if _title_label:
		_title_label.text = tr("Delete all profiles")
	var locked := _is_profile_running_or_busy()
	if _desc_label:
		_desc_label.text = (
			tr("Settings are locked while a profile is running. Close the game to modify.")
			if locked
			else tr("Are you sure you want to permanently delete all saved profiles? This action cannot be undone.")
		)
	if _cancel_button:
		_cancel_button.text = tr("Close") if locked else tr("Cancel")
	if _confirm_button:
		_confirm_button.text = tr("Delete")
		_confirm_button.visible = not locked


func _on_delete_all_pressed() -> void:
	open_modal()


func open_modal() -> void:
	if not _modal:
		return
	# Re-apply theme every open so it always matches the active preset.
	var accent_key := String(ConfigManager.get_value("AccentColor", "white")).to_lower()
	apply_accent_color(_accent_from_key(accent_key))
	_update_translations()
	_is_open = true
	_modal.visible = true
	_modal.move_to_front()

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_backdrop.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.pivot_offset = Vector2(220.0, 105.0)
	_panel.scale = Vector2(0.94, 0.94)

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_panel, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_modal() -> void:
	if not _is_open or not _modal:
		return
	_is_open = false

	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween().set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim_tween.chain().tween_callback(func(): _modal.visible = false)


func _on_confirm_delete_pressed() -> void:
	if _is_profile_running_or_busy():
		SfxManager.error()
		_update_translations()
		return
	close_modal()
	if ProfileManager and ProfileManager.has_method("delete_all_profiles"):
		ProfileManager.delete_all_profiles()


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		SfxManager.cancel()
		close_modal()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed():
		SfxManager.cancel()
		close_modal()
		get_viewport().set_input_as_handled()


func _find_profile_grid() -> Node:
	for node in get_tree().root.find_children("*", "", true, false):
		if node.has_method("get_running_profile_name") and node.has_method("save_running_session"):
			return node
	return null

