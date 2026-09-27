class_name AddProfileController
extends Control

# "Add profile" form: name input, background picker (built-in or custom upload), preview, and creation.

signal profile_created_successfully
signal warning_dismissed

const DEFAULT_BG_PATH := "res://assets/backgrounds/default_bg.webp"
const ALLOWED_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]

const COLOR_BORDER_IDLE := Color(0.4706, 0.3529, 0.1569, 0.85)
const COLOR_BORDER_HOVER := Color(0.80, 0.70, 0.46, 0.55)
const COLOR_BORDER_SELECTED := Color(0.82, 0.72, 0.48, 0.82)

# Injected by Main.
var profile_manager: Node

var _current_custom_bg_path: String = ""
var _current_custom_file_label: String = ""
var _selected_preset_index: int = 0
var _background_textures: Array = [] # Built-in backgrounds, aligned with picker buttons.

@onready var _backgrounds_container: Control = find_child("backgrounds", true, false) as Control
@onready var _external_bg_scrollbar: VScrollBar = get_node_or_null("bg_select/bg_scrollbar") as VScrollBar
@onready var _random_bg_button: Button = $bg_select/random_bg_button if has_node("bg_select/random_bg_button") else null
@onready var _preview_card: Control = $preview/profile_button
@onready var _preview_background: TextureRect = $preview/profile_button/card/Panel/profile_bg
@onready var _upload_node: Control = $upload_custom_bg if has_node("upload_custom_bg") else null
@onready var _browse_button: Button = $upload_custom_bg/browser_button
@onready var _file_dialog: FileDialog = $creation/create_button/FileDialog
@onready var _name_input: LineEdit = $profile_name/LineEdit
@onready var _name_input_bg: Panel = $profile_name/input_bg if has_node("profile_name/input_bg") else null
@onready var _name_char_count: Label = $profile_name/char_count if has_node("profile_name/char_count") else null
@onready var _description_input: LineEdit = $profile_description/LineEdit if has_node("profile_description/LineEdit") else null
@onready var _desc_input_bg: Panel = $profile_description/input_bg if has_node("profile_description/input_bg") else null
@onready var _desc_char_count: Label = $profile_description/char_count if has_node("profile_description/char_count") else null
@onready var _name_preview: Label = $preview/profile_button/profile_name
@onready var _create_button: Button = $creation/create_button
@onready var _error_node: Control = $error
@onready var _error_label: Label = $error/Label
@onready var _warning_panel: Control = $warning
@onready var _close_warning_button: Button = $warning/closewarning

var _upload_bar_bg: Panel = null
var _upload_file_hint: Label = null
var _game_mode_option: OptionButton = null
var _cascade_tweens: Array[Tween] = []
var _preview_pulse_tween: Tween = null


const TOTAL_PRESET_BACKGROUNDS := 20
const DIVIDER_TEX: Texture2D = preload("res://assets/icons/hextech/title_divider.png")
const ADD_ICON_TEX: Texture2D = preload("res://assets/icons/ui/icon_add.svg")
const FONT_DISPLAY: FontFile = preload("res://assets/fonts/BeaufortforLoL-Bold.otf")
const FONT_BODY: FontFile = preload("res://assets/fonts/Spiegel-Regular.otf")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(AppPaths.BACKGROUNDS_DIR)
	_ensure_layout_and_backgrounds()
	if _preview_card and _preview_card.has_method("set_preview_mode"):
		_preview_card.set_preview_mode(true)
	_setup_input_focus_styles()
	_load_background_images()
	_connect_signals()
	reset_form()
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		_reset_hover_states()


func _process(_delta: float) -> void:
	if _external_bg_scrollbar and _backgrounds_container:
		var scroll := _backgrounds_container.get_parent() as ScrollContainer
		if scroll:
			_sync_external_scrollbar(scroll)


func _reset_hover_states() -> void:
	# Reset BG preset card borders to their idle/selected state
	_update_preset_selection_visuals()
	# Reset upload bar hover
	_on_upload_bar_hover(false)

func _on_external_scroll_changed(value: float) -> void:
	if not _backgrounds_container:
		return
	var scroll := _backgrounds_container.get_parent() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = int(value)


func _sync_external_scrollbar(scroll: ScrollContainer) -> void:
	if not _external_bg_scrollbar or not scroll:
		return
	var internal_scrollbar := scroll.get_v_scroll_bar()
	if not internal_scrollbar:
		return
	internal_scrollbar.visible = true
	internal_scrollbar.modulate.a = 0.0
	_external_bg_scrollbar.min_value = 0.0
	_external_bg_scrollbar.max_value = internal_scrollbar.max_value
	_external_bg_scrollbar.page = internal_scrollbar.page
	_external_bg_scrollbar.step = 1.0
	if absf(_external_bg_scrollbar.value - float(scroll.scroll_vertical)) > 0.5:
		_external_bg_scrollbar.value = scroll.scroll_vertical


func _position_background_scrollbar(scroll: ScrollContainer) -> void:
	if not scroll or not is_instance_valid(scroll):
		return
	var scrollbar := scroll.get_v_scroll_bar()
	if not scrollbar:
		return
	# Keep the content untouched; only tuck the scrollbar 8px into the right rail.
	var target_x: float = maxf(0.0, scroll.size.x - scrollbar.size.x - 8.0)
	if absf(scrollbar.position.x - target_x) > 0.5:
		scrollbar.position.x = target_x


func _ensure_layout_and_backgrounds() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var root_panel := get_node_or_null("Panel") as Control
	if root_panel:
		root_panel.anchor_left = 0.0
		root_panel.anchor_top = 0.0
		root_panel.anchor_right = 0.0
		root_panel.anchor_bottom = 0.0
		root_panel.offset_left = 80.0
		root_panel.offset_top = 32.0
		root_panel.offset_right = 1282.0
		root_panel.offset_bottom = 720.0

	var title_lbl := get_node_or_null("tittle") as Label
	if title_lbl:
		title_lbl.offset_left = 133.0
		title_lbl.offset_top = 45.0
		title_lbl.offset_right = 600.0
		title_lbl.offset_bottom = 105.0
		title_lbl.add_theme_font_size_override("font_size", 42)
		title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var main_div := get_node_or_null("Panel/title_divider") as TextureRect
	if main_div:
		main_div.offset_left = 53.0
		main_div.offset_top = 72.0
		main_div.offset_right = 363.0
		main_div.offset_bottom = 78.0
		main_div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		main_div.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Ensure preview is on the right side with clean top-to-bottom order: Label -> preview_divider -> profile_button
	var preview_node := get_node_or_null("preview") as Control
	if preview_node:
		preview_node.anchor_left = 0.0
		preview_node.anchor_top = 0.0
		preview_node.anchor_right = 0.0
		preview_node.anchor_bottom = 0.0
		preview_node.offset_left = 914.0
		preview_node.offset_top = 285.0
		preview_node.offset_right = 1186.0
		preview_node.offset_bottom = 410.0
		var prev_lbl := preview_node.get_node_or_null("Label") as Label
		if prev_lbl:
			prev_lbl.anchor_left = 0.0
			prev_lbl.anchor_top = 0.0
			prev_lbl.anchor_right = 0.0
			prev_lbl.anchor_bottom = 0.0
			prev_lbl.offset_left = 0.0
			prev_lbl.offset_top = 0.0
			prev_lbl.offset_right = 272.0
			prev_lbl.offset_bottom = 26.0
			prev_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			preview_node.move_child(prev_lbl, 0)
		var div := preview_node.get_node_or_null("preview_divider") as TextureRect
		if not div:
			div = TextureRect.new()
			div.name = "preview_divider"
			preview_node.add_child(div)
		div.anchor_left = 0.0
		div.anchor_top = 0.0
		div.anchor_right = 0.0
		div.anchor_bottom = 0.0
		div.offset_left = 0.0
		div.offset_top = 30.0
		div.offset_right = 272.0
		div.offset_bottom = 36.0
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		div.texture = DIVIDER_TEX
		div.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		div.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_node.move_child(div, 1)
		if _preview_card:
			_preview_card.custom_minimum_size = Vector2(181.0, 50.0)
			_preview_card.anchor_left = 0.0
			_preview_card.anchor_top = 0.0
			_preview_card.anchor_right = 0.0
			_preview_card.anchor_bottom = 0.0
			if "pivot_offset_ratio" in _preview_card:
				_preview_card.set("pivot_offset_ratio", Vector2(0.5, 0.5))
			_preview_card.pivot_offset = Vector2.ZERO
			_preview_card.scale = Vector2(1.5, 1.5)
			_preview_card.offset_left = 45.25
			_preview_card.offset_top = 62.5
			_preview_card.offset_right = 226.25
			_preview_card.offset_bottom = 112.5
			preview_node.move_child(_preview_card, 2)

	var p_name := get_node_or_null("profile_name") as Control
	if p_name:
		p_name.offset_left = 133.0
		p_name.offset_top = 120.0
		p_name.offset_right = 421.0
		p_name.offset_bottom = 181.0
	var p_desc := get_node_or_null("profile_description") as Control
	if p_desc:
		p_desc.offset_left = 437.0
		p_desc.offset_top = 120.0
		p_desc.offset_right = 725.0
		p_desc.offset_bottom = 181.0

	# Ensure left column positions and 20 backgrounds in a scrollable 4-column grid
	var bg_select := get_node_or_null("bg_select") as Control
	if bg_select:
		bg_select.offset_left = 133.0
		bg_select.offset_top = 195.0
		bg_select.offset_right = 725.0
		bg_select.offset_bottom = 511.0
		if _random_bg_button:
			_random_bg_button.offset_left = 502.0
			_random_bg_button.offset_right = 592.0
			var rand_norm := _create_hextech_fancy_box(
				Color(0.1176, 0.1373, 0.1569, 1.0),
				Color(0.4706, 0.3529, 0.1569, 1.0),
				7, 0, 0, 7,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
			rand_norm.borders[0].width_right = 2
			var rand_hov := _create_hextech_fancy_box(
				Color(0.1725, 0.1608, 0.1333, 1.0),
				Color(0.82, 0.72, 0.48, 0.85),
				7, 0, 0, 7,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
			rand_hov.borders[0].width_right = 2

	var upload_node := get_node_or_null("upload_custom_bg") as Control
	if upload_node:
		upload_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		upload_node.offset_left = 133.0
		upload_node.offset_top = 528.0
		upload_node.offset_right = 725.0
		upload_node.offset_bottom = 582.0
		upload_node.custom_minimum_size = Vector2(592.0, 54.0)
		upload_node.size = Vector2(592.0, 54.0)
		upload_node.mouse_filter = Control.MOUSE_FILTER_STOP
		upload_node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		_upload_bar_bg = upload_node.get_node_or_null("bar_bg") as Panel
		if not _upload_bar_bg:
			_upload_bar_bg = Panel.new()
			_upload_bar_bg.name = "bar_bg"
			upload_node.add_child(_upload_bar_bg)
			upload_node.move_child(_upload_bar_bg, 0)
		_upload_bar_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_upload_bar_bg.offset_left = 0.0
		_upload_bar_bg.offset_top = 0.0
		_upload_bar_bg.offset_right = 592.0
		_upload_bar_bg.offset_bottom = 54.0
		_upload_bar_bg.custom_minimum_size = Vector2(592.0, 54.0)
		_upload_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar_style := _create_hextech_fancy_box(
			Color(0.0039, 0.0392, 0.0745, 0.95),
			COLOR_BORDER_IDLE,
			6, 10, 0, 10,
			-7.0, 0.0, 0.0, 0.0,
			true,
			2, 1
		)

		var icon_node := upload_node.get_node_or_null("icon") as TextureRect
		if not icon_node:
			icon_node = TextureRect.new()
			icon_node.name = "icon"
			upload_node.add_child(icon_node)
		icon_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon_node.offset_left = 18.0
		icon_node.offset_top = 18.0
		icon_node.offset_right = 36.0
		icon_node.offset_bottom = 36.0
		icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_node.texture = ADD_ICON_TEX
		icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var up_lbl := upload_node.get_node_or_null("Label") as Label
		if up_lbl:
			up_lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
			up_lbl.offset_left = 46.0
			up_lbl.offset_top = 0.0
			up_lbl.offset_right = 256.0
			up_lbl.offset_bottom = 54.0
			up_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			up_lbl.add_theme_font_override("font", FONT_DISPLAY)
			up_lbl.add_theme_font_size_override("font_size", 14)

		_upload_file_hint = upload_node.get_node_or_null("file_hint") as Label
		if not _upload_file_hint:
			_upload_file_hint = Label.new()
			_upload_file_hint.name = "file_hint"
			upload_node.add_child(_upload_file_hint)
		_upload_file_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_upload_file_hint.offset_left = 260.0
		_upload_file_hint.offset_top = 0.0
		_upload_file_hint.offset_right = 460.0
		_upload_file_hint.offset_bottom = 54.0
		_upload_file_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_upload_file_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_upload_file_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_upload_file_hint.add_theme_font_override("font", FONT_BODY)
		_upload_file_hint.add_theme_font_size_override("font_size", 12)
		_upload_file_hint.text = "PNG, JPG, WEBP"

		if _browse_button:
			_browse_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_browse_button.offset_left = 474.0
			_browse_button.offset_top = 10.0
			_browse_button.offset_right = 580.0
			_browse_button.offset_bottom = 44.0
			var btn_norm := _create_hextech_fancy_box(
				Color(0.1176, 0.1373, 0.1569, 1.0),
				Color(0.4706, 0.3529, 0.1569, 1.0),
				7, 0, 0, 7,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
			btn_norm.borders[0].width_right = 2
			var btn_hov := _create_hextech_fancy_box(
				Color(0.1725, 0.1608, 0.1333, 1.0),
				Color(0.82, 0.72, 0.48, 0.85),
				7, 0, 0, 7,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
			btn_hov.borders[0].width_right = 2
			_browse_button.add_theme_font_override("font", FONT_DISPLAY)
			_browse_button.add_theme_font_size_override("font_size", 12)

	# Bottom bar: error on the left (133..340), disabled game OptionButton + create_button at the end (right side: 350..725)
	var creation_node := get_node_or_null("creation") as Control
	if creation_node:
		creation_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		creation_node.offset_left = 133.0
		creation_node.offset_top = 602.0
		creation_node.offset_right = 725.0
		creation_node.offset_bottom = 646.0
		# Language is an application-wide setting (Settings > Language). The old
		# per-account dropdown duplicated that control and was never connected.
		# Remove it at runtime so old scene files remain compatible.
		var duplicate_language := creation_node.get_node_or_null("game_lang_option")
		if duplicate_language:
			duplicate_language.queue_free()

		_game_mode_option = creation_node.get_node_or_null("game_mode_option") as OptionButton
		if not _game_mode_option:
			_game_mode_option = OptionButton.new()
			_game_mode_option.name = "game_mode_option"
			creation_node.add_child(_game_mode_option)
		_game_mode_option.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_game_mode_option.offset_left = 212.0
		_game_mode_option.offset_top = 0.0
		_game_mode_option.offset_right = 412.0
		_game_mode_option.offset_bottom = 44.0
		if _game_mode_option.item_count == 0:
			_game_mode_option.add_item("League of Legends", 0)
			_game_mode_option.add_item("Valorant", 1)
			_game_mode_option.add_item("Teamfight Tactics", 2)
		_game_mode_option.selected = 0
		_game_mode_option.disabled = true
		_game_mode_option.set_meta("sfx_silent", true)
		_game_mode_option.add_theme_font_override("font", FONT_DISPLAY)
		_game_mode_option.add_theme_font_size_override("font_size", 13)
		var opt_dis := _create_hextech_fancy_box(
			Color(0.0039, 0.0392, 0.0745, 0.7),
			Color(0.4706, 0.3529, 0.1569, 0.45),
			8, 0, 0, 8,
			0.0, 0.0, 0.0, 0.0,
			false,
			1, 1
		)
		opt_dis.content_margin_left = 14.0
		opt_dis.content_margin_right = 14.0

		if _create_button:
			_create_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_create_button.offset_left = 424.0
			_create_button.offset_top = 0.0
			_create_button.offset_right = 592.0
			_create_button.offset_bottom = 44.0
			var create_norm := _create_hextech_fancy_box(
				Color(0.16, 0.145, 0.105, 1.0),
				Color(0.7843, 0.6667, 0.4314, 1.0),
				10, 10, 4, 4,
				0.0, 0.0, -7.0, -7.0,
				true,
				1, 1
			)
			create_norm.borders[0].width_top = 2
			var create_hov := _create_hextech_fancy_box(
				Color(0.22, 0.19, 0.13, 1.0),
				Color(0.86, 0.76, 0.52, 0.95),
				10, 10, 4, 4,
				0.0, 0.0, -7.0, -7.0,
				true,
				1, 1
			)
			create_hov.borders[0].width_top = 2

	if _error_node:
		_error_node.offset_left = 133.0
		_error_node.offset_top = 602.0
		_error_node.offset_right = 338.0
		_error_node.offset_bottom = 646.0

	if not _backgrounds_container or not bg_select:
		return

	# Ensure ScrollContainer wraps _backgrounds_container with clean inner margins
	var scroll := _backgrounds_container as ScrollContainer
	if not scroll:
		scroll = bg_select.get_node_or_null("scroll") as ScrollContainer
	if not scroll:
		scroll = ScrollContainer.new()
		scroll.name = "scroll"
		bg_select.add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scroll.offset_left = 0.0
	scroll.offset_top = 34.0
	scroll.offset_right = 592.0
	scroll.offset_bottom = 316.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var internal_scrollbar := scroll.get_v_scroll_bar()
	if internal_scrollbar:
		internal_scrollbar.visible = true
		internal_scrollbar.modulate.a = 0.0
	if not _external_bg_scrollbar:
		_external_bg_scrollbar = bg_select.get_node_or_null("bg_scrollbar") as VScrollBar
	if _external_bg_scrollbar and not _external_bg_scrollbar.value_changed.is_connected(_on_external_scroll_changed):
		_external_bg_scrollbar.value_changed.connect(_on_external_scroll_changed)
	scroll.add_theme_constant_override("scrollbar_v_separation", -8)
	if not scroll.resized.is_connected(_position_background_scrollbar):
		scroll.resized.connect(_position_background_scrollbar.bind(scroll))
	_position_background_scrollbar(scroll)
	call_deferred("_position_background_scrollbar", scroll)
	var scroll_style := _create_hextech_fancy_box(
		Color(0.07058824, 0.07058824, 0.07058824, 1.0),
		Color(0.4706, 0.3529, 0.1569, 0.55),
		5, 5, 5, 5,
		-7.0, -7.0, -7.0, -7.0,
		true,
		1, 1
	)
	scroll_style.content_margin_left = 3.0
	scroll_style.content_margin_top = 3.0
	scroll_style.content_margin_right = 3.0
	scroll_style.content_margin_bottom = 3.0
	scroll.add_theme_stylebox_override("panel", scroll_style)

	if _backgrounds_container != scroll and _backgrounds_container.get_parent() != scroll:
		var old_parent := _backgrounds_container.get_parent()
		if old_parent:
			old_parent.remove_child(_backgrounds_container)
		scroll.add_child(_backgrounds_container)
	call_deferred("_position_background_scrollbar", scroll)

	var template_panel: Panel = null
	if _backgrounds_container.get_child_count() > 0:
		template_panel = _backgrounds_container.get_child(0) as Panel

	while _backgrounds_container.get_child_count() < TOTAL_PRESET_BACKGROUNDS and template_panel:
		var next_num := _backgrounds_container.get_child_count() + 1
		var dup := template_panel.duplicate() as Panel
		dup.name = "bgexample%d" % next_num
		_backgrounds_container.add_child(dup)

	var pad_x := 8.0
	var pad_top := 10.0
	var pad_bottom := 32.0
	var card_w := 127.0
	var card_h := 51.0
	var gap_x := 12.0
	var gap_y := 12.0
	var children := _backgrounds_container.get_children()
	var rows := int(ceil(float(children.size()) / 4.0))
	var total_h := pad_top + rows * card_h + maxi(0, rows - 1) * gap_y + pad_bottom
	if not _backgrounds_container is ScrollContainer:
		_backgrounds_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_backgrounds_container.offset_left = 0.0
		_backgrounds_container.offset_top = 0.0
		_backgrounds_container.offset_right = 568.0
		_backgrounds_container.offset_bottom = total_h
	_backgrounds_container.custom_minimum_size = Vector2(568.0, total_h)
	_sync_external_scrollbar(scroll)
	_backgrounds_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backgrounds_container.mouse_filter = Control.MOUSE_FILTER_PASS

	for i in range(children.size()):
		var card := children[i] as Panel
		if not card:
			continue
		var col := i % 4
		var row := int(i / 4)
		var x := pad_x + col * (card_w + gap_x)
		var y := pad_top + row * (card_h + gap_y)
		card.offset_left = x
		card.offset_top = y
		card.offset_right = x + card_w
		card.offset_bottom = y + card_h
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var btn := card.get_node_or_null("Button") as Button
		if btn:
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			# The image is the normal state; the scene's hover StyleBox supplies
			# only the highlight, so the button must not paint a gray fill over it.
			btn.flat = true
			var btn_frame := _create_hextech_fancy_box(
				Color(0, 0, 0, 0),
				COLOR_BORDER_IDLE,
				5, 5, 5, 5,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
			btn_frame.draw_center = false
			var btn_hov_frame := _create_hextech_fancy_box(
				Color(0.7843, 0.6667, 0.4314, 0.04),
				COLOR_BORDER_HOVER,
				5, 5, 5, 5,
				0.0, 0.0, 0.0, 0.0,
				false,
				1, 1
			)
		var tex_rect := card.get_node_or_null("TextureRect") as TextureRect
		if tex_rect:
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.offset_left = 0.0
			tex_rect.offset_top = 0.0
			tex_rect.offset_right = 0.0
			tex_rect.offset_bottom = 0.0
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			var img_path := "res://assets/backgrounds/profiles_bg/%d.webp" % (i + 1)
			if ResourceLoader.exists(img_path):
				tex_rect.texture = load(img_path)


func _create_hextech_fancy_box(
	bg_col: Color,
	border_col: Color,
	tl: int = 7,
	tr_rad: int = 4,
	br: int = 7,
	bl: int = 4,
	curv_tl: float = 0.0,
	curv_tr: float = -7.0,
	curv_br: float = 0.0,
	curv_bl: float = -7.0,
	with_inner_filigree: bool = true,
	left_width: int = 1,
	other_width: int = 1
) -> StyleBoxFancy:
	var box := StyleBoxFancy.new()
	box.color = bg_col
	box.corner_detail = 8
	box.corner_radius_top_left = tl
	box.corner_radius_top_right = tr_rad
	box.corner_radius_bottom_right = br
	box.corner_radius_bottom_left = bl
	box.corner_curvature_top_left = curv_tl
	box.corner_curvature_top_right = curv_tr
	box.corner_curvature_bottom_right = curv_br
	box.corner_curvature_bottom_left = curv_bl

	var outer := StyleBorder.new()
	outer.color = border_col
	outer.width_left = left_width
	outer.width_top = other_width
	outer.width_right = other_width
	outer.width_bottom = other_width

	var arr: Array[StyleBorder] = [outer]
	if with_inner_filigree:
		var inner := StyleBorder.new()
		inner.color = Color(0.7843, 0.6667, 0.4314, 0.20)
		inner.width_left = 1
		inner.width_top = 1
		inner.width_right = 1
		inner.width_bottom = 1
		inner.inset_left = 2
		inner.inset_top = 2
		inner.inset_right = 2
		inner.inset_bottom = 2
		arr.append(inner)
	box.borders = arr
	return box


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


# Injected by Main.
func set_profile_manager(pm: Node) -> void:
	profile_manager = pm
	_update_name_preview()


func set_warning_visibility(visible_: bool) -> void:
	if _warning_panel:
		_warning_panel.visible = visible_
		_warning_panel.modulate.a = 1.0


func _setup_input_focus_styles() -> void:
	if _name_input and _name_input_bg:
		_name_input.focus_entered.connect(func(): _set_input_box_focused(_name_input_bg, true))
		_name_input.focus_exited.connect(func(): _set_input_box_focused(_name_input_bg, false))
	if _description_input and _desc_input_bg:
		_description_input.focus_entered.connect(func(): _set_input_box_focused(_desc_input_bg, true))
		_description_input.focus_exited.connect(func(): _set_input_box_focused(_desc_input_bg, false))


func _set_input_box_focused(panel: Panel, focused: bool) -> void:
	# Focus colors are authored through the LineEdit focus StyleBox in the scene.
	return


func reset_form() -> void:
	_hide_error()
	_name_input.text = ""
	if _description_input:
		_description_input.text = ""
	_current_custom_bg_path = ""
	_current_custom_file_label = ""
	_update_name_preview()
	_update_description_preview()
	if _background_textures.size() > 0 and _background_textures[0]:
		_select_preset_background(0, false)
	else:
		_preview_background.texture = load(DEFAULT_BG_PATH)
		_update_preset_selection_visuals()


func _load_background_images() -> void:
	_background_textures.clear()
	var index := 0
	for child in _backgrounds_container.get_children():
		var panel := child as Panel
		if panel:
			panel.pivot_offset = panel.size * 0.5
		var button := child.get_node_or_null("Button") as Button
		if not button:
			continue
		index += 1
		var image_path := "res://assets/backgrounds/profiles_bg/%d.webp" % index
		if ResourceLoader.exists(image_path):
			_background_textures.append(load(image_path))
		else:
			printerr("AddProfile: Built-in background not found: ", image_path)
			_background_textures.append(null)
		var captured_idx := _background_textures.size() - 1
		button.pressed.connect(_on_standard_background_selected.bind(captured_idx))


func _connect_signals() -> void:
	_name_input.text_changed.connect(_on_name_text_changed)
	_name_input.text_submitted.connect(func(_text): _on_create_button_pressed())
	if _description_input:
		_description_input.text_changed.connect(_on_description_text_changed)
		_description_input.text_submitted.connect(func(_text): _on_create_button_pressed())
	if _random_bg_button:
		_random_bg_button.pressed.connect(_on_random_bg_pressed)
	_file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp ; Image Files"]
	_file_dialog.file_selected.connect(_on_file_selected)
	_browse_button.pressed.connect(_on_browse_button_pressed)
	_browse_button.mouse_entered.connect(func(): _on_upload_bar_hover(true))
	_browse_button.mouse_exited.connect(func(): _on_upload_bar_hover(false))
	if _upload_node:
		_upload_node.gui_input.connect(_on_upload_bar_gui_input)
		_upload_node.mouse_entered.connect(func(): _on_upload_bar_hover(true))
		_upload_node.mouse_exited.connect(func(): _on_upload_bar_hover(false))
	var win := get_window()
	if win and not win.files_dropped.is_connected(_on_window_files_dropped):
		win.files_dropped.connect(_on_window_files_dropped)
	_create_button.pressed.connect(_on_create_button_pressed)
	_create_button.set_meta("sfx", &"confirm")
	_close_warning_button.pressed.connect(_on_close_warning_pressed)


func _on_upload_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		SfxManager.click()
		_on_browse_button_pressed()


func _on_upload_bar_hover(hovered: bool) -> void:
	# Upload hover/selected colors are authored by the scene/theme.
	return


func _on_window_files_dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree() or files.is_empty():
		return
	_on_file_selected(files[0])


func _on_random_bg_pressed() -> void:
	var count := _background_textures.size()
	if count <= 0:
		return
	var next_idx := randi() % count
	if count > 1 and next_idx == _selected_preset_index:
		next_idx = (next_idx + 1 + (randi() % (count - 1))) % count
	_select_preset_background(next_idx, true)


func _update_preset_selection_visuals() -> void:
	# Background card StyleBoxes are authored in add_menu.tscn.
	return

func _pulse_preview_card() -> void:
	pass


func _generate_auto_profile_name() -> String:
	if not profile_manager:
		return "Account 1"
	var index := 1
	while profile_manager.has_profile("Account %d" % index):
		index += 1
	return "Account %d" % index


func _update_name_preview() -> void:
	var auto_name := _generate_auto_profile_name()
	if _name_input:
		_name_input.placeholder_text = auto_name
	var raw_len := _name_input.text.length() if _name_input else 0
	if _name_char_count:
		_name_char_count.text = "%d/20" % raw_len
	if not _name_preview:
		return
	var typed := _name_input.text.strip_edges() if _name_input else ""
	_name_preview.text = typed if not typed.is_empty() else auto_name


func _update_description_preview() -> void:
	var raw_len := _description_input.text.length() if _description_input else 0
	if _desc_char_count:
		_desc_char_count.text = "%d/35" % raw_len


func _on_create_button_pressed() -> void:
	if not profile_manager:
		_show_error("Internal error: Profile Manager not available.")
		return

	var raw_typed := _name_input.text.strip_edges()
	var has_custom_name := not raw_typed.is_empty()
	var profile_name := raw_typed if has_custom_name else _generate_auto_profile_name()
	var description := _description_input.text.strip_edges() if _description_input else ""

	if not _preview_background.texture:
		_show_error("Please select or upload a background image!")
		return
	if profile_manager.has_profile(profile_name):
		_show_error("Profile name '%s' already exists!" % profile_name)
		return

	_hide_error()
	var background_path := _resolve_background_path()
	if not profile_manager.add_profile(profile_name, background_path, has_custom_name, description):
		_show_error("Failed to create profile! Check logs.")
		return

	reset_form()
	profile_created_successfully.emit()


# Decides which background path gets stored for the new profile.
func _resolve_background_path() -> String:
	if not _current_custom_bg_path.is_empty():
		return _current_custom_bg_path
	if _preview_background and _preview_background.texture:
		var resource_path: String = _preview_background.texture.resource_path
		if resource_path.begins_with("res://"):
			return resource_path
	return DEFAULT_BG_PATH


func _on_browse_button_pressed() -> void:
	_hide_error()
	_file_dialog.popup_centered()


# Copies the picked image into the app's backgrounds folder and previews it.
func _on_file_selected(path: String) -> void:
	var extension := path.get_extension().to_lower()
	if not extension in ALLOWED_EXTENSIONS:
		_show_error("Invalid file type. Please use PNG, JPG, or WEBP.")
		return

	var typed_name := _name_input.text.strip_edges()
	var base_name := typed_name.validate_filename().replace(" ", "_") if not typed_name.is_empty() else _generate_auto_profile_name().validate_filename().replace(" ", "_")
	var file_name := "%s_%d.%s" % [base_name, Time.get_unix_time_from_system(), extension]
	var destination_path := AppPaths.BACKGROUNDS_DIR.path_join(file_name)

	if DirAccess.copy_absolute(path, destination_path) != OK:
		_show_error("Could not save custom background image.")
		return

	var image := Image.load_from_file(destination_path)
	if not image:
		_show_error("Failed to load saved custom image.")
		_current_custom_bg_path = ""
		_current_custom_file_label = ""
		return

	_preview_background.texture = ImageTexture.create_from_image(image)
	_current_custom_bg_path = destination_path
	_current_custom_file_label = path.get_file()
	_selected_preset_index = -1
	_update_preset_selection_visuals()
	_pulse_preview_card()
	_hide_error()


func _select_preset_background(index: int, animate: bool = true) -> void:
	if index < 0 or index >= _background_textures.size() or not _background_textures[index]:
		_show_error("Selected background is unavailable.")
		return
	_selected_preset_index = index
	_current_custom_bg_path = ""
	_current_custom_file_label = ""
	_preview_background.texture = _background_textures[index]
	_update_preset_selection_visuals()
	if animate:
		_pulse_preview_card()
	_hide_error()


func _on_standard_background_selected(index: int) -> void:
	_select_preset_background(index, true)


func _on_name_text_changed(_new_text: String) -> void:
	_update_name_preview()
	_hide_error()


func _on_description_text_changed(_new_text: String) -> void:
	_update_description_preview()
	_hide_error()


func _on_close_warning_pressed() -> void:
	warning_dismissed.emit()
	if _warning_panel:
		var tw := _warning_panel.create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_warning_panel, "modulate:a", 0.0, 0.14)
		tw.tween_property(_warning_panel, "offset_top", 40.0, 0.14)
		tw.tween_property(_warning_panel, "offset_bottom", 190.0, 0.14)
		tw.chain().tween_callback(func():
			if is_instance_valid(_warning_panel):
				_warning_panel.visible = false
				_warning_panel.offset_top = 56.0
				_warning_panel.offset_bottom = 206.0
		)


func _show_error(message: String) -> void:
	_error_label.text = message
	if _error_node:
		_error_node.visible = true
		var base_x := 133.0
		_error_node.position.x = base_x - 6.0
		var tw := _error_node.create_tween()
		tw.tween_property(_error_node, "position:x", base_x + 5.0, 0.04)
		tw.tween_property(_error_node, "position:x", base_x - 3.0, 0.04)
		tw.tween_property(_error_node, "position:x", base_x, 0.04)
	_error_label.visible = true
	SfxManager.error()


func _hide_error() -> void:
	if _error_node:
		_error_node.visible = false
	_error_label.visible = false


# Plays a professional staggered cascade entrance animation for the add profile view.
func play_cascade_entrance() -> void:
	for tw in _cascade_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_cascade_tweens.clear()

	# 1.
	var title_node := get_node_or_null("tittle") as Control
	if title_node:
		title_node.modulate.a = 0.0
		var title_has_offset: bool = "offset_transform_enabled" in title_node
		if title_has_offset:
			title_node.set("offset_transform_enabled", true)
			title_node.set("offset_transform_position", Vector2(0.0, -8.0))
			title_node.set("offset_transform_visual_only", true)
		else:
			title_node.position.y = 37.0

		var tw := title_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(title_node, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if title_has_offset:
			tw.tween_property(title_node, "offset_transform_position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(title_node, "position:y", 45.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2.
	var input_nodes: Array[Control] = []
	var p_name := get_node_or_null("profile_name") as Control
	var p_desc := get_node_or_null("profile_description") as Control
	if p_name: input_nodes.append(p_name)
	if p_desc: input_nodes.append(p_desc)

	for inp in input_nodes:
		inp.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in inp
		if has_offset:
			inp.set("offset_transform_enabled", true)
			inp.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			inp.set("offset_transform_scale", Vector2(0.96, 0.96))
			inp.set("offset_transform_visual_only", false)
		else:
			inp.scale = Vector2(0.96, 0.96)

		var tw := inp.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(inp, "modulate:a", 1.0, 0.16).set_delay(0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(inp, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(inp, "scale", Vector2.ONE, 0.18).set_delay(0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3.
	var bg_label := get_node_or_null("bg_select/Label") as Control
	if bg_label:
		bg_label.modulate.a = 0.0
		var tw := bg_label.create_tween()
		_cascade_tweens.append(tw)
		tw.tween_property(bg_label, "modulate:a", 1.0, 0.14).set_delay(0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4.
	if _backgrounds_container:
		var bg_children := _backgrounds_container.get_children()
		for i in range(bg_children.size()):
			var bg_card := bg_children[i] as Control
			if not bg_card or not is_instance_valid(bg_card):
				continue

			bg_card.modulate.a = 0.0
			var has_offset: bool = "offset_transform_enabled" in bg_card
			if has_offset:
				bg_card.set("offset_transform_enabled", true)
				bg_card.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
				bg_card.set("offset_transform_scale", Vector2(0.85, 0.85))
				bg_card.set("offset_transform_visual_only", false)
			else:
				var sz := bg_card.size
				if sz.x > 0 and sz.y > 0:
					bg_card.pivot_offset = sz * 0.5
				bg_card.scale = Vector2(0.85, 0.85)

			var delay: float = 0.06 + (i * 0.02)
			var tw := bg_card.create_tween().set_parallel(true)
			_cascade_tweens.append(tw)
			tw.tween_property(bg_card, "modulate:a", 1.0, 0.14).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if has_offset:
				tw.tween_property(bg_card, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				tw.tween_property(bg_card, "scale", Vector2.ONE, 0.18).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 5.
	var bottom_nodes: Array[Control] = []
	var upload_node := get_node_or_null("upload_custom_bg") as Control
	var create_node := get_node_or_null("creation") as Control
	if upload_node: bottom_nodes.append(upload_node)
	if create_node: bottom_nodes.append(create_node)

	for b_node in bottom_nodes:
		b_node.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in b_node
		if has_offset:
			b_node.set("offset_transform_enabled", true)
			b_node.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			b_node.set("offset_transform_scale", Vector2(0.96, 0.96))
			b_node.set("offset_transform_visual_only", false)
		else:
			b_node.scale = Vector2(0.96, 0.96)

		var tw := b_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(b_node, "modulate:a", 1.0, 0.16).set_delay(0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(b_node, "offset_transform_scale", Vector2.ONE, 0.18).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(b_node, "scale", Vector2.ONE, 0.18).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 6.
	var preview_node := get_node_or_null("preview") as Control
	if preview_node:
		preview_node.modulate.a = 0.0
		var has_offset: bool = "offset_transform_enabled" in preview_node
		if has_offset:
			preview_node.set("offset_transform_enabled", true)
			preview_node.set("offset_transform_pivot_ratio", Vector2(0.5, 0.5))
			preview_node.set("offset_transform_scale", Vector2(0.94, 0.94))
			preview_node.set("offset_transform_visual_only", false)
		else:
			var sz := preview_node.size
			if sz.x > 0 and sz.y > 0:
				preview_node.pivot_offset = sz * 0.5
			preview_node.scale = Vector2(0.94, 0.94)

		var tw := preview_node.create_tween().set_parallel(true)
		_cascade_tweens.append(tw)
		tw.tween_property(preview_node, "modulate:a", 1.0, 0.18).set_delay(0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if has_offset:
			tw.tween_property(preview_node, "offset_transform_scale", Vector2.ONE, 0.22).set_delay(0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(preview_node, "scale", Vector2.ONE, 0.22).set_delay(0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 7. Notification toast slide-in if warning is still active
	if _warning_panel and _warning_panel.visible:
		_warning_panel.modulate.a = 0.0
		_warning_panel.offset_top = 36.0
		_warning_panel.offset_bottom = 186.0
		var tw_warn := _warning_panel.create_tween().set_parallel(true)
		_cascade_tweens.append(tw_warn)
		tw_warn.tween_property(_warning_panel, "modulate:a", 1.0, 0.20).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_warn.tween_property(_warning_panel, "offset_top", 56.0, 0.22).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_warn.tween_property(_warning_panel, "offset_bottom", 206.0, 0.22).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
