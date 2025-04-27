extends Control

@onready var dropdown = $Panel/OptionButton

# Configuration path
const CONFIG_PATH = "res://Data/configs.json"

# My mapping from item index to locale code
# I want English (en_US) at index 0 (default)
var locales = {
	0: "en_US", # English (US)
	1: "pt_BR", # Portuguese (Brazil)
	2: "zh_CN", # Chinese (Simplified)
	3: "es_ES", # Spanish (Spain)
	4: "ko_KR"  # Korean
}

# My mapping from locale code to display name
var locale_names = {
	"en_US": "English (US)",
	"pt_BR": "Português (Brasil)",
	"zh_CN": "中文 (简体)",
	"es_ES": "Español (España)",
	"ko_KR": "한국어" # Korean
}

func _ready():
	# Load saved language preference first
	_load_and_apply_saved_locale()

	# I should clear existing items first (just in case)
	dropdown.clear()

	# Now I add items to the OptionButton using my 'locales' order
	# This loop makes sure the order is 0, 1, 2, 3, 4
	for id in locales:
		var locale_code = locales[id]
		if locale_names.has(locale_code):
			dropdown.add_item(locale_names[locale_code], id)
		else:
			# Fallback if I forget a name in locale_names
			dropdown.add_item(locale_code, id)

	# I need to connect the item_selected signal to my function
	dropdown.item_selected.connect(_on_language_selected)

	# Set the initial selection based on the *now potentially loaded* current locale
	_update_dropdown_selection()

# This function receives notifications from the engine (Godot 3 style)
func _notification(what):
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		print("Translation changed notification received. Updating dropdown selection.")
		_update_dropdown_selection()


func _on_language_selected(index: int):
	# Get the locale code from the selected index
	if locales.has(index):
		var selected_locale = locales[index]
		# Only set the global locale if it's actually different
		if TranslationServer.get_locale() != selected_locale:
			print("Dropdown selected: ", selected_locale, " - Setting global locale.")
			# Set the global locale here
			TranslationServer.set_locale(selected_locale)
			# Save the newly selected locale to config
			_save_selected_locale_to_config(selected_locale)
			# NOTE: The NOTIFICATION_TRANSLATION_CHANGED will be sent by the engine
			# and trigger _update_dropdown_selection in all relevant nodes.
	else:
		printerr("Invalid language index selected: ", index)

# Helper function to update this dropdown's selection based on the current global locale
func _update_dropdown_selection():
	# Add a check here to make sure dropdown is ready
	if not is_instance_valid(dropdown):
		# print("Dropdown node is not ready yet in _update_dropdown_selection. Skipping.") # Optional: Reduce log noise
		return

	var current_locale = TranslationServer.get_locale()
	var selected_id = 0 # Default to English (index 0)
	for id in locales:
		if locales[id] == current_locale:
			selected_id = id
			break # Stop searching once I find it

	# Prevent calling select unnecessarily if the dropdown is already correct
	if dropdown.selected != selected_id:
		# print("Updating dropdown ID to: ", selected_id, " for locale: ", current_locale) # Optional: Reduce log noise
		dropdown.select(selected_id)


# --- Config Saving/Loading ---

# Loads the saved locale from config and applies it
func _load_and_apply_saved_locale():
	var config_data = _load_json_data(CONFIG_PATH)
	var saved_locale = "en_US" # Default to English

	if config_data and config_data.has("SelectedLanguage"):
		var loaded_locale = config_data["SelectedLanguage"]
		# Validate if the loaded locale is one we actually support
		var valid = false
		for id in locales:
			if locales[id] == loaded_locale:
				valid = true
				break
		if valid:
			saved_locale = loaded_locale
			print("Loaded saved locale: ", saved_locale)
		else:
			print("Warning: Saved locale '", loaded_locale, "' is not supported. Using default.")
	else:
		print("No saved locale found in config. Using default.")

	# Apply the loaded (or default) locale
	if TranslationServer.get_locale() != saved_locale:
		TranslationServer.set_locale(saved_locale)


# Saves the selected locale to the config file
func _save_selected_locale_to_config(locale_code: String):
	var config_data = _load_json_data(CONFIG_PATH)
	if config_data == null: config_data = {} # Start fresh if load failed

	config_data["SelectedLanguage"] = locale_code

	if not _save_json_data(CONFIG_PATH, config_data):
		printerr("Failed to save selected language to config!")
	else:
		print("Saved selected language '", locale_code, "' to config.")


# Utility to load and parse JSON data from a file.
# Returns the parsed data (usually a Dictionary) or null on error.
func _load_json_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		# printerr("JSON file not found at: ", path) # Less verbose
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("Could not open JSON file: ", path)
		return null
	var json_string = file.get_as_text()
	file.close()
	if json_string.is_empty(): # Handle empty file case
		return {} # Return empty dictionary for empty file
	var json_parser = JSON.new()
	var error = json_parser.parse(json_string)
	if error != OK:
		printerr("Error parsing JSON (code: %s) in %s: %s at line %s" %
			[error, path.get_file(), json_parser.get_error_message(), json_parser.get_error_line()])
		return null
	return json_parser.get_data()


# Utility to save data to a JSON file.
# Returns true on success, false on failure
func _save_json_data(path: String, data: Variant) -> bool:
	var json_string = JSON.stringify(data, "\t") # Use tab for indentation
	# Ensure directory exists (though "res://" usually does)
	var dir_path = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var save_file = FileAccess.open(path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(json_string)
		save_file.close()
		# print("JSON data saved successfully to: ", path) # Less verbose
		return true
	else:
		printerr("Error saving JSON data to: ", path)
		return false


# (Optional) My optional function to update texts that don't change automatically
# func _update_ui_texts():
	# Example: $SomeLabel.text = tr("SOME_KEY")
	# I should call this at the end of _on_language_selected if I use it.
