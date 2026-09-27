@tool
class_name ProfileButton
extends Control

# A single profile card in the grid.

@export_group("Glow Settings")
# Preview glow in the editor.
@export var preview_glow: bool = false:
	set(value):
		preview_glow = value
		_update_glow_preview()

@export var glow_color: Color = Color(0.7843, 0.6667, 0.4314, 0.65):
	set(value):
		glow_color = value
		_update_glow()

@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 0.35:
	set(value):
		glow_intensity = value
		_update_glow()

@export_range(0.5, 6.0, 0.1) var glow_spread: float = 2.8:
	set(value):
		glow_spread = value
		_update_glow()

@export var glow_rect_size: Vector2 = Vector2(0.26, 0.10):
	set(value):
		glow_rect_size = value
		_update_glow()

signal client_toggled(profile_button: Control, is_starting: bool)
signal delete_requested(profile_button: Control)
signal edit_requested(profile_button: Control)

const PLAY_ICON_CLASSIC: Texture2D = preload("res://assets/icons/ui/icon_play.png")
const STOP_ICON_CLASSIC: Texture2D = preload("res://assets/icons/ui/icon_stop.png")
const PLAY_ICON_CYBERPUNK: Texture2D = preload("res://assets/icons/hextech/icon_play.png")
const STOP_ICON_CYBERPUNK: Texture2D = preload("res://assets/icons/hextech/icon_stop.png")
const COLOR_HEXTECH_GOLD_BORDER := Color(0.4706, 0.3529, 0.1569, 0.9)
const COLOR_HEXTECH_HOVER_BORDER := Color(0.9412, 0.902, 0.8235, 1.0)
const COLOR_ACTIVE_RED := Color(1.0, 0.04, 0.14, 1.0)
const COLOR_ICON_IDLE := Color(0.8039, 0.7451, 0.5686, 1.0)
const COLOR_ICON_HOVER := Color(0.9412, 0.902, 0.8235, 1.0)
const DRAG_THRESHOLD := 6.0
const HOVER_FADE_IN_TIME := 0.08
const HOVER_FADE_OUT_TIME := 0.08
const HOVER_SCALE_FACTOR := 1.04

# Full profile dictionary from ProfileManager.
var profile_data: Dictionary = {}:
	set(val):
		profile_data = val
		if is_instance_valid(_hover_info) and _hover_info.visible:
			_show_hover_info()

var client_is_running := false
var _pending_toggle_state: bool = false
var _has_pending_toggle: bool = false
var _is_interactable := true
var _is_transitioning := false

@export var is_preview: bool = false:
	set(value):
		if is_preview == value:
			return
		is_preview = value
		if is_node_ready():
			_apply_preview_mode(is_preview)

# Drag & click state
var _is_mouse_down := false
var _drag_start_pos := Vector2.ZERO

@onready var _context_menu: Control = get_node_or_null("card/context_menu")
@onready var _context_separator: HSeparator = get_node_or_null("card/context_menu/vbox/separator") as HSeparator
@onready var _delete_button: BaseButton = (find_child("delete_button", true, false) as BaseButton)
@onready var _edit_button: BaseButton = (find_child("edit_button", true, false) as BaseButton)
@onready var _glow_effect: Control = $glow if has_node("glow") else find_child("glow", true, false)
@onready var _button: Button = get_node_or_null("card/card_inner/Button")
@onready var _button_panel: Panel = get_node_or_null("card/card_inner/Button/Panel")
@onready var _state_icon: TextureRect = get_node_or_null("card/card_inner/Button/TextureRect")
@onready var _card: Control = get_node_or_null("card")
@onready var _card_panel: Panel = get_node_or_null("card/Panel") as Panel
@onready var _hextech_frame: Panel = get_node_or_null("card/hextech_frame")
@onready var _hover_info: Control = $hover_info if has_node("hover_info") else null
@onready var _name_level_row: Control = $hover_info/vbox/name_level_row if has_node("hover_info/vbox/name_level_row") else find_child("name_level_row", true, false)
@onready var _summoner_name: Label = $hover_info/vbox/name_level_row/summoner_name if has_node("hover_info/vbox/name_level_row/summoner_name") else find_child("summoner_name", true, false)
@onready var _summoner_level: Label = $hover_info/vbox/name_level_row/summoner_level if has_node("hover_info/vbox/name_level_row/summoner_level") else find_child("summoner_level", true, false)
@onready var _rank_badge: TextureRect = $hover_info/vbox/rank_row/rank_badge if has_node("hover_info/vbox/rank_row/rank_badge") else find_child("rank_badge", true, false)
@onready var _rank_tier_label: Label = $hover_info/vbox/rank_row/rank_tier_label if has_node("hover_info/vbox/rank_row/rank_tier_label") else find_child("rank_tier_label", true, false)
@onready var _separator: Control = $hover_info/vbox/separator if has_node("hover_info/vbox/separator") else find_child("separator", true, false)
@onready var _desc_label: Label = $hover_info/vbox/desc_label if has_node("hover_info/vbox/desc_label") else (find_child("desc_label", true, false) as Label)
@onready var _profile_name_label: Label = get_node_or_null("profile_name") if has_node("profile_name") else (find_child("profile_name", true, false) as Label)
@onready var _progress_bar: ProgressBar = get_node_or_null("card/Panel/ProgressBar") as ProgressBar

const RANKS_DIR := "res://assets/icons/ranks/"

const ACCENT_PRESETS: Dictionary = {
	"red": Color("ff0000"),
	"white": Color("f0e6d2"),
	"blue": Color("4f8fd8"),
	"gold": Color("c8aa6e"),
	"green": Color("45b878"),
	"violet": Color("9b70d8"),
	"cyan": Color("39c6c8"),
	"orange": Color("e08a3e"),
	"pink": Color("d96b9b"),
	"gray": Color("858b95"),
}

const TIER_COLORS: Dictionary = {
	"IRON": Color("a19d94"),
	"BRONZE": Color("cd7f32"),
	"SILVER": Color("b5c4d4"),
	"GOLD": Color("f1a80a"),
	"PLATINUM": Color("20c5a0"),
	"EMERALD": Color("12cc73"),
	"DIAMOND": Color("4aa7ff"),
	"MASTER": Color("a855f7"),
	"GRANDMASTER": Color("ef4444"),
	"CHALLENGER": Color("f59e0b"),
	"UNRANKED": Color("a09b8c"),
}

const TIER_NAMES: Dictionary = {
	"IRON": "Iron",
	"BRONZE": "Bronze",
	"SILVER": "Silver",
	"GOLD": "Gold",
	"PLATINUM": "Platinum",
	"EMERALD": "Emerald",
	"DIAMOND": "Diamond",
	"MASTER": "Master",
	"GRANDMASTER": "Grandmaster",
	"CHALLENGER": "Challenger",
	"UNRANKED": "Unranked",
}

static var _badge_cache: Dictionary = {}
static var is_any_card_dragging: bool = false
static var active_context_card: ProfileButton = null

var _hover_tween: Tween = null
var _glow_tween: Tween = null
var _accent_color: Color = Color("c8aa6e")
var _orig_card_panel_sb: StyleBox = null
var _orig_button_panel_sb: StyleBox = null
var _orig_hextech_frame_sb: StyleBox = null
var _orig_context_menu_sb: StyleBox = null
var _orig_hover_info_sb: StyleBox = null
var _orig_item_hover_sb: StyleBox = null


func _get_configured_accent_color() -> Color:
	if Engine.is_editor_hint():
		return _accent_color
	var preset := String(ConfigManager.get_value("AccentColor", "white")).to_lower()
	return ACCENT_PRESETS.get(preset, ACCENT_PRESETS["white"])


func _get_configured_ui_style() -> String:
	if Engine.is_editor_hint():
		return "fancy"
	return String(ConfigManager.get_value("UIStyle", "clean")).to_lower()


func _is_clean_ui() -> bool:
	return _get_configured_ui_style() == "clean"


func _is_league_ui() -> bool:
	return _get_configured_ui_style() == "league_client"


func _play_icon_tex() -> Texture2D:
	return PLAY_ICON_CLASSIC if _is_clean_ui() else PLAY_ICON_CYBERPUNK


func _stop_icon_tex() -> Texture2D:
	return STOP_ICON_CLASSIC if _is_clean_ui() else STOP_ICON_CYBERPUNK


func _idle_icon_color() -> Color:
	if _is_clean_ui():
		return Color.WHITE
	if _is_league_ui():
		return Color(0.80, 0.98, 0.98, 1.0)
	return _accent_color


func _idle_glow_color() -> Color:
	if _is_clean_ui():
		return Color(1.0, 0.0392, 0.1412, 0.6275)
	if _is_league_ui():
		return Color(0.7843, 0.6078, 0.2353, 0.68)
	return _accent_color


func _ensure_original_styleboxes() -> void:
	if _orig_card_panel_sb == null and _card_panel:
		_orig_card_panel_sb = _duplicate_stylebox_deep(_card_panel.get_theme_stylebox("panel"))
	if _orig_button_panel_sb == null and _button_panel:
		_orig_button_panel_sb = _duplicate_stylebox_deep(_button_panel.get_theme_stylebox("panel"))
	if _orig_hextech_frame_sb == null and _hextech_frame:
		_orig_hextech_frame_sb = _duplicate_stylebox_deep(_hextech_frame.get_theme_stylebox("panel"))
	if _orig_context_menu_sb == null and _context_menu:
		_orig_context_menu_sb = _duplicate_stylebox_deep(_context_menu.get_theme_stylebox("panel"))
	if _orig_hover_info_sb == null and _hover_info:
		_orig_hover_info_sb = _duplicate_stylebox_deep(_hover_info.get_theme_stylebox("panel"))
	if _orig_item_hover_sb == null and _edit_button and _edit_button is Control:
		_orig_item_hover_sb = _duplicate_stylebox_deep((_edit_button as Control).get_theme_stylebox("hover"))


func _on_configs_updated(new_config: Dictionary) -> void:
	var preset := String(new_config.get("AccentColor", "white")).to_lower()
	var col: Color = ACCENT_PRESETS.get(preset, ACCENT_PRESETS["white"])
	set_accent_color(col)


func set_accent_color(accent: Color) -> void:
	_ensure_original_styleboxes()
	_accent_color = accent
	var is_clean := _is_clean_ui()
	var is_league := _is_league_ui()
	var lcu_gold := Color(0.7843, 0.6078, 0.2353, 1.0)
	var eff_accent := lcu_gold if is_league else accent
	var target_glow := _idle_glow_color()
	if not client_is_running:
		glow_color = target_glow
	var card_inner := get_node_or_null("card/card_inner") as Control
	if card_inner:
		card_inner.offset_left = -48.0 if is_clean else -46.0
	if _state_icon:
		var half := 12.0 if is_clean else 10.0
		_state_icon.offset_left = -half
		_state_icon.offset_top = -half
		_state_icon.offset_right = half
		_state_icon.offset_bottom = half
		_state_icon.texture = _stop_icon_tex() if client_is_running else _play_icon_tex()
	if _card_panel and _orig_card_panel_sb:
		var c_sb := _duplicate_stylebox_deep(_orig_card_panel_sb)
		if is_clean and c_sb is StyleBoxFancy:
			var cf := c_sb as StyleBoxFancy
			var empty_borders: Array[StyleBorder] = []
			cf.borders = empty_borders
			cf.corner_detail = 12
			cf.corner_radius_top_left = 8
			cf.corner_radius_top_right = 8
			cf.corner_radius_bottom_right = 8
			cf.corner_radius_bottom_left = 8
			cf.corner_curvature_top_left = 1.0
			cf.corner_curvature_top_right = 1.0
			cf.corner_curvature_bottom_right = 1.0
			cf.corner_curvature_bottom_left = 1.0
		elif is_league and c_sb is StyleBoxFancy:
			var lcf := c_sb as StyleBoxFancy
			var empty_lcu: Array[StyleBorder] = []
			lcf.borders = empty_lcu
			lcf.corner_radius_top_left = 0
			lcf.corner_radius_top_right = 0
			lcf.corner_radius_bottom_right = 0
			lcf.corner_radius_bottom_left = 0
		_card_panel.add_theme_stylebox_override("panel", c_sb)
	if client_is_running:
		_set_frame_border_color(COLOR_ACTIVE_RED)
	else:
		_set_frame_border_color(eff_accent)
		if _state_icon:
			_state_icon.modulate = _idle_icon_color()
	if _profile_name_label:
		_profile_name_label.add_theme_color_override("font_color", Color.WHITE if is_clean else Color(0.9412, 0.902, 0.8235, 1))
	if _progress_bar:
		var fill := _progress_bar.get_theme_stylebox("fill")
		if fill:
			var fill_copy := fill.duplicate(true) as StyleBox
			if fill_copy is StyleBoxFlat:
				var fill_flat := fill_copy as StyleBoxFlat
				var alpha := fill_flat.bg_color.a
				var bar_col := Color(1.0, 0.04, 0.14, 1.0) if is_clean else (Color(0.04, 0.78, 0.73, 1.0) if is_league else accent)
				fill_flat.bg_color = bar_col
				fill_flat.bg_color.a = alpha if alpha > 0.01 else 0.9
				_progress_bar.add_theme_stylebox_override("fill", fill_copy)
	if _glow_effect and _glow_effect.material is ShaderMaterial:
		var mat := _glow_effect.material as ShaderMaterial
		var gcol := Color(1.0, 0.04, 0.14, 0.85) if client_is_running else target_glow
		mat.set_shader_parameter("glow_color", gcol)
		mat.set_shader_parameter("glow_color_secondary", gcol.darkened(0.25))
	var popup_bg := Color(0.0039, 0.0392, 0.0745, 0.98) if is_league else Color(0.07058824, 0.07058824, 0.07058824, 1.0)
	if _context_menu and _orig_context_menu_sb:
		var ctx_sb := _duplicate_stylebox_deep(_orig_context_menu_sb)
		if ctx_sb is StyleBoxFancy:
			var cfancy := ctx_sb as StyleBoxFancy
			cfancy.color = popup_bg
			if is_clean:
				var b := StyleBorder.new()
				b.set_width_all(1)
				b.color = Color(1.0, 1.0, 1.0, 0.1686)
				var clean_borders: Array[StyleBorder] = [b]
				cfancy.borders = clean_borders
				cfancy.corner_detail = 12
				cfancy.corner_radius_top_left = 6
				cfancy.corner_radius_top_right = 6
				cfancy.corner_radius_bottom_right = 6
				cfancy.corner_radius_bottom_left = 6
				cfancy.corner_curvature_top_left = 1.0
				cfancy.corner_curvature_top_right = 1.0
				cfancy.corner_curvature_bottom_right = 1.0
				cfancy.corner_curvature_bottom_left = 1.0
			elif is_league:
				var lb_outer := StyleBorder.new()
				lb_outer.width_top = 2
				lb_outer.width_left = 1
				lb_outer.width_right = 1
				lb_outer.width_bottom = 1
				lb_outer.color = Color(0.7843, 0.6078, 0.2353, 0.95)
				var lb_inner := StyleBorder.new()
				lb_inner.set_width_all(1)
				lb_inner.set_inset_all(2)
				lb_inner.color = Color(0.7843, 0.6667, 0.4314, 0.22)
				var lcu_ctx_borders: Array[StyleBorder] = [lb_outer, lb_inner]
				cfancy.borders = lcu_ctx_borders
				cfancy.corner_radius_top_left = 0
				cfancy.corner_radius_top_right = 0
				cfancy.corner_radius_bottom_right = 0
				cfancy.corner_radius_bottom_left = 0
			else:
				if cfancy.borders.size() > 0 and cfancy.borders[0] != null:
					cfancy.borders[0].color = Color(accent.r, accent.g, accent.b, 0.92)
				if cfancy.borders.size() > 1 and cfancy.borders[1] != null:
					cfancy.borders[1].color = Color(accent.r, accent.g, accent.b, 0.25)
		elif ctx_sb is StyleBoxFlat:
			(ctx_sb as StyleBoxFlat).bg_color = popup_bg
			(ctx_sb as StyleBoxFlat).border_color = Color(1, 1, 1, 0.1686) if is_clean else Color(eff_accent.r, eff_accent.g, eff_accent.b, 0.92)
		_context_menu.add_theme_stylebox_override("panel", ctx_sb)
	if _context_separator:
		var sep_sb := _context_separator.get_theme_stylebox("separator")
		if sep_sb is StyleBoxLine:
			var sep_line := (sep_sb as StyleBoxLine).duplicate() as StyleBoxLine
			sep_line.color = Color(1.0, 1.0, 1.0, 0.08) if is_clean else Color(eff_accent.r, eff_accent.g, eff_accent.b, 0.72)
			_context_separator.add_theme_stylebox_override("separator", sep_line)
	for btn in [_edit_button, _delete_button]:
		if btn and btn is Control and _orig_item_hover_sb:
			var ctrl := btn as Control
			for sname in [&"hover", &"pressed"]:
				var item_sname: StringName = sname
				var hsb := _duplicate_stylebox_deep(_orig_item_hover_sb)
				if hsb is StyleBoxFancy:
					var hfancy := hsb as StyleBoxFancy
					if is_clean:
						hfancy.color = Color(0.115, 0.115, 0.115, 1.0)
						var empty_borders: Array[StyleBorder] = []
						hfancy.borders = empty_borders
						hfancy.corner_detail = 12
						hfancy.corner_radius_top_left = 5
						hfancy.corner_radius_top_right = 5
						hfancy.corner_radius_bottom_right = 5
						hfancy.corner_radius_bottom_left = 5
						hfancy.corner_curvature_top_left = 1.0
						hfancy.corner_curvature_top_right = 1.0
						hfancy.corner_curvature_bottom_right = 1.0
						hfancy.corner_curvature_bottom_left = 1.0
					elif is_league:
						hfancy.color = Color(0.1176, 0.1373, 0.1569, 0.96)
						var lb_hov := StyleBorder.new()
						lb_hov.set_width_all(1)
						lb_hov.color = Color(0.7843, 0.6667, 0.4314, 0.85)
						var lcu_hov_borders: Array[StyleBorder] = [lb_hov]
						hfancy.borders = lcu_hov_borders
						hfancy.corner_radius_top_left = 0
						hfancy.corner_radius_top_right = 0
						hfancy.corner_radius_bottom_right = 0
						hfancy.corner_radius_bottom_left = 0
					else:
						if hfancy.borders.size() > 0 and hfancy.borders[0] != null:
							hfancy.borders[0].color = Color(accent.r, accent.g, accent.b, 0.75)
					ctrl.add_theme_stylebox_override(item_sname, hfancy)
	if _hover_info and _orig_hover_info_sb:
		var hov_sb := _duplicate_stylebox_deep(_orig_hover_info_sb)
		if hov_sb is StyleBoxFancy:
			var hofancy := hov_sb as StyleBoxFancy
			hofancy.color = popup_bg
			if is_clean:
				var hb := StyleBorder.new()
				hb.set_width_all(1)
				hb.color = Color(1.0, 1.0, 1.0, 0.1686)
				var h_borders: Array[StyleBorder] = [hb]
				hofancy.borders = h_borders
				hofancy.corner_detail = 12
				hofancy.corner_curvature_top_left = 1.0
				hofancy.corner_curvature_top_right = 1.0
				hofancy.corner_curvature_bottom_right = 1.0
				hofancy.corner_curvature_bottom_left = 1.0
				hofancy.corner_radius_top_left = 6
				hofancy.corner_radius_top_right = 6
				hofancy.corner_radius_bottom_right = 6
				hofancy.corner_radius_bottom_left = 6
			elif is_league:
				var lhb_outer := StyleBorder.new()
				lhb_outer.width_top = 2
				lhb_outer.width_left = 1
				lhb_outer.width_right = 1
				lhb_outer.width_bottom = 1
				lhb_outer.color = Color(0.7843, 0.6078, 0.2353, 0.95)
				var lhb_inner := StyleBorder.new()
				lhb_inner.set_width_all(1)
				lhb_inner.set_inset_all(2)
				lhb_inner.color = Color(0.7843, 0.6667, 0.4314, 0.22)
				var lcu_hov_b: Array[StyleBorder] = [lhb_outer, lhb_inner]
				hofancy.borders = lcu_hov_b
				hofancy.corner_radius_top_left = 0
				hofancy.corner_radius_top_right = 0
				hofancy.corner_radius_bottom_right = 0
				hofancy.corner_radius_bottom_left = 0
			else:
				if hofancy.borders.size() > 0 and hofancy.borders[0] != null:
					hofancy.borders[0].color = Color(accent.r, accent.g, accent.b, 0.92)
				if hofancy.borders.size() > 1 and hofancy.borders[1] != null:
					hofancy.borders[1].color = Color(accent.r, accent.g, accent.b, 0.25)
		elif hov_sb is StyleBoxFlat:
			(hov_sb as StyleBoxFlat).bg_color = popup_bg
			(hov_sb as StyleBoxFlat).border_color = Color(1, 1, 1, 0.1686) if is_clean else Color(eff_accent.r, eff_accent.g, eff_accent.b, 0.92)
		_hover_info.add_theme_stylebox_override("panel", hov_sb)
	if _separator:
		var hsep_sb := _separator.get_theme_stylebox("separator")
		if hsep_sb is StyleBoxLine:
			var hsep_line := (hsep_sb as StyleBoxLine).duplicate() as StyleBoxLine
			hsep_line.color = Color(1.0, 1.0, 1.0, 0.08) if is_clean else Color(eff_accent.r, eff_accent.g, eff_accent.b, 0.72)
			_separator.add_theme_stylebox_override("separator", hsep_line)
	if _summoner_level:
		_summoner_level.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75) if is_clean else eff_accent)
	if _summoner_name:
		_summoner_name.add_theme_color_override("font_color", Color.WHITE if is_clean else Color(0.9412, 0.902, 0.8235, 1.0))


static func is_any_context_menu_open() -> bool:
	return active_context_card != null and is_instance_valid(active_context_card) and active_context_card._context_menu != null and active_context_card._context_menu.visible


var profile_name: String:
	get: return profile_data.get("profile_name", "")


func _duplicate_stylebox_deep(sb: StyleBox) -> StyleBox:
	if sb == null:
		return null
	var copy: StyleBox = sb.duplicate(true)
	if copy is StyleBoxFancy:
		var fancy := copy as StyleBoxFancy
		var new_borders: Array[StyleBorder] = []
		for b in fancy.borders:
			if b != null:
				new_borders.append(b.duplicate() as StyleBorder)
		fancy.borders = new_borders
	return copy


func _ready() -> void:
	if _glow_effect and _glow_effect.material is ShaderMaterial:
		_glow_effect.material = (_glow_effect.material as ShaderMaterial).duplicate()
	_ensure_original_styleboxes()

	if not Engine.is_editor_hint():
		_accent_color = _get_configured_accent_color()
		if not ConfigManager.configs_updated.is_connected(_on_configs_updated):
			ConfigManager.configs_updated.connect(_on_configs_updated)

	glow_color = _accent_color
	_update_glow()
	_update_glow_preview()

	if Engine.is_editor_hint():
		return

	if get_parent() and get_parent().name == "preview":
		is_preview = true

	if _delete_button:
		_delete_button.pressed.connect(_on_delete_button_pressed)
		_delete_button.set_meta("sfx", &"cancel")
		if _delete_button is Button:
			var delete_button := _delete_button as Button
			delete_button.text = tr("Delete")
			delete_button.add_theme_color_override("font_color", Color.WHITE)
			delete_button.add_theme_color_override("font_hover_color", Color.WHITE)
			delete_button.add_theme_color_override("font_pressed_color", Color.WHITE)
			delete_button.add_theme_color_override("font_focus_color", Color.WHITE)
			delete_button.add_theme_color_override("icon_normal_color", Color.WHITE)
			delete_button.add_theme_color_override("icon_hover_color", Color.WHITE)
			delete_button.add_theme_color_override("icon_pressed_color", Color.WHITE)
			delete_button.add_theme_color_override("icon_focus_color", Color.WHITE)
	if _edit_button:
		_edit_button.pressed.connect(_on_edit_button_pressed)
		if _edit_button is Button:
			var edit_button := _edit_button as Button
			edit_button.text = tr("Edit")
			edit_button.add_theme_color_override("font_color", Color.WHITE)
			edit_button.add_theme_color_override("font_hover_color", Color.WHITE)
			edit_button.add_theme_color_override("font_pressed_color", Color.WHITE)
			edit_button.add_theme_color_override("font_focus_color", Color.WHITE)
			edit_button.add_theme_color_override("icon_normal_color", Color.WHITE)
			edit_button.add_theme_color_override("icon_hover_color", Color.WHITE)
			edit_button.add_theme_color_override("icon_pressed_color", Color.WHITE)
			edit_button.add_theme_color_override("icon_focus_color", Color.WHITE)
	if _card:
		_card.set_meta("sfx_no_hover", true)
		_card.gui_input.connect(_on_card_gui_input)
	if _button and _button is Button:
		if not _button.pressed.is_connected(_on_profile_button_pressed):
			_button.pressed.connect(_on_profile_button_pressed)
		if not _button.button_down.is_connected(_on_profile_button_down):
			_button.button_down.connect(_on_profile_button_down)
		_button.set_meta("sfx", &"confirm")
		_button.set_meta("sfx_no_hover", true)
		_button.mouse_entered.connect(_on_card_mouse_entered)
		_button.mouse_exited.connect(_on_card_mouse_exited)
	if _context_menu:
		_context_menu.top_level = true
		_context_menu.z_index = 300
		_context_menu.z_as_relative = false
		_context_menu.visible = false
	if not visibility_changed.is_connected(_on_self_visibility_changed):
		visibility_changed.connect(_on_self_visibility_changed)
	if _hover_info:
		_hover_info.visible = false
		_hover_info.custom_minimum_size = Vector2(280.0, 0.0)
		_hover_info.size = Vector2(280.0, 0.0)
		var vbox: Control = _hover_info.get_node_or_null("vbox")
		if vbox:
			vbox.custom_minimum_size = Vector2(244.0, 0.0)
			vbox.size = Vector2(244.0, 0.0)
		if _desc_label:
			_desc_label.custom_minimum_size = Vector2(244.0, 0.0)
			_desc_label.size = Vector2(244.0, 0.0)
	if _glow_effect:
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)
		_glow_effect.pivot_offset = _glow_effect.size * 0.5

	set_accent_color(_accent_color)

	if is_preview:
		_apply_preview_mode(true)
	else:
		set_process_input(true)


func _exit_tree() -> void:
	if active_context_card == self:
		active_context_card = null


func _on_self_visibility_changed() -> void:
	if not is_visible_in_tree():
		hide_context_menu()


func set_preview_mode(enabled: bool = true) -> void:
	is_preview = enabled
	_apply_preview_mode(enabled)


func _apply_preview_mode(enabled: bool) -> void:
	_is_interactable = not enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	set_process_input(not enabled)
	if _card:
		_card.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		_card.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_card.set_meta("sfx_silent", enabled)
		if _card is BaseButton:
			(_card as BaseButton).disabled = enabled
	var card_inner := get_node_or_null("card/card_inner") as Control
	if card_inner:
		card_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		card_inner.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _button:
		_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
		_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_button.set_meta("sfx_silent", enabled)
		_button.disabled = enabled
	if enabled:
		if _glow_effect:
			_glow_effect.modulate.a = 0.0
			_glow_effect.visible = false
		if _hover_info:
			_hover_info.visible = false
		if _context_menu:
			_context_menu.visible = false


func _set_frame_border_color(col: Color) -> void:
	_ensure_original_styleboxes()
	var is_clean := _is_clean_ui()
	var is_league := _is_league_ui()
	var is_running_col := (col == COLOR_ACTIVE_RED)
	var eff_col := col
	if is_league and not is_running_col:
		eff_col = Color(0.7843, 0.6078, 0.2353, 0.96)
	if _hextech_frame:
		_hextech_frame.visible = not is_clean
		if not is_clean and _orig_hextech_frame_sb:
			var sb: StyleBox = _duplicate_stylebox_deep(_orig_hextech_frame_sb)
			if sb is StyleBoxFancy:
				var fancy := sb as StyleBoxFancy
				if is_league:
					fancy.corner_radius_top_left = 0
					fancy.corner_radius_top_right = 0
					fancy.corner_radius_bottom_right = 0
					fancy.corner_radius_bottom_left = 0
				if fancy.borders.size() > 0 and fancy.borders[0] != null:
					fancy.borders[0].color = eff_col
				if fancy.borders.size() > 1 and fancy.borders[1] != null:
					fancy.borders[1].color = Color(eff_col.r, eff_col.g, eff_col.b, 0.28 if is_league else 0.25)
			elif sb is StyleBoxFlat:
				(sb as StyleBoxFlat).border_color = eff_col
			_hextech_frame.add_theme_stylebox_override("panel", sb)
	if _button_panel and _orig_button_panel_sb:
		var bsb: StyleBox = _duplicate_stylebox_deep(_orig_button_panel_sb)
		if bsb is StyleBoxFancy:
			var bfancy := bsb as StyleBoxFancy
			if is_clean:
				var empty_borders: Array[StyleBorder] = []
				bfancy.borders = empty_borders
				bfancy.corner_detail = 12
				bfancy.corner_radius_top_left = 0
				bfancy.corner_radius_top_right = 8
				bfancy.corner_radius_bottom_right = 8
				bfancy.corner_radius_bottom_left = 0
				bfancy.corner_curvature_top_left = 1.0
				bfancy.corner_curvature_top_right = 1.0
				bfancy.corner_curvature_bottom_right = 1.0
				bfancy.corner_curvature_bottom_left = 1.0
			elif is_league:
				bfancy.corner_radius_top_left = 0
				bfancy.corner_radius_top_right = 0
				bfancy.corner_radius_bottom_right = 0
				bfancy.corner_radius_bottom_left = 0
				if is_running_col:
					bfancy.color = Color(0.14, 0.02, 0.04, 0.92)
					var rb_left := StyleBorder.new()
					rb_left.width_left = 1
					rb_left.color = COLOR_ACTIVE_RED
					var rb_in := StyleBorder.new()
					rb_in.set_width_all(1)
					rb_in.set_inset_all(3)
					rb_in.color = Color(1.0, 0.04, 0.14, 0.55)
					var run_borders: Array[StyleBorder] = [rb_left, rb_in]
					bfancy.borders = run_borders
				else:
					bfancy.color = Color(0.0235, 0.1255, 0.1882, 0.94)
					var lb_div := StyleBorder.new()
					lb_div.width_left = 1
					lb_div.color = Color(0.7843, 0.6078, 0.2353, 0.92)
					var lb_cyan := StyleBorder.new()
					lb_cyan.set_width_all(1)
					lb_cyan.set_inset_all(3)
					lb_cyan.color = Color(0.04, 0.78, 0.73, 0.85)
					var play_borders: Array[StyleBorder] = [lb_div, lb_cyan]
					bfancy.borders = play_borders
			else:
				if bfancy.borders.size() > 0 and bfancy.borders[0] != null:
					bfancy.borders[0].color = Color(col.r, col.g, col.b, 0.75)
				if bfancy.borders.size() > 1 and bfancy.borders[1] != null:
					bfancy.borders[1].color = Color(col.r, col.g, col.b, 0.22)
		elif bsb is StyleBoxFlat:
			(bsb as StyleBoxFlat).border_color = Color(eff_col.r, eff_col.g, eff_col.b, 0.0 if is_clean else 0.75)
		_button_panel.add_theme_stylebox_override("panel", bsb)


func _update_glow() -> void:
	var glow_node: Control = _glow_effect if _glow_effect else (get_node_or_null("glow") as Control)
	if not glow_node or not glow_node.material is ShaderMaterial:
		return
	var mat: ShaderMaterial = glow_node.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", glow_rect_size)
	mat.set_shader_parameter("bness", glow_intensity)
	mat.set_shader_parameter("fall_off_scale", glow_spread)
	mat.set_shader_parameter("glow_color", glow_color)
	mat.set_shader_parameter("glow_color_secondary", glow_color.darkened(0.25))


func _update_glow_preview() -> void:
	var glow_node: Control = _glow_effect if _glow_effect else (get_node_or_null("glow") as Control)
	if not glow_node:
		return
	if is_preview and not Engine.is_editor_hint():
		glow_node.modulate.a = 0.0
		glow_node.visible = false
		return
	if preview_glow:
		glow_node.modulate.a = 1.0
		glow_node.scale = Vector2(1.04, 1.04)
	else:
		if Engine.is_editor_hint():
			glow_node.modulate.a = 0.0
			glow_node.scale = Vector2(0.96, 0.96)



# Confirms the client for this profile is now running.
func confirm_started() -> void:
	client_is_running = true
	_is_transitioning = false
	glow_color = Color(1.0, 0.04, 0.14, 0.85)
	_set_frame_border_color(COLOR_ACTIVE_RED)
	if _glow_effect:
		_glow_effect.modulate.a = 0.75
		_glow_effect.scale = Vector2(1.02, 1.02)
	if _state_icon:
		_state_icon.texture = _stop_icon_tex()
		_state_icon.modulate = COLOR_ACTIVE_RED


# Confirms the client was stopped and the session saved.
func confirm_stopped() -> void:
	client_is_running = false
	_is_transitioning = false
	glow_color = _idle_glow_color()
	_set_frame_border_color(_accent_color)
	if _glow_effect and not get_global_rect().has_point(get_global_mouse_position()):
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)
	if _state_icon:
		_state_icon.texture = _play_icon_tex()
		_state_icon.modulate = _idle_icon_color()


# Reverts the toggle after a failed start/stop attempt.
func reset_toggle_state() -> void:
	client_is_running = false
	_is_transitioning = false
	glow_color = _idle_glow_color()
	_set_frame_border_color(_accent_color)
	if _glow_effect and not get_global_rect().has_point(get_global_mouse_position()):
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)
	if _state_icon:
		_state_icon.texture = _play_icon_tex()
		_state_icon.modulate = _idle_icon_color()



func _on_profile_button_pressed() -> void:
	if is_preview or not _is_interactable or _is_transitioning:
		return
	if is_any_context_menu_open():
		if active_context_card and is_instance_valid(active_context_card):
			active_context_card.hide_context_menu()
		return
	_is_transitioning = true
	var starting := _pending_toggle_state if _has_pending_toggle else not client_is_running
	_has_pending_toggle = false

	if starting:
		glow_color = Color(1.0, 0.04, 0.14, 0.85)
		_set_frame_border_color(COLOR_ACTIVE_RED)

	# Immediately switch icon with punchy pop animation for instant UI responsiveness
	if _state_icon:
		_state_icon.pivot_offset = _state_icon.size * 0.5
		_state_icon.texture = _stop_icon_tex() if starting else _play_icon_tex()
		_state_icon.modulate = COLOR_ACTIVE_RED if starting else (_idle_icon_color() if _is_clean_ui() else _accent_color.lightened(0.18))
		_state_icon.scale = Vector2(1.28, 1.28)
		var icon_tw := create_tween()
		icon_tw.tween_property(_state_icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	client_toggled.emit(self, starting)


func _on_profile_button_down() -> void:
	# Update the icon on mouse-down, before the pressed signal and before any
	# client/profile operation starts, so the click has immediate feedback.
	if is_preview or not _is_interactable or _is_transitioning:
		return
	var starting := not client_is_running
	var grid := get_parent()
	if grid and grid.has_method("_disable_other_buttons"):
		# Start the other-card juice on mouse-down, not after process validation.
		grid._disable_other_buttons(self)
	_pending_toggle_state = starting
	_has_pending_toggle = true
	# Keep the visual state stable while ConfigManager/process startup emits updates.
	client_is_running = starting
	if starting:
		glow_color = Color(1.0, 0.04, 0.14, 0.85)
		_set_frame_border_color(COLOR_ACTIVE_RED)
	if _state_icon:
		_state_icon.texture = _stop_icon_tex() if starting else _play_icon_tex()
		_state_icon.modulate = COLOR_ACTIVE_RED if starting else _idle_icon_color()


func _on_delete_button_pressed() -> void:
	hide_context_menu()
	if client_is_running or _is_transitioning:
		printerr("Cannot delete profile while its client is running.")
		return
	delete_requested.emit(self)


func _on_edit_button_pressed() -> void:
	hide_context_menu()
	if client_is_running or _is_transitioning:
		printerr("Cannot edit profile while its client is running.")
		return
	edit_requested.emit(self)


func _open_context_menu() -> void:
	if not _context_menu:
		return
	if active_context_card != null and active_context_card != self and is_instance_valid(active_context_card):
		active_context_card.hide_context_menu()
	var parent_grid := get_parent()
	if parent_grid:
		for sibling in parent_grid.get_children():
			if sibling is ProfileButton and sibling != self:
				(sibling as ProfileButton)._force_unhover()
	active_context_card = self
	z_index = 200
	_context_menu.top_level = true
	_context_menu.z_index = 300
	_context_menu.z_as_relative = false
	_context_menu.visible = true
	_hide_hover_info(true)
	_position_and_animate_context_menu()


func _force_unhover() -> void:
	if not client_is_running:
		_set_frame_border_color(_accent_color)
		if _state_icon:
			_state_icon.modulate = _idle_icon_color()
	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_effect.modulate.a = 0.75 if client_is_running else 0.0
		_glow_effect.scale = Vector2(1.02, 1.02) if client_is_running else Vector2(0.96, 0.96)
	_hide_hover_info(true)


# Handles right-click (context menu) and click-and-drag for grid reordering.
func _on_card_gui_input(event: InputEvent) -> void:
	if not _is_interactable or _is_transitioning:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			var opening := not (_context_menu and _context_menu.visible)
			if opening:
				_open_context_menu()
				SfxManager.open()
			else:
				hide_context_menu()
				SfxManager.cancel()
			get_viewport().set_input_as_handled()
			return

		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				if is_any_context_menu_open():
					if active_context_card and is_instance_valid(active_context_card):
						active_context_card.hide_context_menu()
					SfxManager.cancel()
					get_viewport().set_input_as_handled()
					return
				if profile_data.is_empty():
					return
				var parent_grid = get_parent()
				if parent_grid and parent_grid.has_method("_is_busy") and parent_grid._is_busy():
					return

				_is_mouse_down = true
				_drag_start_pos = event.global_position
				_hide_hover_info(true)
			else:
				var was_down := _is_mouse_down
				_is_mouse_down = false
				var parent_grid: Node = get_parent()
				var is_dragging: bool = is_any_card_dragging or (parent_grid != null and parent_grid.has_method("is_dragging_card") and bool(parent_grid.is_dragging_card()))
				if was_down and not is_dragging and get_global_rect().has_point(event.global_position):
					_on_card_mouse_entered()

	elif event is InputEventMouseMotion and _is_mouse_down:
		if event.global_position.distance_to(_drag_start_pos) >= DRAG_THRESHOLD:
			_is_mouse_down = false
			hide_context_menu()
			_hide_hover_info(true)
			var parent_grid = get_parent()
			if parent_grid and parent_grid.has_method("start_card_drag"):
				parent_grid.start_card_drag(self, event.global_position)


# Hides the context menu when clicking anywhere outside of it and blocks input from leaking to cards behind it.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _context_menu or not _context_menu.visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var mouse_pos := get_global_mouse_position()
		if not _context_menu.get_global_rect().has_point(mouse_pos):
			hide_context_menu()
			SfxManager.cancel()
			get_viewport().set_input_as_handled()


func _position_and_animate_context_menu() -> void:
	if not _context_menu:
		return
	var mouse_pos := get_global_mouse_position()
	var vp_size := get_viewport_rect().size
	var menu_size := _context_menu.size
	if menu_size == Vector2.ZERO:
		menu_size = Vector2(154, 86)

	# Keep fully visible inside the window boundaries
	var target_x: float = clampf(mouse_pos.x, 8.0, vp_size.x - menu_size.x - 8.0)
	var target_y: float = clampf(mouse_pos.y, 8.0, vp_size.y - menu_size.y - 8.0)
	_context_menu.global_position = Vector2(target_x, target_y)

	# Punchy, smooth entrance
	_context_menu.pivot_offset = Vector2(0, 0)
	_context_menu.scale = Vector2(0.92, 0.92)
	_context_menu.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_context_menu, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_context_menu, "modulate:a", 1.0, 0.10)



func _on_card_mouse_entered() -> void:
	if Engine.is_editor_hint() or not _is_interactable or _is_mouse_down or is_any_card_dragging or is_any_context_menu_open():
		return

	var parent_grid = get_parent()
	if parent_grid and parent_grid.has_method("is_dragging_card") and parent_grid.is_dragging_card():
		return

	if not client_is_running:
		_set_frame_border_color(_accent_color)
		if _state_icon:
			_state_icon.modulate = _idle_icon_color()

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_tween = create_tween()
		_glow_tween.tween_property(_glow_effect, "modulate:a", 1.0, HOVER_FADE_IN_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	_show_hover_info()


func _on_card_mouse_exited() -> void:
	if Engine.is_editor_hint() or not _is_interactable:
		return

	# If mouse is still within the profile card rect (e.g. over play button), don't exit hover
	var global_mouse := get_global_mouse_position()
	if get_global_rect().has_point(global_mouse):
		return

	if not client_is_running:
		_set_frame_border_color(_accent_color)
		if _state_icon:
			_state_icon.modulate = _idle_icon_color()

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		var target_alpha := 0.75 if client_is_running else 0.0
		_glow_tween = create_tween()
		_glow_tween.tween_property(_glow_effect, "modulate:a", target_alpha, HOVER_FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_hide_hover_info()


func _load_badge_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			return tex
	var real_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(real_path):
		var img := Image.load_from_file(real_path)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _resolve_rank_badge(tier: String) -> Texture2D:
	var clean_tier := tier.to_lower().strip_edges()
	if clean_tier.is_empty():
		clean_tier = "unranked"
	if _badge_cache.has(clean_tier):
		return _badge_cache[clean_tier]

	var cap := clean_tier.capitalize()
	var candidates := [
		"Season_2022_-_" + cap,
		"Season_2023_-_" + cap,
		clean_tier,
		cap,
		"Emblem_" + cap,
	]
	for cand in candidates:
		for ext in ["png", "webp", "svg", "jpg"]:
			var tex := _load_badge_texture(RANKS_DIR.path_join("%s.%s" % [cand, ext]))
			if tex:
				_badge_cache[clean_tier] = tex
				return tex

	# Fallback for missing tier emblems (e.g. older asset packs)
	if clean_tier == "emerald":
		var fallback_tex := _resolve_rank_badge("platinum")
		if fallback_tex:
			_badge_cache[clean_tier] = fallback_tex
			return fallback_tex
	elif clean_tier == "iron":
		var fallback_tex := _resolve_rank_badge("bronze")
		if fallback_tex:
			_badge_cache[clean_tier] = fallback_tex
			return fallback_tex

	_badge_cache[clean_tier] = null
	return null


func _show_hover_info() -> void:
	if not _hover_info or (_context_menu and _context_menu.visible) or is_any_context_menu_open() or not _is_interactable or _is_mouse_down or is_any_card_dragging:
		return

	var parent_grid = get_parent()
	if parent_grid and parent_grid.has_method("is_dragging_card") and parent_grid.is_dragging_card():
		return

	var raw_nick: String = profile_data.get("summoner_name", "").strip_edges()
	var display_nick: String = raw_nick if not raw_nick.is_empty() else profile_data.get("profile_name", "Account")
	var level: int = int(profile_data.get("summoner_level", 0))
	var tier: String = str(profile_data.get("rank_tier", "UNRANKED")).to_upper().strip_edges()
	if tier.is_empty():
		tier = "UNRANKED"
	var division: String = str(profile_data.get("rank_division", "")).to_upper().strip_edges()
	if division == "NA":
		division = ""
	var lp: int = int(profile_data.get("rank_lp", 0))
	var description: String = profile_data.get("description", "").strip_edges()

	var is_unscanned: bool = raw_nick.is_empty() and level <= 0

	# 1.
	if _name_level_row:
		_name_level_row.visible = not is_unscanned
	if _summoner_name:
		if is_unscanned:
			_summoner_name.visible = false
		else:
			_summoner_name.visible = true
			_summoner_name.text = raw_nick
	if _summoner_level:
		if not is_unscanned and level > 0:
			_summoner_level.visible = true
			_summoner_level.text = "Nv. %d" % level
		else:
			_summoner_level.visible = false

	# 2.
	if _rank_tier_label:
		if is_unscanned:
			_rank_tier_label.text = tr("Waiting for first login...")
			_rank_tier_label.add_theme_color_override("font_color", Color("888c98"))
		else:
			var tier_display: String = tr(TIER_NAMES.get(tier, tier.capitalize()))
			if tier != "UNRANKED" and not division.is_empty():
				_rank_tier_label.text = "%s %s - %d LP" % [tier_display, division, lp]
			elif tier != "UNRANKED":
				_rank_tier_label.text = "%s - %d LP" % [tier_display, lp]
			else:
				_rank_tier_label.text = tier_display

			var tier_color: Color = TIER_COLORS.get(tier, Color("888c98"))
			_rank_tier_label.add_theme_color_override("font_color", tier_color)

	# 3.
	if _rank_badge:
		var badge_tier := "UNRANKED" if is_unscanned else tier
		var badge_tex := _resolve_rank_badge(badge_tier)
		if badge_tex:
			_rank_badge.texture = badge_tex
			_rank_badge.visible = true
		else:
			_rank_badge.visible = false

	const HOVER_W := 280.0
	const CONTENT_W := 244.0 # HOVER_W - 18 - 18

	_hover_info.custom_minimum_size.x = HOVER_W
	_hover_info.size.x = HOVER_W
	var vbox: Control = _hover_info.get_node_or_null("vbox")
	if vbox:
		vbox.custom_minimum_size.x = CONTENT_W
		vbox.size.x = CONTENT_W

	# 4.
	var has_desc := not description.is_empty()
	if _separator:
		_separator.visible = has_desc
	if _desc_label:
		_desc_label.visible = has_desc
		_desc_label.custom_minimum_size = Vector2(CONTENT_W, 0.0)
		_desc_label.size.x = CONTENT_W
		if has_desc:
			_desc_label.text = description

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	var final_h: float = _hover_info.get_combined_minimum_size().y
	final_h = clampf(final_h, 54.0, 360.0)

	var card_w: float = size.x if size.x > 0.0 else 181.0
	var pos_x: float = (card_w - HOVER_W) * 0.5
	# Always place hover card cleanly below the profile card
	var pos_y: float = size.y + 10.0

	_hover_info.custom_minimum_size = Vector2(HOVER_W, final_h)
	_hover_info.size = Vector2(HOVER_W, final_h)
	_hover_info.position = Vector2(pos_x, pos_y)
	_hover_info.scale = Vector2.ONE

	_hover_info.modulate.a = 0.0
	_hover_info.visible = true

	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_info, "modulate:a", 1.0, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hide_hover_info(instant: bool = false) -> void:
	if not _hover_info or not _hover_info.visible:
		return

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	if instant:
		_hover_info.modulate.a = 0.0
		_hover_info.visible = false
		return

	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_info, "modulate:a", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.chain().tween_callback(func():
		if is_instance_valid(_hover_info):
			_hover_info.visible = false
	)


var _interactable_tween: Tween = null


# Dims and disables the card (or restores it) with smooth, juicy animations.
func set_interactable(interactable: bool, delay: float = 0.0) -> void:
	_is_interactable = interactable
	if _button:
		_button.disabled = not interactable
	if not interactable:
		_hide_hover_info()

	pivot_offset = size * 0.5

	if _interactable_tween and _interactable_tween.is_valid():
		_interactable_tween.kill()

	_interactable_tween = create_tween().set_parallel(true)

	if interactable:
		var target_modulate := Color(1, 1, 1, 1)
		var tw_mod := _interactable_tween.tween_property(self, "modulate", target_modulate, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var tw_scale := _interactable_tween.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if delay > 0.0:
			tw_mod.set_delay(delay)
			tw_scale.set_delay(delay)
	else:
		# Keep the original juicy response while another profile is switching.
		var target_modulate := Color(1, 1, 1, 0.45)
		var tw_mod := _interactable_tween.tween_property(self, "modulate", target_modulate, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var tw_scale := _interactable_tween.tween_property(self, "scale", Vector2(0.97, 0.97), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if delay > 0.0:
			tw_mod.set_delay(delay)
			tw_scale.set_delay(delay)

	if not interactable and _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_effect.modulate.a = 0.0
		_glow_effect.scale = Vector2(0.96, 0.96)


func hide_context_menu() -> void:
	if _context_menu:
		_context_menu.visible = false
	if z_index == 200:
		z_index = 0
	if active_context_card == self:
		active_context_card = null
