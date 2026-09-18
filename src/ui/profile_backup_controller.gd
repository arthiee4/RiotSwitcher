class_name ProfileBackupController
extends Control

## Controller for the "Backup & Restore Profiles" card in the Settings menu.
## Provides side-by-side Export and Import buttons using Windows native FileDialog,
## runs tasks on background threads, and drives the BackupProgressModal.

@onready var _export_btn: Button = find_child("export_button", true, false) as Button
@onready var _import_btn: Button = find_child("import_button", true, false) as Button
@onready var _status_label: Label = find_child("status_label", true, false) as Label
@onready var _export_dialog: FileDialog = $export_dialog if has_node("export_dialog") else null
@onready var _import_dialog: FileDialog = $import_dialog if has_node("import_dialog") else null

var _worker_thread: Thread = null
var _progress_modal: BackupProgressModal = null


func _ready() -> void:
	if _export_btn:
		_export_btn.text = tr("Export")
		_export_btn.pressed.connect(_on_export_pressed)

	if _import_btn:
		_import_btn.text = tr("Import")
		_import_btn.pressed.connect(_on_import_pressed)

	# Locate the progress modal overlay in the tree
	_find_progress_modal.call_deferred()

	# File dialogs are authored in profile_backup_card.tscn; just wire their signals.
	if _export_dialog:
		_export_dialog.file_selected.connect(_on_export_file_selected)
	if _import_dialog:
		_import_dialog.file_selected.connect(_on_import_file_selected)


func _exit_tree() -> void:
	if _worker_thread and _worker_thread.is_started():
		_worker_thread.wait_to_finish()


func _find_progress_modal() -> void:
	var root := get_tree().root
	var found = root.find_child("backup_progress_modal", true, false)
	if found is BackupProgressModal:
		_progress_modal = found


func _on_export_pressed() -> void:
	if _worker_thread and _worker_thread.is_started():
		return

	var default_name := "RiotSwitcher_Backup_%s.zip" % Time.get_date_string_from_system().replace("-", "_")
	_export_dialog.current_file = default_name
	_export_dialog.popup_file_dialog()


func _on_import_pressed() -> void:
	if _worker_thread and _worker_thread.is_started():
		return

	_import_dialog.popup_file_dialog()


func _on_export_file_selected(path: String) -> void:
	if path.is_empty():
		return

	if not path.to_lower().ends_with(".zip"):
		path += ".zip"

	if _progress_modal:
		_progress_modal.open_modal(false)

	_set_buttons_enabled(false)

	if _worker_thread and _worker_thread.is_started():
		_worker_thread.wait_to_finish()
	_worker_thread = Thread.new()
	_worker_thread.start(_run_export.bind(path))


func _run_export(dest_path: String) -> void:
	var progress_cb := func(pct: float, msg: String):
		_notify_progress.call_deferred(pct, msg)

	var res := ProfileBackupService.export_backup(dest_path, progress_cb)
	_on_export_finished.call_deferred(res)


func _on_export_finished(res: Dictionary) -> void:
	if _worker_thread and _worker_thread.is_started():
		_worker_thread.wait_to_finish()

	_set_buttons_enabled(true)

	if res.get("success", false):
		var msg: String = tr("Exported %d profile(s) successfully!") % res.get("profile_count", 0)
		if _progress_modal:
			_progress_modal.finish_success(msg)
	else:
		var err_msg: String = res.get("error", tr("Export failed."))
		if _progress_modal:
			_progress_modal.finish_error(err_msg)
		if _status_label:
			_status_label.text = tr("Failed")
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.04, 0.14, 1.0))


func _on_import_file_selected(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return

	if _progress_modal:
		_progress_modal.open_modal(true)

	_set_buttons_enabled(false)

	if _worker_thread and _worker_thread.is_started():
		_worker_thread.wait_to_finish()
	_worker_thread = Thread.new()
	_worker_thread.start(_run_import.bind(path))


func _run_import(src_path: String) -> void:
	var progress_cb := func(pct: float, msg: String):
		_notify_progress.call_deferred(pct, msg)

	var res := ProfileBackupService.import_backup(src_path, progress_cb)
	_on_import_finished.call_deferred(res)


func _on_import_finished(res: Dictionary) -> void:
	if _worker_thread and _worker_thread.is_started():
		_worker_thread.wait_to_finish()

	_set_buttons_enabled(true)

	if res.get("success", false):
		# Reload on the main thread so the home grid repopulates immediately.
		var loaded: Array = ProfileManager.load_profiles_data()
		var count: int = loaded.size()
		var msg: String = tr("Imported %d profile(s) successfully!") % count
		if _progress_modal:
			_progress_modal.finish_success(msg)
		if _status_label:
			_status_label.text = tr("Restored %d") % count
			_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	else:
		var err_msg: String = res.get("error", tr("Import failed."))
		if _progress_modal:
			_progress_modal.finish_error(err_msg)
		if _status_label:
			_status_label.text = tr("Failed")
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.04, 0.14, 1.0))


func _notify_progress(pct: float, msg: String) -> void:
	if _progress_modal:
		_progress_modal.set_progress(pct, msg)


func _set_buttons_enabled(val: bool) -> void:
	if _export_btn:
		_export_btn.disabled = not val
	if _import_btn:
		_import_btn.disabled = not val
