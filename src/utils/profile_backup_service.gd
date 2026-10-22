class_name ProfileBackupService
extends RefCounted

# Handles password-protected ZIP backup and restore for all RiotSwitcher profiles, login session files, and custom uploaded background images.

const MAGIC_BYTES := [0x52, 0x53, 0x42, 0x4B] # "RSBK" (RiotSwitcher Backup)
const BACKUP_VERSION := 0x02
const LEGACY_BACKUP_VERSION := 0x01

# Legacy (v1) key, kept only to read old backups. It is public, so v1 files are obfuscated, not protected.
const LEGACY_SECRET_SEED := "RiotSwitcher_Vault_AES256_Secret_Key_2026_SecureBackup"

const MIN_PASSWORD_LENGTH := 8
const KDF_ITERATIONS := 600000
# Bounds for the iteration count read from a file, so a crafted header cannot stall the import thread.
const KDF_MIN_ITERATIONS := 100000
const KDF_MAX_ITERATIONS := 5000000
const SALT_SIZE := 16
const IV_SIZE := 16
const MAC_SIZE := 32

# v2 layout: magic(4) | version(1) | iterations u32(4) | salt(16) | iv(16) | plain length u64(8) | AES-256-CBC ciphertext | HMAC-SHA256(32) over everything before it.
const V2_HEADER_SIZE := 4 + 1 + 4 + SALT_SIZE + IV_SIZE + 8

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


static func _get_legacy_key() -> PackedByteArray:
	return LEGACY_SECRET_SEED.sha256_buffer() # Exact 32-byte key for AES-256


# PBKDF2-HMAC-SHA256 with a single 32-byte output block (RFC 8018).
static func _pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var first_block := salt.duplicate()
	first_block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, first_block)
	var result := u.duplicate()
	for i in range(1, iterations):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for j in range(32):
			result[j] ^= u[j]
	return result


# Derives independent encryption and MAC keys from the password, so the MAC key never doubles as the AES key.
static func _derive_keys(password: String, salt: PackedByteArray, iterations: int) -> Dictionary:
	var crypto := Crypto.new()
	var master := _pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations)
	return {
		"enc": crypto.hmac_digest(HashingContext.HASH_SHA256, master, "RSBK v2 encryption".to_utf8_buffer()),
		"mac": crypto.hmac_digest(HashingContext.HASH_SHA256, master, "RSBK v2 authentication".to_utf8_buffer()),
	}


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


static func _aes_cbc(mode: AESContext.Mode, key: PackedByteArray, iv: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var aes := AESContext.new()
	if aes.start(mode, key, iv) != OK:
		return PackedByteArray()
	var out := aes.update(data)
	aes.finish()
	return out


# Returns the container version of a backup file, or 0 when it is not a RiotSwitcher backup.
static func read_backup_version(file_path: String) -> int:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file or file.get_length() < 5:
		return 0
	var header := file.get_buffer(5)
	for i in range(4):
		if header[i] != MAGIC_BYTES[i]:
			return 0
	return header[4]


# Encrypts a raw ZIP payload into a v2 container protected by the given password.
static func encrypt_zip_payload(zip_bytes: PackedByteArray, password: String) -> PackedByteArray:
	if password.length() < MIN_PASSWORD_LENGTH:
		printerr("ProfileBackupService: Refusing to encrypt with a password shorter than %d characters." % MIN_PASSWORD_LENGTH)
		return PackedByteArray()

	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(SALT_SIZE)
	var iv := crypto.generate_random_bytes(IV_SIZE)
	if salt.size() != SALT_SIZE or iv.size() != IV_SIZE:
		printerr("ProfileBackupService: Failed to generate random salt/IV!")
		return PackedByteArray()

	var keys := _derive_keys(password, salt, KDF_ITERATIONS)
	var encrypted := _aes_cbc(AESContext.MODE_CBC_ENCRYPT, keys["enc"], iv, _pkcs7_pad(zip_bytes))
	if encrypted.is_empty():
		printerr("ProfileBackupService: AES encryption failed.")
		return PackedByteArray()

	var header := StreamPeerBuffer.new()
	header.big_endian = true
	header.put_data(PackedByteArray(MAGIC_BYTES))
	header.put_u8(BACKUP_VERSION)
	header.put_u32(KDF_ITERATIONS)
	header.put_data(salt)
	header.put_data(iv)
	header.put_u64(zip_bytes.size())

	var container := header.data_array
	container.append_array(encrypted)
	container.append_array(crypto.hmac_digest(HashingContext.HASH_SHA256, keys["mac"], container))
	return container


# Decrypts a backup container back into the raw ZIP bytes. v2 needs the password; v1 uses the legacy built-in key and ignores it.
static func decrypt_zip_payload(container: PackedByteArray, password: String = "") -> Dictionary:
	if container.size() < 5:
		return {"success": false, "error": _tr("File is too small to be a valid RiotSwitcher backup.")}

	for i in range(4):
		if container[i] != MAGIC_BYTES[i]:
			return {"success": false, "error": _tr("Invalid backup format or unsupported file type.")}

	var version: int = container[4]
	if version == LEGACY_BACKUP_VERSION:
		return _decrypt_legacy(container)
	if version != BACKUP_VERSION:
		return {"success": false, "error": _tr("Unsupported backup version (%d).") % version}

	# Smallest valid v2 file: header + one AES block + MAC.
	if container.size() < V2_HEADER_SIZE + 16 + MAC_SIZE or (container.size() - V2_HEADER_SIZE - MAC_SIZE) % 16 != 0:
		return {"success": false, "error": _tr("File is too small to be a valid RiotSwitcher backup.")}
	if password.is_empty():
		return {"success": false, "error": _tr("A password is required to import this backup.")}

	var header := StreamPeerBuffer.new()
	header.big_endian = true
	header.data_array = container.slice(5, V2_HEADER_SIZE)
	var iterations := header.get_u32()
	var salt: PackedByteArray = header.get_data(SALT_SIZE)[1]
	var iv: PackedByteArray = header.get_data(IV_SIZE)[1]
	var plain_len := header.get_u64()
	if iterations < KDF_MIN_ITERATIONS or iterations > KDF_MAX_ITERATIONS:
		return {"success": false, "error": _tr("Invalid backup format or unsupported file type.")}

	var keys := _derive_keys(password, salt, iterations)
	var crypto := Crypto.new()
	var mac_offset := container.size() - MAC_SIZE
	var expected_mac := crypto.hmac_digest(HashingContext.HASH_SHA256, keys["mac"], container.slice(0, mac_offset))
	# Verify before decrypting: a wrong password and a tampered file are indistinguishable by design.
	if not crypto.constant_time_compare(expected_mac, container.slice(mac_offset)):
		return {"success": false, "error": _tr("Wrong password or damaged backup file.")}

	var decrypted := _pkcs7_unpad(_aes_cbc(AESContext.MODE_CBC_DECRYPT, keys["enc"], iv, container.slice(V2_HEADER_SIZE, mac_offset)))
	if decrypted.is_empty() or decrypted.size() != plain_len:
		return {"success": false, "error": _tr("Wrong password or damaged backup file.")}

	return {"success": true, "zip_bytes": decrypted, "legacy": false}


# Reads a v1 container, whose key is built into the app and whose checksum is unkeyed.
static func _decrypt_legacy(container: PackedByteArray) -> Dictionary:
	# Minimum valid size: 4 (magic) + 1 (ver) + 16 (IV) + 8 (len) + 16 (min 1 AES block) + 32 (checksum) = 77 bytes
	if container.size() < 77:
		return {"success": false, "error": _tr("File is too small to be a valid RiotSwitcher backup.")}

	var payload_without_checksum := container.slice(0, container.size() - 32)
	if _sha256(payload_without_checksum) != container.slice(container.size() - 32):
		return {"success": false, "error": _tr("Backup integrity check failed: file is corrupted or tampered with.")}

	var iv := container.slice(5, 21)
	var len_buf := StreamPeerBuffer.new()
	len_buf.data_array = container.slice(21, 29)
	var orig_len := len_buf.get_u64()

	var decrypted := _pkcs7_unpad(_aes_cbc(AESContext.MODE_CBC_DECRYPT, _get_legacy_key(), iv, container.slice(29, container.size() - 32)))
	if decrypted.is_empty():
		return {"success": false, "error": _tr("Decryption failed: corrupted data or invalid key.")}

	if orig_len > 0 and decrypted.size() != orig_len:
		decrypted = decrypted.slice(0, orig_len)

	return {"success": true, "zip_bytes": decrypted, "legacy": true}


# Recursively collects all files inside a directory and returns an array of relative paths.
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


# Exports all profiles, sessions, and custom backgrounds into a ZIP file encrypted with the given password.
static func export_backup(dest_file_path: String, password: String, progress_cb: Callable = Callable()) -> Dictionary:
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

	# 1.
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

	# 2.
	packer.start_file(PROFILES_DATA_REL)
	packer.write_file(profiles_json_content)
	packer.close_file()

	# 3.
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

	# 4.
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
	var encrypted_container := encrypt_zip_payload(raw_zip_bytes, password)
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


# Imports an encrypted ZIP backup file, restoring accounts, sessions, and backgrounds. The password is ignored for legacy (v1) files.
static func import_backup(src_file_path: String, password: String, progress_cb: Callable = Callable()) -> Dictionary:
	if progress_cb.is_valid():
		progress_cb.call(0.05, _tr("Reading backup file..."))

	if not FileAccess.file_exists(src_file_path):
		return {"success": false, "error": _tr("Backup file does not exist.")}

	var file_bytes := FileAccess.get_file_as_bytes(src_file_path)
	if file_bytes.is_empty():
		return {"success": false, "error": _tr("Backup file is empty.")}

	if progress_cb.is_valid():
		progress_cb.call(0.15, _tr("Verifying security and decrypting..."))

	var decrypt_res := decrypt_zip_payload(file_bytes, password)
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

	# ProfileManager is reloaded on the main thread by the caller.
	var actual_count := profile_count

	if progress_cb.is_valid():
		progress_cb.call(1.0, _tr("Profiles imported successfully!"))

	return {
		"success": true,
		"profile_count": actual_count,
		"legacy": decrypt_res.get("legacy", false),
	}
