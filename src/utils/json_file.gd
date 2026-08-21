class_name JsonFile
extends RefCounted

## Centralized JSON file load/save helpers.
## All JSON persistence in the project should go through this class.
##
## Saves are atomic: data is written to a temporary file first and then
## swapped into place, so a crash mid-save can never leave a truncated or
## half-written JSON file behind.

const TMP_SUFFIX := ".tmp"


## Loads and parses JSON data from [param path].
## Returns the parsed Variant (usually a Dictionary), or null if the file
## does not exist, is empty, or fails to parse.
static func load_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_recover_interrupted_save(path)
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


## Saves [param data] as indented JSON to [param path], creating parent
## directories as needed. The write is atomic (temp file + rename), so the
## previous file content survives any failure. Returns true on success.
static func save_data(path: String, data: Variant) -> bool:
	var json_string := JSON.stringify(data, "\t")

	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		printerr("JsonFile: Failed to create directory for '%s'. Error: %s" % [path, dir_error])
		return false

	var tmp_path := path + TMP_SUFFIX
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		printerr("JsonFile: Could not open '%s' for writing. Error: %s" % [tmp_path, FileAccess.get_open_error()])
		return false

	file.store_string(json_string)
	file.flush()
	file.close()

	# Swap the temp file into place. The old file is only removed after the
	# new content is fully on disk.
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(path)
		if remove_error != OK:
			printerr("JsonFile: Could not replace '%s'. Error: %s" % [path, remove_error])
			return false

	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error == OK:
		return true

	# Windows can hold a brief lock on the freshly removed file; retry.
	for attempt in 3:
		OS.delay_msec(100)
		rename_error = DirAccess.rename_absolute(tmp_path, path)
		if rename_error == OK:
			return true

	# Last resort: copy the content over (leaves no corrupt window).
	if DirAccess.copy_absolute(tmp_path, path) == OK:
		DirAccess.remove_absolute(tmp_path)
		return true

	printerr("JsonFile: Failed to finalize save of '%s'. Error: %s" % [path, rename_error])
	return false


## Recovers a temp file left behind when the app died between removing the
## old file and renaming the temp into place.
static func _recover_interrupted_save(path: String) -> void:
	var tmp_path := path + TMP_SUFFIX
	if not FileAccess.file_exists(tmp_path):
		return
	if DirAccess.rename_absolute(tmp_path, path) != OK:
		printerr("JsonFile: Found leftover temp save for '%s' but failed to recover it." % path)
	else:
		print("JsonFile: Recovered interrupted save for '%s'." % path)
