class_name JsonFile
extends RefCounted

# Centralized JSON file load/save helpers.


# Loads and parses JSON data from path.
static func load_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("JsonFile: Could not open '%s' for reading. Error: %s" % [path, FileAccess.get_open_error()])
		return null

	var json_string := file.get_as_text()
	if json_string.is_empty():
		return null

	var parser := JSON.new()
	var error := parser.parse(json_string)
	if error != OK:
		printerr("JsonFile: Parse error in '%s': %s at line %d" % [path, parser.get_error_message(), parser.get_error_line()])
		return null

	return parser.get_data()


# Saves data as indented JSON to path, creating parent directories as needed.
static func save_data(path: String, data: Variant) -> bool:
	var json_string := JSON.stringify(data, "\t")

	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		printerr("JsonFile: Failed to create directory for '%s'. Error: %s" % [path, dir_error])
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("JsonFile: Could not open '%s' for writing. Error: %s" % [path, FileAccess.get_open_error()])
		return false

	file.store_string(json_string)
	return true
