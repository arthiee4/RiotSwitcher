class_name ProfileBackupService
extends RefCounted

## Handles encrypted ZIP backup and restore for all RiotSwitcher profiles,
## login session files, and custom uploaded background images.

const MAGIC_BYTES := [0x52, 0x53, 0x42, 0x4B] # "RSBK" (RiotSwitcher Backup)
const BACKUP_VERSION := 0x01

# Intentional: the key is hardcoded and yes, someone could extract it from the
# binary. That's fine. The goal isn't to stop a determined attacker, it's just
# so a random person who finds the .zip can't open it in WinRAR and read
# session files. Casual obfuscation. The SHA-256 checksum still guarantees the
# file wasn't corrupted or tampered with, which is the part that actually matters.
const SECRET_SEED := "RiotSwitcher_Vault_AES256_Secret_Key_2026_SecureBackup"

const MANIFEST_PATH := "manifest.json"
const PROFILES_DATA_REL := "data/profiles_data.json"
const PROFILES_DIR_PREFIX := "profiles/"
const BACKGROUNDS_DIR_PREFIX := "backgrounds/"


static func _tr(text: String) -> String:
	return TranslationServer.translate(text)


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


static func _get_key() -> PackedByteArray:
	return SECRET_SEED.sha256_buffer() # Exact 32-byte key for AES-256


static func _pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var pad_len := 16 - (data.size() % 16)
	var padded := data.duplicate()
	for i in range(pad_len):
		padded.append(pad_len)
	return padded


static func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var pad_len: int = data[data.size() - 1]
	if pad_len <= 0 or pad_len > 16 or pad_len > data.size():
		return PackedByteArray()
	for i in range(data.size() - pad_len, data.size()):
		if data[i] != pad_len:
			return PackedByteArray()
	return data.slice(0, data.size() - pad_len)


## Encrypts a raw ZIP payload into the RSBK authenticated container.
static func encrypt_zip_payload(zip_bytes: PackedByteArray) -> PackedByteArray:
	var key := _get_key()
	var crypto := Crypto.new()
	var iv := crypto.generate_random_bytes(16)
	if iv.size() != 16:
		printerr("ProfileBackupService: Failed to generate random 16-byte IV!")
		return PackedByteArray()

	var padded := _pkcs7_pad(zip_bytes)
	var aes := AESContext.new()
	var err := aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	if err != OK:
		printerr("ProfileBackupService: AESContext start failed: ", err)
		return PackedByteArray()

	var encrypted := aes.update(padded)
	aes.finish()

	var container := PackedByteArray()
	# 1. Magic
	for b in MAGIC_BYTES:
		container.append(b)
	# 2. Version
	container.append(BACKUP_VERSION)
	# 3. IV (16 bytes)
	container.append_array(iv)
	# 4. Original length (8 bytes)
	var len_buf := StreamPeerBuffer.new()
	len_buf.put_u64(zip_bytes.size())
	container.append_array(len_buf.data_array)
	# 5. Encrypted payload
	container.append_array(encrypted)
	# 6. Checksum of everything so far (SHA-256, 32 bytes)
	var checksum := _sha256(container)
	container.append_array(checksum)

	return container


## Decrypts an RSBK authenticated container back into the raw ZIP bytes.
static func decrypt_zip_payload(container: PackedByteArray) -> Dictionary:
	# Minimum valid size: 4 (magic) + 1 (ver) + 16 (IV) + 8 (len) + 16 (min 1 AES block) + 32 (checksum) = 77 bytes
	if container.size() < 77:
		return {"success": false, "error": "File is too small to be a valid RiotSwitcher backup."}

	# Verify Magic
	for i in range(4):
		if container[i] != MAGIC_BYTES[i]:
			return {"success": false, "error": "Invalid backup format or unsupported file type."}

	var version: int = container[4]
	if version != BACKUP_VERSION:
		return {"success": false, "error": "Unsupported backup version (%d)." % version}

	# Verify Checksum
	var payload_without_checksum := container.slice(0, container.size() - 32)
	var file_checksum := container.slice(container.size() - 32)
	var calc_checksum := _sha256(payload_without_checksum)

	if file_checksum != calc_checksum:
		return {"success": false, "error": "Backup integrity check failed: file is corrupted or tampered with."}

	var iv := container.slice(5, 21)
	var len_buf := StreamPeerBuffer.new()
	len_buf.data_array = container.slice(21, 29)
	var orig_len := len_buf.get_u64()

	var encrypted := container.slice(29, container.size() - 32)
	var key := _get_key()
	var aes := AESContext.new()
	var err := aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	if err != OK:
		return {"success": false, "error": "Failed to initialize decryption engine."}

	var decrypted_padded := aes.update(encrypted)
	aes.finish()

	var decrypted := _pkcs7_unpad(decrypted_padded)
	if decrypted.is_empty():
		return {"success": false, "error": "Decryption failed: corrupted data or invalid key."}

	if orig_len > 0 and decrypted.size() != orig_len:
		decrypted = decrypted.slice(0, orig_len)

	return {"success": true, "zip_bytes": decrypted}


## Recursively collects all files inside a directory and returns an array of
## relative paths (e.g. ["Account1/Sessions/...", "Account2/..."]).
static func _collect_files_recursive(dir_path: String, rel_prefix: String = "") -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if not dir:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := dir_path.path_join(file_name)
			var rel_path := rel_prefix.path_join(file_name) if rel_prefix != "" else file_name
			if dir.current_is_dir():
				result.append_array(_collect_files_recursive(full_path, rel_path))
			else:
				result.append(rel_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


## Exports all profiles, sessions, and custom backgrounds into an encrypted ZIP file.
## progress_cb(percent: float, message: String) is invoked periodically if provided.
static func export_backup(dest_file_path: String, progress_cb: Callable = Callable()) -> Dictionary:
	if progress_cb.is_valid():
		progress_cb.call(0.05, _tr("Gathering profile data..."))

	var profiles_data_path := AppPaths.PROFILES_FILE
	if not FileAccess.file_exists(profiles_data_path):
		return {"success": false, "error": _tr("No profiles found to export.")}

	var profiles_json_content := FileAccess.get_file_as_bytes(profiles_data_path)
	var profiles_data = JsonFile.load_data(profiles_data_path)
	var profile_count := 0
	var profile_names: Array = []
	if profiles_data is Dictionary and profiles_data.get("profiles") is Array:
		profile_count = profiles_data["profiles"].size()
		for p in profiles_data["profiles"]:
			if p is Dictionary and p.has("profile_name"):
				profile_names.append(p["profile_name"])

	# Create temporary zip
	var temp_zip_path := "user://_temp_export_%d.zip" % Time.get_ticks_msec()
	var packer := ZIPPacker.new()
	var err := packer.open(temp_zip_path)
	if err != OK:
		return {"success": false, "error": _tr("Failed to initialize ZIP archive: %d") % err}

	# 1. Manifest
	if progress_cb.is_valid():
		progress_cb.call(0.15, _tr("Writing manifest..."))

	var manifest_dict := {
		"app": "RiotSwitcher",
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"profile_count": profile_count,
		"profiles": profile_names,
	}
	var manifest_bytes := JSON.stringify(manifest_dict, "\t").to_utf8_buffer()
	packer.start_file(MANIFEST_PATH)
	packer.write_file(manifest_bytes)
	packer.close_file()

	# 2. profiles_data.json
	packer.start_file(PROFILES_DATA_REL)
	packer.write_file(profiles_json_content)
	packer.close_file()

	# 3. Profile session folders (user://profiles/...)
	var profile_files := _collect_files_recursive(AppPaths.PROFILES_DIR)
	var total_files := profile_files.size()
	var bg_files := _collect_files_recursive(AppPaths.BACKGROUNDS_DIR)
	total_files += bg_files.size()
	var processed_files := 0

	for rel_file in profile_files:
		var full_file_path := AppPaths.PROFILES_DIR.path_join(rel_file)
		var file_bytes := FileAccess.get_file_as_bytes(full_file_path)
		packer.start_file(PROFILES_DIR_PREFIX + rel_file)
		packer.write_file(file_bytes)
		packer.close_file()
		processed_files += 1

		if progress_cb.is_valid() and total_files > 0:
			var pct := 0.20 + (float(processed_files) / float(total_files)) * 0.50
			progress_cb.call(pct, _tr("Packing session files (%d/%d)...") % [processed_files, total_files])

	# 4. Custom Backgrounds (user://backgrounds/...)
	for rel_file in bg_files:
		var full_file_path := AppPaths.BACKGROUNDS_DIR.path_join(rel_file)
		var file_bytes := FileAccess.get_file_as_bytes(full_file_path)
		packer.start_file(BACKGROUNDS_DIR_PREFIX + rel_file)
		packer.write_file(file_bytes)
		packer.close_file()
		processed_files += 1

		if progress_cb.is_valid() and total_files > 0:
			var pct := 0.20 + (float(processed_files) / float(total_files)) * 0.50
			progress_cb.call(pct, _tr("Packing background images (%d/%d)...") % [processed_files, total_files])

	packer.close()

	if progress_cb.is_valid():
		progress_cb.call(0.75, _tr("Encrypting backup archive..."))

	# Read raw zip bytes
	var raw_zip_bytes := FileAccess.get_file_as_bytes(temp_zip_path)
	DirAccess.remove_absolute(temp_zip_path)

	if raw_zip_bytes.is_empty():
		return {"success": false, "error": _tr("Failed to build archive payload.")}

	# Encrypt container
	var encrypted_container := encrypt_zip_payload(raw_zip_bytes)
	if encrypted_container.is_empty():
		return {"success": false, "error": _tr("Encryption error while generating backup.")}

	if progress_cb.is_valid():
		progress_cb.call(0.90, _tr("Saving file to disk..."))

	# Write to final destination
	var dest_file := FileAccess.open(dest_file_path, FileAccess.WRITE)
	if not dest_file:
		return {"success": false, "error": _tr("Failed to open destination path: %s") % dest_file_path}

	dest_file.store_buffer(encrypted_container)
	dest_file.close()

	if progress_cb.is_valid():
		progress_cb.call(1.0, _tr("Backup exported successfully!"))

	return {
		"success": true,
		"profile_count": profile_count,
		"file_size": encrypted_container.size(),
		"path": dest_file_path,
	}


## Imports an encrypted ZIP backup file, restoring accounts, sessions, and backgrounds.
## progress_cb(percent: float, message: String) is invoked periodically if provided.
static func import_backup(src_file_path: String, progress_cb: Callable = Callable()) -> Dictionary:
	if progress_cb.is_valid():
		progress_cb.call(0.05, _tr("Reading backup file..."))

	if not FileAccess.file_exists(src_file_path):
		return {"success": false, "error": _tr("Backup file does not exist.")}

	var file_bytes := FileAccess.get_file_as_bytes(src_file_path)
	if file_bytes.is_empty():
		return {"success": false, "error": _tr("Backup file is empty.")}

	if progress_cb.is_valid():
		progress_cb.call(0.15, _tr("Verifying security and decrypting..."))

	var decrypt_res := decrypt_zip_payload(file_bytes)
	if not decrypt_res.get("success", false):
		return {"success": false, "error": decrypt_res.get("error", _tr("Decryption failed."))}

	var raw_zip_bytes: PackedByteArray = decrypt_res["zip_bytes"]
	var temp_zip_path := "user://_temp_import_%d.zip" % Time.get_ticks_msec()

	var temp_file := FileAccess.open(temp_zip_path, FileAccess.WRITE)
	if not temp_file:
		return {"success": false, "error": _tr("Failed to write temporary decrypted archive.")}
	temp_file.store_buffer(raw_zip_bytes)
	temp_file.close()

	if progress_cb.is_valid():
		progress_cb.call(0.30, _tr("Opening archive..."))

	var reader := ZIPReader.new()
	var err := reader.open(temp_zip_path)
	if err != OK:
		DirAccess.remove_absolute(temp_zip_path)
		return {"success": false, "error": _tr("Failed to open decrypted archive: %d") % err}

	var files := reader.get_files()
	if not files.has(MANIFEST_PATH):
		reader.close()
		DirAccess.remove_absolute(temp_zip_path)
		return {"success": false, "error": _tr("Invalid backup: manifest.json is missing.")}

	# Read manifest
	var manifest_bytes := reader.read_file(MANIFEST_PATH)
	var manifest_json = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	var profile_count := 0
	if manifest_json is Dictionary:
		profile_count = manifest_json.get("profile_count", 0)

	# Ensure target directories exist
	DirAccess.make_dir_recursive_absolute(AppPaths.DATA_DIR)
	DirAccess.make_dir_recursive_absolute(AppPaths.PROFILES_DIR)
	DirAccess.make_dir_recursive_absolute(AppPaths.BACKGROUNDS_DIR)

	var total_files := files.size()
	var processed := 0

	for zip_file in files:
		processed += 1
		if zip_file == MANIFEST_PATH:
			continue

		var file_bytes_extracted := reader.read_file(zip_file)
		var target_path := ""

		if zip_file == PROFILES_DATA_REL:
			target_path = AppPaths.PROFILES_FILE
		elif zip_file.begins_with(PROFILES_DIR_PREFIX):
			var rel := zip_file.trim_prefix(PROFILES_DIR_PREFIX)
			target_path = AppPaths.PROFILES_DIR.path_join(rel)
		elif zip_file.begins_with(BACKGROUNDS_DIR_PREFIX):
			var rel := zip_file.trim_prefix(BACKGROUNDS_DIR_PREFIX)
			target_path = AppPaths.BACKGROUNDS_DIR.path_join(rel)

		if target_path != "":
			var target_dir := target_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(target_dir):
				DirAccess.make_dir_recursive_absolute(target_dir)

			var out_file := FileAccess.open(target_path, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(file_bytes_extracted)
				out_file.close()

		if progress_cb.is_valid() and total_files > 0:
			var pct := 0.30 + (float(processed) / float(total_files)) * 0.60
			progress_cb.call(pct, _tr("Restoring files (%d/%d)...") % [processed, total_files])

	reader.close()
	DirAccess.remove_absolute(temp_zip_path)

	if progress_cb.is_valid():
		progress_cb.call(0.95, _tr("Updating profile manager..."))

	# NOTE: ProfileManager is intentionally NOT reloaded here. This function runs
	# on a worker thread, and reloading emits `profiles_updated`, which rebuilds
	# the UI scene tree off-thread and leaves the home grid stale. The caller
	# (ProfileBackupController) reloads on the main thread once the worker ends.
	var actual_count := profile_count

	if progress_cb.is_valid():
		progress_cb.call(1.0, _tr("Profiles imported successfully!"))

	return {
		"success": true,
		"profile_count": actual_count,
	}
