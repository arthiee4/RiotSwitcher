@tool
class_name ProfileButton
extends Control

## A single profile card in the grid. It only handles presentation and user
## input; all heavy work (killing processes, swapping session files) is
## orchestrated by ProfileGridController, which confirms state changes back
## through confirm_started()/confirm_stopped()/reset_toggle_state().

#region Glow Customization (Inspector)
@export_group("Glow Settings")
## Ative para ver e ajustar o glow ao vivo no editor!
@export var preview_glow: bool = false:
	set(value):
		preview_glow = value
		_update_glow_preview()

@export var glow_color: Color = Color(1.0, 0.04, 0.14, 1.0):
	set(value):
		glow_color = value
		_update_glow()

@export_range(0.0, 3.0, 0.05) var glow_intensity: float = 1.3:
	set(value):
		glow_intensity = value
		_update_glow()

@export_range(0.5, 6.0, 0.1) var glow_spread: float = 1.8:
	set(value):
		glow_spread = value
		_update_glow()

@export var glow_rect_size: Vector2 = Vector2(0.26, 0.10):
	set(value):
		glow_rect_size = value
		_update_glow()
#endregion

signal client_toggled(profile_button: Control, is_starting: bool)
signal delete_requested(profile_button: Control)
signal edit_requested(profile_button: Control)

const PLAY_ICON: Texture2D = preload("res://assets/icons/ui/icon_play.png")
const STOP_ICON: Texture2D = preload("res://assets/icons/ui/icon_stop.png")
const DRAG_THRESHOLD := 6.0
const HOVER_FADE_IN_TIME := 0.08
const HOVER_FADE_OUT_TIME := 0.08
const HOVER_SCALE_FACTOR := 1.04

## Full profile dictionary from ProfileManager. Set right after instantiation.
var profile_data: Dictionary = {}:
	set(val):
		profile_data = val
		if is_instance_valid(_hover_info) and _hover_info.visible:
			_show_hover_info()

var client_is_running := false
var _is_interactable := true
var _is_transitioning := false

# Drag & click state
var _is_mouse_down := false
var _drag_start_pos := Vector2.ZERO

@onready var _context_menu: Control = get_node_or_null("card/context_menu")
@onready var _delete_button: BaseButton = (find_child("delete_button", true, false) as BaseButton)
@onready var _edit_button: BaseButton = (find_child("edit_button", true, false) as BaseButton)
@onready var _glow_effect: Control = $glow if has_node("glow") else find_child("glow", true, false)
@onready var _button: Button = get_node_or_null("card/card_inner/Button")
@onready var _state_icon: TextureRect = get_node_or_null("card/card_inner/Button/TextureRect")
@onready var _card: Control = get_node_or_null("card")
@onready var _hover_info: Control = $hover_info if has_node("hover_info") else null
@onready var _name_level_row: Control = $hover_info/vbox/name_level_row if has_node("hover_info/vbox/name_level_row") else find_child("name_level_row", true, false)
@onready var _summoner_name: Label = $hover_info/vbox/name_level_row/summoner_name if has_node("hover_info/vbox/name_level_row/summoner_name") else find_child("summoner_name", true, false)
@onready var _summoner_level: Label = $hover_info/vbox/name_level_row/summoner_level if has_node("hover_info/vbox/name_level_row/summoner_level") else find_child("summoner_level", true, false)
@onready var _rank_badge: TextureRect = $hover_info/vbox/rank_row/rank_badge if has_node("hover_info/vbox/rank_row/rank_badge") else find_child("rank_badge", true, false)
@onready var _rank_tier_label: Label = $hover_info/vbox/rank_row/rank_tier_label if has_node("hover_info/vbox/rank_row/rank_tier_label") else find_child("rank_tier_label", true, false)
@onready var _separator: Control = $hover_info/vbox/separator if has_node("hover_info/vbox/separator") else find_child("separator", true, false)
@onready var _desc_label: Label = $hover_info/vbox/desc_label if has_node("hover_info/vbox/desc_label") else (find_child("desc_label", true, false) as Label)
@onready var _profile_name_label: Label = get_node_or_null("profile_name") if has_node("profile_name") else (find_child("profile_name", true, false) as Label)

const RANKS_DIR := "res://assets/icons/ranks/"

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
	"UNRANKED": Color("888c98"),
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

var _hover_tween: Tween = null
var _glow_tween: Tween = null


var profile_name: String:
	get: return profile_data.get("profile_name", "")


func _ready() -> void:
	_update_glow()
	_update_glow_preview()

	if Engine.is_editor_hint():
		return

	if _delete_button:
		_delete_button.pressed.connect(_on_delete_button_pressed)
		_delete_button.set_meta("sfx", &"cancel")
		if _delete_button is Button:
			(_delete_button as Button).text = tr("Delete")
	if _edit_button:
		_edit_button.pressed.connect(_on_edit_button_pressed)
		if _edit_button is Button:
			(_edit_button as Button).text = tr("Edit")
	if _card:
		_card.gui_input.connect(_on_card_gui_input)
	if _button and _button is Button:
		if not _button.pressed.is_connected(_on_profile_button_pressed):
			_button.pressed.connect(_on_profile_button_pressed)
		_button.set_meta("sfx", &"confirm")
		_button.mouse_entered.connect(_on_card_mouse_entered)
		_button.mouse_exited.connect(_on_card_mouse_exited)
	if _context_menu:
		_context_menu.visible = false
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
	set_process_input(true)


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
	if preview_glow:
		glow_node.modulate.a = 1.0
		glow_node.scale = Vector2(1.04, 1.04)
	else:
		if Engine.is_editor_hint():
			glow_node.modulate.a = 0.0
			glow_node.scale = Vector2(0.96, 0.96)


#region State confirmation (called by ProfileGridController)

## Confirms the client for this profile is now running.
func confirm_started() -> void:
	client_is_running = true
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = STOP_ICON


## Confirms the client was stopped and the session saved.
func confirm_stopped() -> void:
	client_is_running = false
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = PLAY_ICON


## Reverts the toggle after a failed start/stop attempt.
func reset_toggle_state() -> void:
	client_is_running = false
	_is_transitioning = false
	if _state_icon:
		_state_icon.texture = PLAY_ICON

#endregion

#region Input handlers

func _on_profile_button_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	var starting := not client_is_running

	# Immediately switch icon with punchy pop animation for instant UI responsiveness
	if _state_icon:
		_state_icon.pivot_offset = _state_icon.size * 0.5
		_state_icon.texture = STOP_ICON if starting else PLAY_ICON
		_state_icon.scale = Vector2(1.28, 1.28)
		var icon_tw := create_tween()
		icon_tw.tween_property(_state_icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	client_toggled.emit(self, starting)


func _on_delete_button_pressed() -> void:
	_context_menu.visible = false
	if client_is_running or _is_transitioning:
		printerr("Cannot delete profile while its client is running.")
		return
	delete_requested.emit(self)


func _on_edit_button_pressed() -> void:
	_context_menu.visible = false
	if client_is_running or _is_transitioning:
		printerr("Cannot edit profile while its client is running.")
		return
	edit_requested.emit(self)


## Handles right-click (context menu) and click-and-drag for grid reordering.
func _on_card_gui_input(event: InputEvent) -> void:
	if not _is_interactable or _is_transitioning:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			var opening := not _context_menu.visible
			_context_menu.visible = opening
			if opening:
				_hide_hover_info()
				_position_and_animate_context_menu()
				SfxManager.open()
			else:
				SfxManager.cancel()
			get_viewport().set_input_as_handled()
			return

		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				if _context_menu and _context_menu.visible:
					_context_menu.visible = false
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
			if _context_menu:
				_context_menu.visible = false
			_hide_hover_info(true)
			var parent_grid = get_parent()
			if parent_grid and parent_grid.has_method("start_card_drag"):
				parent_grid.start_card_drag(self, event.global_position)


## Hides the context menu when clicking anywhere outside of it.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _context_menu or not _context_menu.visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		if not _context_menu.get_global_rect().has_point(event.position):
			_context_menu.visible = false


func _position_and_animate_context_menu() -> void:
	if not _context_menu:
		return
	var mouse_pos := get_global_mouse_position()
	var vp_size := get_viewport_rect().size
	var menu_size := _context_menu.size
	if menu_size == Vector2.ZERO:
		menu_size = Vector2(148, 86)

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

#endregion

#region Visual state & Hover Info

func _on_card_mouse_entered() -> void:
	if Engine.is_editor_hint() or not _is_interactable or _is_mouse_down or is_any_card_dragging:
		return

	var parent_grid = get_parent()
	if parent_grid and parent_grid.has_method("is_dragging_card") and parent_grid.is_dragging_card():
		return

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_tween = create_tween().set_parallel(true)
		_glow_tween.tween_property(_glow_effect, "modulate:a", 1.0, HOVER_FADE_IN_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_glow_tween.tween_property(_glow_effect, "scale", Vector2(HOVER_SCALE_FACTOR, HOVER_SCALE_FACTOR), HOVER_FADE_IN_TIME + 0.02).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_show_hover_info()


func _on_card_mouse_exited() -> void:
	if Engine.is_editor_hint() or not _is_interactable:
		return

	# If mouse is still within the profile card rect (e.g. over play button), don't exit hover
	var global_mouse := get_global_mouse_position()
	if get_global_rect().has_point(global_mouse):
		return

	if _glow_effect:
		if _glow_tween and _glow_tween.is_valid():
			_glow_tween.kill()
		_glow_tween = create_tween().set_parallel(true)
		_glow_tween.tween_property(_glow_effect, "modulate:a", 0.0, HOVER_FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_glow_tween.tween_property(_glow_effect, "scale", Vector2(0.96, 0.96), HOVER_FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	if not _hover_info or (_context_menu and _context_menu.visible) or not _is_interactable or _is_mouse_down or is_any_card_dragging:
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

	# 1. Nick & Level (hidden if unscanned to avoid duplicating card profile name)
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

	# 2. Rank Tier & LP text + color
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

	# 3. Rank Badge icon
	if _rank_badge:
		if is_unscanned or tier == "UNRANKED":
			_rank_badge.visible = false
		else:
			var badge_tex := _resolve_rank_badge(tier)
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

	# 4. Separator & Description
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
	_hover_info.pivot_offset = Vector2(HOVER_W * 0.5, 0.0)

	_hover_info.modulate.a = 0.0
	_hover_info.scale = Vector2(0.97, 0.97)
	_hover_info.visible = true

	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(_hover_info, "modulate:a", 1.0, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_hover_info, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hide_hover_info(instant: bool = false) -> void:
	if not _hover_info or not _hover_info.visible:
		return

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	if instant:
		_hover_info.modulate.a = 0.0
		_hover_info.visible = false
		return

	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(_hover_info, "modulate:a", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.tween_property(_hover_info, "scale", Vector2(0.95, 0.95), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.chain().tween_callback(func():
		if is_instance_valid(_hover_info):
			_hover_info.visible = false
	)


var _interactable_tween: Tween = null


## Dims and disables the card (or restores it) with smooth, juicy animations.
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

#endregion
