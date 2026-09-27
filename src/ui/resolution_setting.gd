class_name ResolutionSettingController
extends Control

# Resolution picker — three presets: Small, Default, Large.

const CONFIG_KEY := "WindowResolution"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576),   # Small
	Vector2i(1280, 720),   # Default
	Vector2i(1440, 810),   # Large
]

const RESOLUTION_LABELS: Array[String] = [
	"1024 × 576",
	"1280 × 720",
	"1440 × 810",
]

const DEFAULT_INDEX := 1 # 1280x720

@onready var _option: OptionButton = $Panel/OptionButton if has_node("Panel/OptionButton") else null


func _ready() -> void:
	if not _option:
		return
	_option.clear()
	for i in range(RESOLUTION_LABELS.size()):
		_option.add_item(RESOLUTION_LABELS[i], i)
	_option.item_selected.connect(_on_resolution_selected)
	_load_and_apply_saved_resolution()


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTIONS.size():
		return
	var res := RESOLUTIONS[index]
	_apply_resolution(res)
	_save_resolution(index)


func _apply_resolution(res: Vector2i) -> void:
	var win := get_window()
	if not win:
		return
	win.size = res
	# Center the window on the current screen.
	var screen_id := win.current_screen
	var screen_pos := DisplayServer.screen_get_position(screen_id)
	var screen_size := DisplayServer.screen_get_size(screen_id)
	win.position = screen_pos + (screen_size - res) / 2


func _load_and_apply_saved_resolution() -> void:
	var saved_index: int = DEFAULT_INDEX
	var config = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if config is Dictionary:
		var loaded: Variant = config.get(CONFIG_KEY, DEFAULT_INDEX)
		if loaded is int or loaded is float:
			var idx := int(loaded)
			if idx >= 0 and idx < RESOLUTIONS.size():
				saved_index = idx
	if _option:
		_option.select(saved_index)
	_apply_resolution(RESOLUTIONS[saved_index])


func _save_resolution(index: int) -> void:
	var config = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if not config is Dictionary:
		config = {}
	config[CONFIG_KEY] = index
	if not JsonFile.save_data(AppPaths.CONFIG_FILE, config):
		printerr("Resolution: Failed to save resolution setting.")
