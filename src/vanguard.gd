extends Control

@onready var restart = $Panel/restart
@onready var close = $Panel/close

func _ready():
	restart.pressed.connect(_on_restart_pressed)
	close.pressed.connect(_on_close_pressed)

func _on_restart_pressed():
	print("Restart button pressed. Starting start_vanguard in a thread...")
	var thread = Thread.new()
	thread.start(start_vanguard)

func _on_close_pressed():
	# Potential improvement: Run stop_vanguard in a thread as well?
	stop_vanguard() 

# Starts the vgc service and launches vgtray.exe
func start_vanguard():
	var service_started = false
	var tray_launched = false
	var vanguard_tray_path = "C:\\Program Files\\Riot Vanguard\\vgtray.exe"

	print("Attempting to start Vanguard service (vgc)...")
	var output_sc = []
	# Non-blocking call
	var exit_code_sc = OS.execute("sc", ["start", "vgc"], output_sc, false, false) 
	print("Command 'sc start vgc' sent (non-blocking). Immediate exit code: ", exit_code_sc)
	print("SC Output (immediate, if any): ", "\n".join(output_sc))
	if exit_code_sc == 0:
		print("Command to start Vanguard service sent successfully.")
		service_started = true 
	else:
		print("Failed to send command to start Vanguard service. Error code: ", exit_code_sc, " (Admin permissions might be required)")

	if service_started:
		print("Attempting to execute vgtray.exe at: ", vanguard_tray_path)
		var output_tray = []
		var exit_code_tray = OS.execute(vanguard_tray_path, [], output_tray, false, false)
		print("Command to execute vgtray.exe sent. Immediate exit code: ", exit_code_tray)
		print("Tray Output (if any): ", "\n".join(output_tray))
		if exit_code_tray == 0:
			print("Command to execute vgtray.exe sent successfully.")
			tray_launched = true
		else:
			print("Failed to execute vgtray.exe. Error code: ", exit_code_tray)
	else:
		print("Not attempting to execute vgtray.exe because vgc service start command failed.")

	return service_started and tray_launched

# Stops the vgc service and kills vgtray.exe
func stop_vanguard():
	var service_stopped = false
	var tray_killed = false

	print("Attempting to stop Vanguard service (vgc)...")
	var output_sc = []
	# Blocking call - consider making non-blocking or running in thread if it causes freezes
	var exit_code_sc = OS.execute("sc", ["stop", "vgc"], output_sc, true, false) 
	print("Command 'sc stop vgc' executed. Exit code: ", exit_code_sc)
	print("SC Output: ", "\n".join(output_sc))
	if exit_code_sc == 0:
		print("Command to stop vgc service sent successfully (or already stopped).")
		service_stopped = true
	elif exit_code_sc == 1062: # Service not started
		print("vgc service was already stopped.")
		service_stopped = true 
	else:
		print("Failed to send command to stop vgc service. Error code: ", exit_code_sc, " (Admin permissions might be required)")
	
	# Short delay for the service to stop before killing the tray
	OS.delay_msec(500)

	print("Attempting to kill vgtray.exe process...")
	var output_tk = []
	# Blocking call - consider making non-blocking or running in thread if it causes freezes
	var exit_code_tk = OS.execute("taskkill", ["/IM", "vgtray.exe", "/F"], output_tk, true, false)
	print("Command 'taskkill /IM vgtray.exe /F' executed. Exit code: ", exit_code_tk)
	print("Taskkill Output: ", "\n".join(output_tk))
	if exit_code_tk == 0:
		print("vgtray.exe process killed successfully.")
		tray_killed = true
	elif exit_code_tk == 128: # Process not found
		print("vgtray.exe process not found (already closed?).")
		tray_killed = true 
	else:
		print("Failed to kill vgtray.exe process. Error code: ", exit_code_tk, " (Admin permissions might be required)")

	return service_stopped and tray_killed
