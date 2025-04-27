extends Control

@onready var restart = $Panel/restart
@onready var close = $Panel/close

func _ready():
	restart.pressed.connect(_on_restart_pressed)
	close.pressed.connect(_on_close_pressed)

func _on_restart_pressed():
	# start_vanguard() # Chamada direta removida
	print("Botão Restart pressionado. Iniciando start_vanguard em uma thread...")
	var thread = Thread.new()
	# Passamos um Callable que referencia a função start_vanguard deste objeto
	thread.start(start_vanguard)
	# Nota: Não usamos thread.wait_to_finish() para não bloquear a thread principal.
	# A função start_vanguard agora rodará em segundo plano.

func _on_close_pressed():
	stop_vanguard() # Chama a função para parar o serviço
	# Opcional: Se também quiser fechar a aplicação Godot após parar o serviço:
	# get_tree().quit()
	# Se precisar fechar um processo Vanguard externo, a lógica seria diferente
	# Exemplo (Windows): OS.execute("taskkill", ["/IM", "vanguard.exe", "/F"], true)
	# Exemplo (Linux/macOS): OS.execute("killall", ["vanguard"], true)

# Função para iniciar o serviço Vanguard (vgc) E executar vgtray.exe
func start_vanguard():
	var service_started = false
	var tray_launched = false
	var vanguard_tray_path = "C:\\Program Files\\Riot Vanguard\\vgtray.exe"

	# 1. Tentar iniciar o serviço vgc
	print("Tentando iniciar o serviço Vanguard (vgc)...")
	var output_sc = []
	var exit_code_sc = OS.execute("sc", ["start", "vgc"], output_sc, false, false) 
	print("Comando 'sc start vgc' enviado (não bloqueante). Código de saída imediato: ", exit_code_sc)
	print("Saída SC (imediata, se houver): ", "\n".join(output_sc))
	if exit_code_sc == 0:
		print("Comando para iniciar o serviço Vanguard enviado com sucesso.")
		service_started = true # Assumimos que foi enviado, mas não garantimos que iniciou
	else:
		print("Falha ao enviar comando para iniciar o serviço Vanguard. Código de erro: ", exit_code_sc, " (Pode precisar de permissões de Admin)")

	# 2. Tentar executar vgtray.exe (agora baseado apenas se o COMANDO sc foi enviado)
	if service_started:
		print("Tentando executar vgtray.exe em: ", vanguard_tray_path)
		var output_tray = []
		var exit_code_tray = OS.execute(vanguard_tray_path, [], output_tray, false, false)
		print("Comando para executar vgtray.exe enviado. Código de saída imediato: ", exit_code_tray)
		print("Saída (se houver): ", "\n".join(output_tray))
		if exit_code_tray == 0:
			print("Comando para executar vgtray.exe enviado com sucesso.")
			tray_launched = true
		else:
			print("Falha ao tentar executar vgtray.exe. Código de erro: ", exit_code_tray)
	else:
		print("Não tentando executar vgtray.exe porque o serviço vgc não foi iniciado.")

	# Retornando sucesso baseado no envio dos comandos
	return service_started and tray_launched

# Função para parar o serviço vgc E o processo vgtray.exe
func stop_vanguard():
	var service_stopped = false
	var tray_killed = false

	# 1. Tentar parar o serviço vgc
	print("Tentando parar o serviço Vanguard (vgc)...")
	var output_sc = []
	var exit_code_sc = OS.execute("sc", ["stop", "vgc"], output_sc, true, false) 
	print("Comando 'sc stop vgc' executado. Código de saída: ", exit_code_sc)
	print("Saída SC: ", "\n".join(output_sc))
	if exit_code_sc == 0:
		print("Comando para parar serviço vgc enviado com sucesso (ou já estava parado).")
		service_stopped = true
	elif exit_code_sc == 1062: # Código para "Serviço não iniciado"
		print("Serviço vgc já estava parado.")
		service_stopped = true # Consideramos como sucesso nesse contexto
	else:
		print("Falha ao enviar comando para parar o serviço vgc. Código de erro: ", exit_code_sc, " (Pode precisar de permissões de Admin)")
	
	# Pequena pausa para dar tempo ao serviço parar antes de matar o tray (opcional mas pode ajudar)
	OS.delay_msec(500)

	# 2. Tentar parar o processo vgtray.exe
	print("Tentando parar o processo vgtray.exe...")
	var output_tk = []
	var exit_code_tk = OS.execute("taskkill", ["/IM", "vgtray.exe", "/F"], output_tk, true, false)
	print("Comando 'taskkill /IM vgtray.exe /F' executado. Código de saída: ", exit_code_tk)
	print("Saída Taskkill: ", "\n".join(output_tk))
	if exit_code_tk == 0:
		print("Processo vgtray.exe encerrado com sucesso.")
		tray_killed = true
	elif exit_code_tk == 128: # Código para "Processo não encontrado"
		print("Processo vgtray.exe não encontrado (já estava fechado?).")
		tray_killed = true # Consideramos como sucesso nesse contexto
	else:
		print("Falha ao encerrar o processo vgtray.exe. Código de erro: ", exit_code_tk, " (Pode precisar de permissões de Admin)")

	# Retorna true se ambos (ou os que deveriam ser parados) foram parados com sucesso
	return service_stopped and tray_killed
