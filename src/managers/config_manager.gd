extends Node

## Loads/saves the app configuration (user://data/configs.json) and
## broadcasts changes through the configs_updated signal.
##
## Access to _data is mutex-protected: values are also read from worker
## threads (session swaps) while the UI thread may save new settings.

signal configs_updated(new_config_data: Dictionary)

var _data: Dictionary = {}
var _lock := Mutex.new()


func _ready() -> void:
	load_configs()


## Reloads the config file from disk and notifies listeners.
func load_configs() -> Dictionary:
	_lock.lock()
	var parsed = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if parsed is Dictionary:
		_data = parsed
	else:
		_data = {}
	var snapshot: Dictionary = _data.duplicate()
	_lock.unlock()
	configs_updated.emit(snapshot)
	return snapshot


func get_value(key: String, default: Variant = null) -> Variant:
	_lock.lock()
	var value: Variant = _data.get(key, default)
	_lock.unlock()
	return value


## Sets a value and persists immediately. The current file is re-read first
## so keys written by other components (e.g. the language picker) are kept.
## The signal is emitted after the lock is released so listeners may call
## back into the manager without deadlocking.
func set_value_and_save(key: String, value: Variant) -> bool:
	_lock.lock()
	var on_disk = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if on_disk is Dictionary:
		_data = on_disk
	_data[key] = value
	var saved := JsonFile.save_data(AppPaths.CONFIG_FILE, _data)
	var snapshot: Dictionary = _data.duplicate()
	_lock.unlock()
	if not saved:
		printerr("ConfigManager: Failed to save config file.")
		return false
	configs_updated.emit.call_deferred(snapshot)
	return true
