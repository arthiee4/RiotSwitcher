class_name AccentSettingController
extends Control

const CONFIG_KEY := "AccentColor"
const UI_CONFIG_KEY := "UIStyle"

const PRESET_KEYS: Array[String] = [
	"white",
	"gold",
	"red",
	"blue",
	"green",
	"violet",
	"cyan",
	"orange",
	"pink",
	"gray",
]

const PRESETS: Dictionary = {
	"white": Color("f0e6d2"),
	"gold": Color("c8aa6e"),
	"red": Color("ff0000"),
	"blue": Color("4f8fd8"),
	"green": Color("45b878"),
	"violet": Color("9b70d8"),
	"cyan": Color("39c6c8"),
	"orange": Color("e08a3e"),
	"pink": Color("d96b9b"),
	"gray": Color("858b95"),
}

const PRESET_LABELS: Dictionary = {
	"white": "White",
	"gold": "Gold",
	"red": "Red",
	"blue": "Blue",
	"green": "Green",
	"violet": "Violet",
	"cyan": "Cyan",
	"orange": "Orange",
	"pink": "Pink",
	"gray": "Gray",
}

const UI_KEYS: Array[String] = [
	"fancy",
	"clean",
	"league_client",
]

const UI_LABELS: Dictionary = {
	"fancy": "Cyberpunk",
	"clean": "Classic",
	"league_client": "League Client",
}

@onready var _option: OptionButton = $Panel/OptionButton if has_node("Panel/OptionButton") else null
@onready var _ui_option: OptionButton = $Panel/UIOptionButton if has_node("Panel/UIOptionButton") else null

var _swatch_icon: Texture2D = null


func _ready() -> void:
	_swatch_icon = _create_swatch_icon()
	_populate_options()
	_populate_ui_options()
	if _option:
		_option.item_selected.connect(_on_option_selected)
	if _ui_option:
		_ui_option.item_selected.connect(_on_ui_option_selected)
	if not ConfigManager.configs_updated.is_connected(_on_configs_updated):
		ConfigManager.configs_updated.connect(_on_configs_updated)
	_refresh_selection(String(ConfigManager.get_value(CONFIG_KEY, "white")).to_lower())
	_refresh_ui_selection(String(ConfigManager.get_value(UI_CONFIG_KEY, "fancy")).to_lower())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_populate_options()
		_populate_ui_options()
		_refresh_selection(String(ConfigManager.get_value(CONFIG_KEY, "white")).to_lower())
		_refresh_ui_selection(String(ConfigManager.get_value(UI_CONFIG_KEY, "fancy")).to_lower())


func _create_swatch_icon() -> Texture2D:
	var size := 14
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var radius := 5.2
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			var alpha := clampf(radius + 0.6 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _populate_options() -> void:
	if not is_instance_valid(_option):
		return
	_option.clear()
	var popup := _option.get_popup()
	for i in range(PRESET_KEYS.size()):
		var key: String = PRESET_KEYS[i]
		var label_text: String = tr(String(PRESET_LABELS.get(key, key.capitalize())))
		if _swatch_icon:
			_option.add_icon_item(_swatch_icon, label_text, i)
			if popup:
				popup.set_item_icon_modulate(i, PRESETS.get(key, Color.WHITE))
		else:
			_option.add_item(label_text, i)


func _populate_ui_options() -> void:
	if not is_instance_valid(_ui_option):
		return
	_ui_option.clear()
	for i in range(UI_KEYS.size()):
		var key: String = UI_KEYS[i]
		var label_text: String = tr(String(UI_LABELS.get(key, key.capitalize())))
		_ui_option.add_item(label_text, i)
	var soon_idx := UI_KEYS.size()
	_ui_option.add_item(tr("Soon more themes..."), soon_idx)
	_ui_option.set_item_disabled(soon_idx, true)


func _on_option_selected(index: int) -> void:
	if index < 0 or index >= PRESET_KEYS.size():
		return
	var preset: String = PRESET_KEYS[index]
	if not PRESETS.has(preset):
		return
	ConfigManager.set_value_and_save(CONFIG_KEY, preset)
	_refresh_selection(preset)


func _on_ui_option_selected(index: int) -> void:
	if index < 0 or index >= UI_KEYS.size():
		return
	var ui_style: String = UI_KEYS[index]
	ConfigManager.set_value_and_save(UI_CONFIG_KEY, ui_style)
	_refresh_ui_selection(ui_style)


func _on_configs_updated(new_config: Dictionary) -> void:
	_refresh_selection(String(new_config.get(CONFIG_KEY, "white")).to_lower())
	_refresh_ui_selection(String(new_config.get(UI_CONFIG_KEY, "fancy")).to_lower())


func _refresh_selection(selected: String) -> void:
	if not is_instance_valid(_option) or _option.item_count == 0:
		return
	var idx := PRESET_KEYS.find(selected.to_lower())
	if idx < 0:
		idx = 0
	if _option.selected != idx:
		_option.select(idx)


func _refresh_ui_selection(selected: String) -> void:
	if not is_instance_valid(_ui_option) or _ui_option.item_count == 0:
		return
	var sel_lower := selected.to_lower()
	var no_custom_accent := (sel_lower == "clean" or sel_lower == "league_client")
	var idx := UI_KEYS.find(sel_lower)
	if idx < 0:
		idx = 0
	if _ui_option.selected != idx:
		_ui_option.select(idx)
	if is_instance_valid(_option):
		_option.disabled = no_custom_accent
		_option.modulate.a = 0.45 if no_custom_accent else 1.0


func apply_accent_color(_accent: Color) -> void:
	_refresh_selection(String(ConfigManager.get_value(CONFIG_KEY, "white")).to_lower())
	_refresh_ui_selection(String(ConfigManager.get_value(UI_CONFIG_KEY, "fancy")).to_lower())
