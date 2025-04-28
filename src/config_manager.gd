extends Node

const CONFIG_PATH = "res://Data/configs.json"

var config_data: Dictionary = {}

# Signal emitted when config data is loaded or changed.
signal configs_updated(new_config_data)

func _ready():
	load_configs()

# Loads the JSON data from the specified path.
func load_configs() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		printerr("Config file not found at: ", CONFIG_PATH)
		config_data = {}
		print("[ConfigManager] Emitting configs_updated (file not found case)")
		emit_signal("configs_updated", config_data)
		return config_data

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		printerr("Could not open config file: ", CONFIG_PATH, " Error: ", FileAccess.get_open_error())
		config_data = {}
		print("[ConfigManager] Emitting configs_updated (file open error case)")
		emit_signal("configs_updated", config_data)
		return config_data

	var json_string = file.get_as_text()

	if json_string.is_empty() and FileAccess.get_open_error() == OK:
		print("Warning: Config file is empty: ", CONFIG_PATH)
		config_data = {}
		print("[ConfigManager] Emitting configs_updated (empty file case)")
		emit_signal("configs_updated", config_data)
		return config_data

	var json_parser = JSON.new()
	var error = json_parser.parse(json_string)
	if error != OK:
		printerr("Error parsing JSON (code: %s) in %s: %s at line %s" %
			[error, CONFIG_PATH.get_file(), json_parser.get_error_message(), json_parser.get_error_line()])
		config_data = {}
		print("[ConfigManager] Emitting configs_updated (JSON parse error case)")
		emit_signal("configs_updated", config_data)
		return config_data

	config_data = json_parser.get_data()
	if not config_data is Dictionary:
		printerr("Parsed config data is not a dictionary. Path: ", CONFIG_PATH)
		config_data = {} # Ensure it's a dictionary

	print("[ConfigManager] Config data loaded successfully. Emitting configs_updated signal...")
	emit_signal("configs_updated", config_data)
	print("Config data loaded successfully.")
	return config_data

# Saves the provided data (Dictionary) to the JSON file.
func save_configs(data_to_save: Dictionary) -> bool:
	print("[ConfigManager] Attempting to save configs. Data: ", data_to_save)
	var json_string = JSON.stringify(data_to_save, "	")
	if json_string.is_empty() and not data_to_save.is_empty():
		printerr("ConfigManager: Failed to stringify config data for saving.")
		return false

	# Ensure directory exists before writing
	var dir_path = CONFIG_PATH.get_base_dir()
	print("[ConfigManager] Ensuring directory exists: ", dir_path)
	var dir_err = DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_err != OK:
		printerr("ConfigManager: Failed to ensure directory exists for saving JSON: '%s'. Error: %s" % [dir_path, dir_err])
		return false
	
	print("[ConfigManager] Opening file for write: ", CONFIG_PATH)
	var save_file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if save_file:
		print("[ConfigManager] Storing string...")
		save_file.store_string(json_string)
		var write_err = FileAccess.get_open_error()
		if write_err == OK:
			print("[ConfigManager] JSON data saved successfully to: ", CONFIG_PATH) 
			# Update internal state and notify listeners only on successful write
			config_data = data_to_save
			emit_signal("configs_updated", config_data)
			return true
		else:
			printerr("ConfigManager: Error writing JSON data to '%s'. Error code: %s" % [CONFIG_PATH, write_err])
			return false
	else:
		printerr("ConfigManager: Error opening JSON file for writing: '%s'. Error code: %s" % [CONFIG_PATH, FileAccess.get_open_error()])
		return false

# Gets a specific value from the loaded config data.
func get_value(key: String, default: Variant = null) -> Variant:
	return config_data.get(key, default)

# Sets a specific value in the config data and saves it immediately.
func set_value_and_save(key: String, value: Variant) -> bool:
	print("[ConfigManager] set_value_and_save called for key: ", key, " | value: ", value)
	config_data[key] = value
	print("[ConfigManager] Calling save_configs from set_value_and_save.")
	return save_configs(config_data) 
