class_name VanguardController
extends Control

## Basic Riot Vanguard (vgc) service control. Commands run on a worker
## thread so the UI never freezes, and the thread is joined on exit.

@onready var _restart_button: Button = $Panel/restart
@onready var _close_button: Button = $Panel/close

const VANGUARD_TRAY_PATH := "C:\\Program Files\\Riot Vanguard\\vgtray.exe"

var _worker: Thread = null


func _ready() -> void:
	_restart_button.pressed.connect(_on_restart_pressed)
	_close_button.pressed.connect(_on_close_pressed)


func _exit_tree() -> void:
	if _worker and _worker.is_alive():
		_worker.wait_to_finish()


func _on_restart_pressed() -> void:
	_run_in_thread(_start_vanguard)


func _on_close_pressed() -> void:
	_run_in_thread(_stop_vanguard)


func _run_in_thread(task: Callable) -> void:
	if _worker and _worker.is_alive():
		print("Vanguard: Another operation is already running.")
		return
	_worker = Thread.new()
	_worker.start(task)


## Starts the vgc service and launches vgtray.exe. Runs on the worker thread.
func _start_vanguard() -> void:
	var output: Array = []
	var exit_code := OS.execute("sc", ["start", "vgc"], output, false, false)
	if exit_code != 0:
		printerr("Vanguard: Failed to send 'sc start vgc' (code %d). Admin rights may be required." % exit_code)
		return

	exit_code = OS.execute(VANGUARD_TRAY_PATH, [], output, false, false)
	if exit_code != 0:
		printerr("Vanguard: Failed to launch vgtray.exe (code %d)." % exit_code)


## Stops the vgc service and kills vgtray.exe. Runs on the worker thread.
func _stop_vanguard() -> void:
	var output: Array = []
	var exit_code := OS.execute("sc", ["stop", "vgc"], output, true, false)
	# 1062 = service was not running.
	if exit_code != 0 and exit_code != 1062:
		printerr("Vanguard: Failed to stop vgc service (code %d). Admin rights may be required." % exit_code)

	OS.delay_msec(500)

	exit_code = OS.execute("taskkill", ["/IM", "vgtray.exe", "/F"], output, true, false)
	# 128 = process not found.
	if exit_code != 0 and exit_code != 128:
		printerr("Vanguard: Failed to kill vgtray.exe (code %d)." % exit_code)
