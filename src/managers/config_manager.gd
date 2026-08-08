extends Node

## Loads/saves the app configuration (user://data/configs.json) and
## broadcasts changes through the configs_updated signal.

signal configs_updated(new_config_data: Dictionary)

var _data: Dictionary = {}


func _ready() -> void:
	load_configs()


## Reloads the config file from disk and notifies listeners.
func load_configs() -> Dictionary:
	var parsed = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if parsed is Dictionary:
		_data = parsed
	else:
		_data = {}
	configs_updated.emit(_data)
	return _data


func get_value(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)


## Sets a value and persists immediately. The current file is re-read first
## so keys written by other components (e.g. the language picker) are kept.
func set_value_and_save(key: String, value: Variant) -> bool:
	var on_disk = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if on_disk is Dictionary:
		_data = on_disk
	_data[key] = value
	if not JsonFile.save_data(AppPaths.CONFIG_FILE, _data):
		printerr("ConfigManager: Failed to save config file.")
		return false
	configs_updated.emit(_data)
	return true
