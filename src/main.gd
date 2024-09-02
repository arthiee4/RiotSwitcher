extends Control

@onready var closebutton = $closebutton
@onready var minimizebutton = $minimizebutton
@onready var accounts_container = $CenterContainer/accounts_container
@onready var add_prof = $CenterContainer/accounts_container/add_prof

@onready var debuglabel = $debuglabel

@onready var createmenu = $createmenupanel
@onready var createmenu_picture = $createmenupanel/createmenu/picturechange
@onready var create_button = $createmenupanel/createmenu/GridContainer/GridContainer/create_button
@onready var cancel_button = $createmenupanel/createmenu/GridContainer/GridContainer/cancel_button

@onready var profile_name_lineedit = $createmenupanel/createmenu/GridContainer/LineEdit

@onready var newaddmenu_imagem = $Panel/newaddmenu/GridContainer/TextureRect
@onready var newddmenu_cancel_button = $Panel/newaddmenu/GridContainer/GridContainer/cancel_button
@onready var newaddmenu_lineedit = $Panel/newaddmenu/GridContainer/LineEdit
@onready var newaddmenu = $Panel
@onready var newaddmenu_create_button = $Panel/newaddmenu/GridContainer/GridContainer/create_button

@onready var browser_create_icon_button = $Panel/Label/createfiledialogbutton
@onready var createfiledialog = $Panel/Label/creatediag
@onready var icon0 = $"Panel/iconsgrid/0"
@onready var icon1 = $"Panel/iconsgrid/1"
@onready var icon2 = $"Panel/iconsgrid/2"
@onready var icon3 = $"Panel/iconsgrid/3"
@onready var icon4 = $"Panel/iconsgrid/4"
@onready var icon5 = $"Panel/iconsgrid/5"
@onready var icon6 = $"Panel/iconsgrid/6"
@onready var icon7 = $"Panel/iconsgrid/7"
@onready var icon8 = $"Panel/iconsgrid/8"
@onready var icon9 = $"Panel/iconsgrid/9"

@onready var loadbar = $loadbar
@onready var loadconfirm = $loadbar/loadconfirm

@onready var video_player  = $CenterContainer/accounts_container/add_prof/Panel/VideoStreamPlayer

@onready var browser_button = $createmenupanel/createmenu/browser_image
@onready var file_dialog = $createmenupanel/createmenu/FileDialog

@onready var add_prof_panel = $CenterContainer/accounts_container/add_prof/Panel


var account_prof_scene = preload("res://scenes/func/account_prof.tscn")
var mouse_menu_scene = preload("res://scenes/menu/mouse_menu.tscn")
var account_prof_list = []
var max_accounts = 20
var config_file_path = "res://config.json"
var active_mouse_menu = null
var dragging = false
var drag_offset = Vector2()
var current_account_prof = null

var selected_icon_texture: Texture = null
var selected_icon_index = -1

func _ready():

	_pause_after_delay()

	loadconfirm.visible = false
	loadbar.visible = false
	createmenu.visible = false
	newaddmenu.visible = false
	closebutton.pressed.connect(_on_closebutton_pressed)
	minimizebutton.pressed.connect(_on_minimizebutton_pressed)
	add_prof.pressed.connect(_on_addprof_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	newaddmenu_create_button.pressed.connect(_on_newaddmenu_create_button_pressed)
	newddmenu_cancel_button.pressed.connect(on_newddmenu_cancel_button_pressed)
	loadconfirm.connect("pressed", Callable(self, "_on_loadconfirm_pressed"))
	
	browser_button.connect("pressed", Callable(self, "_on_browser_button_pressed"))
	file_dialog.connect("file_selected", Callable(self, "_on_file_selected"))
	
	icon0.connect("pressed", Callable(self, "_on_icon_pressed").bind(0))
	icon1.connect("pressed", Callable(self, "_on_icon_pressed").bind(1))
	icon2.connect("pressed", Callable(self, "_on_icon_pressed").bind(2))
	icon3.connect("pressed", Callable(self, "_on_icon_pressed").bind(3))
	icon4.connect("pressed", Callable(self, "_on_icon_pressed").bind(4))
	icon5.connect("pressed", Callable(self, "_on_icon_pressed").bind(5))
	icon6.connect("pressed", Callable(self, "_on_icon_pressed").bind(6))
	icon7.connect("pressed", Callable(self, "_on_icon_pressed").bind(7))
	icon8.connect("pressed", Callable(self, "_on_icon_pressed").bind(8))
	icon9.connect("pressed", Callable(self, "_on_icon_pressed").bind(9))
	

	add_prof_panel.connect("mouse_entered", Callable(self, "_on_add_prof_panel_mouse_entered"))
	add_prof_panel.connect("mouse_exited", Callable(self, "_on_add_prof_panel_mouse_exited"))
	
	_load_existing_profiles()
	_move_add_prof_to_end()
	_create_shortcut()
	
func _on_add_prof_panel_mouse_entered():
	var tween = get_tree().create_tween()
	tween.tween_property(add_prof_panel, "rotation_degrees", 90, 0.5)

func _on_add_prof_panel_mouse_exited():
	var tween = get_tree().create_tween()
	tween.tween_property(add_prof_panel, "rotation_degrees", 0, 0.5)

func _on_icon_pressed(index: int):
	selected_icon_index = index
	print("Ícone selecionado:", index)
	
	# Carrega a textura do ícone selecionado
	var selected_icon = get_icon_by_index()
	if selected_icon != null:
		var icon_name = selected_icon.name
		selected_icon_texture = load("res://assets/icons/%s.png" % icon_name)
		
		# Atualiza o TextureRect do newaddmenu para mostrar o ícone selecionado
		if selected_icon_texture != null:
			newaddmenu_imagem.texture = selected_icon_texture
		else:
			print("Falha ao carregar a textura para o ícone:", icon_name)
	else:
		print("Ícone selecionado é inválido.")
	
func copy_file(src: String, dest: String) -> void:
	var file = FileAccess.open(src, FileAccess.READ)
	if file == null:
		print("Falha ao abrir o arquivo de origem:", src)
		return

	var dest_file = FileAccess.open(dest, FileAccess.WRITE)
	if dest_file == null:
		print("Falha ao abrir o arquivo de destino:", dest)
		file.close()
		return

	dest_file.store_buffer(file.get_buffer(file.get_length()))
	file.close()
	dest_file.close()
	print("Arquivo copiado com sucesso de", src, "para", dest)


func _icon_set_on_create(new_account_prof):
	var selected_icon = get_icon_by_index()
	
	if selected_icon != null:
		var icon_name = selected_icon.name
		var dest_folder = "res://profiles/FOLDER_%s/" % new_account_prof.name
		
		copy_file("res://assets/icons/%s.png" % icon_name, dest_folder + "default_icon.png")
		print("Ícone %s configurado para o perfil %s" % [icon_name, new_account_prof.name])
	
func get_icon_by_index() -> Node:
	var icons = [
		icon0, icon1, icon2, icon3, icon4, 
		icon5, icon6, icon7, icon8, icon9
	]
	
	if selected_icon_index >= 0 and selected_icon_index < icons.size():
		return icons[selected_icon_index]
	else:
		return null
	
func _on_browser_button_pressed():
	file_dialog.popup()
	
func _on_filedialog_dir_selected(dir_path):
	pass
		
func _pause_after_delay():
	await get_tree().create_timer(2.5).timeout
	video_player.paused = true
	
func on_newddmenu_cancel_button_pressed():
	newaddmenu.visible = false
	
func _on_addprof_pressed():
	if account_prof_list.size() >= max_accounts:
		return
	newaddmenu.visible = true
	newaddmenu_lineedit.text = ""	

func _on_newaddmenu_create_button_pressed():
	newaddmenu.visible = false

	var new_profile_name = newaddmenu_lineedit.text.strip_edges()

	# Verifica se já existe um perfil com o mesmo nome
	for account_prof in account_prof_list:
		if account_prof.name == new_profile_name:
			print("Já existe um perfil com esse nome!")            
			return

	# Instancia o novo perfil
	var new_account_prof = account_prof_scene.instantiate()
	new_account_prof.name = new_profile_name

	# Adiciona o novo perfil ao contêiner
	accounts_container.add_child(new_account_prof)
	_move_add_prof_to_end()

	account_prof_list.append(new_account_prof)

	# Cria a pasta para o novo perfil
	_account_folder_created(new_account_prof)

	# Carrega o perfil a partir do JSON
	_load_account_prof_from_json(new_account_prof)

	# Configura o menu do mouse e animações
	_setup_mouse_menu(new_account_prof)
	_animate_account_prof(new_account_prof)

	# Exibe a barra de carregamento
	loadbar.visible = true
	if loadbar.visible:
		
		_riot_configs_delete()
		await get_tree().create_timer(3.5).timeout
		loadbar.value = 20
		await get_tree().create_timer(2.5).timeout
		loadbar.value = 50

		_open_riot_shortcut()

		await get_tree().create_timer(0.5).timeout
		loadbar.value = 100
		loadconfirm.visible = true

		await _await_button_press(loadconfirm)
		_riot_kill()
		
		await get_tree().create_timer(1.0).timeout
		loadbar.visible = false

	print("Novo perfil adicionado: ", new_account_prof.name)

	# Move as configurações para o novo perfil e define o ícone
	_riot_configs_move(new_account_prof)
	_icon_set_on_create(new_account_prof)

	# Reinicia o valor da barra de carregamento
	loadbar.value = 0

func _on_loadconfirm_pressed():
	print("Botão de confirmar pressionado")

func _await_button_press(button) -> void:
	await button.pressed

func _open_riot_shortcut():
	OS.shell_open("profiles\\riotshortcut.lnk")

func _create_shortcut():
	var config_data = _load_config_file()

	var launcher_lang =config_data["launcher_settings"]["launcher_lang"]
	var riot_location = config_data["launcher_settings"]["riotlocation"]
	var target_path = riot_location + "/RiotClientServices.exe"
	
	if target_path == "":
		print("Riotlocation não definido corretamente no config.json")
		return
	
	var _folder_name = "profiles" 
	var shortcut_path = "profiles\\riotshortcut.lnk"
	
	var arguments = "--launch-product=league_of_legends --launch-patchline=live %s" %launcher_lang 
	
	var commands = 'powershell -command " '
	commands += '$WshShell = New-Object -ComObject WScript.Shell; '
	commands += '$Shortcut = $WshShell.CreateShortcut(\'%s\'); ' % shortcut_path
	commands += '$Shortcut.TargetPath = \'%s\'; ' % target_path
	commands += '$Shortcut.Arguments = \'%s\'; ' % arguments
	commands += '$Shortcut.Save()"'
	
	var _result = OS.execute("cmd.exe", ["/c", commands], [], false)

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if active_mouse_menu and not active_mouse_menu.get_global_rect().has_point(get_global_mouse_position()):
				_hide_all_mouse_menus()

		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_offset = event.position

	if event is InputEventMouseMotion and dragging:
		var window_position = Vector2(DisplayServer.window_get_position().x, DisplayServer.window_get_position().y)
		var new_position = window_position + event.position - drag_offset
		DisplayServer.window_set_position(new_position)

func _on_cancel_button_pressed():
	_hide_all_mouse_menus()
	createmenu.visible = false

func _on_closebutton_pressed():
	get_tree().quit()

func _on_minimizebutton_pressed():
	get_tree().root.mode = Window.MODE_MINIMIZED

func _setup_mouse_menu(account_prof):
	var mouse_menu = account_prof.get_node("mouse_menu")
	if mouse_menu:
		mouse_menu.visible = false

	account_prof.connect("gui_input", Callable(self, "_on_account_prof_gui_input").bind(account_prof))

	var delete_button = mouse_menu.get_node("deletebutton")
	if delete_button:
		delete_button.pressed.connect(Callable(self, "_on_delete_button_pressed").bind(account_prof))

	var edit_button = mouse_menu.get_node("editprofilebutton")
	if edit_button:
		edit_button.pressed.connect(Callable(self, "_on_edit_button_pressed").bind(account_prof))

	account_prof.connect("mouse_entered", Callable(self, "_on_account_prof_mouse_entered").bind(account_prof))
	account_prof.connect("mouse_exited", Callable(self, "_on_account_prof_mouse_exited").bind(account_prof))
	
func _on_account_prof_mouse_entered(account_prof):
	if active_mouse_menu and active_mouse_menu.visible:
		return

	_animate_account_prof_growth(account_prof)

func _on_account_prof_mouse_exited(account_prof):
	if active_mouse_menu and active_mouse_menu.visible:
		return
	_animate_account_prof_reduction(account_prof)

func _animate_account_prof_growth(account_prof):
	if is_instance_valid(account_prof):
		debuglabel.text = account_prof.name
		var tween = get_tree().create_tween()
		tween.tween_property(account_prof, "scale", Vector2(1.1, 1.1), 0.2)

func _animate_account_prof_reduction(account_prof):
	if account_prof:
		debuglabel.text = ""
		var tween = get_tree().create_tween()
		tween.tween_property(account_prof, "scale", Vector2(1, 1), 0.2)
		
func _update_debuglabel_position():

	var mouse_position = get_global_mouse_position()
	debuglabel.position = mouse_position + Vector2(10, 10)  

func _process(_delta):
	if debuglabel.visible:
		_update_debuglabel_position()

func _on_account_prof_gui_input(event, account_prof):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if active_mouse_menu:

			active_mouse_menu.visible = false
			_reset_account_prof_scale(active_mouse_menu.get_parent())

		var mouse_menu = account_prof.get_node("mouse_menu")
		if mouse_menu:
			debuglabel.text = ""
			mouse_menu.visible = true
			active_mouse_menu = mouse_menu
			_focus_account_prof(account_prof)

func _focus_account_prof(account_prof):
	if active_mouse_menu and active_mouse_menu.visible:
		var tween = get_tree().create_tween()
		tween.tween_property(account_prof, "scale", Vector2(1.1, 1.1), 0.2)

func _reset_account_prof_scale(account_prof):
	if account_prof:
		var tween = get_tree().create_tween()
		tween.tween_property(account_prof, "scale", Vector2(1, 1), 0.2)
		
func _riot_kill():
	print("executado task")
	OS.execute("cmd", ["/c", "taskkill", "/IM", "RiotClientServices.exe", "/F"])
	OS.execute("cmd", ["/c", "taskkill", "/IM", "LeagueClient.exe", "/F"])

func _on_account_prof_pressed(account_prof):
	print("Perfil selecionado: ", account_prof.name)
	_riot_configs_move_selected(account_prof.name)


func _riot_configs_delete():

	var env_output = []
	OS.execute("cmd", ["/c", "echo %LOCALAPPDATA%"], env_output)
	var root_folder = env_output[0].strip_edges()

	var folder_name = "Riot Games"

	var delete_path = "%s\\%s" % [root_folder, folder_name]

	print("Deletando a pasta: ", delete_path)

	var commands = '@echo off && rmdir /S /Q "%s" && exit' % delete_path
	var _result = OS.execute("cmd.exe", ["/c", commands], [], false)

	
func _riot_configs_move(new_account_prof):
	var profile_name = new_account_prof.name

	# Caminho de origem na pasta %LOCALAPPDATA%
	var env_output = []
	OS.execute("cmd", ["/c", "echo %LOCALAPPDATA%"], env_output)
	var root_folder = env_output[0].strip_edges()
	var source_path = "%s\\Riot Games" % root_folder

	# Caminho de destino na pasta profiles do programa
	var destination_path = "profiles\\FOLDER_%s\\Riot Games" % profile_name

	print("Copiando de:", source_path)
	print("Para:", destination_path)

	# Comando para copiar a pasta
	var commands = '@echo off && xcopy "%s" "%s" /E /I /Y && exit' % [source_path, destination_path]
	print("Comando a ser executado:", commands)

	# Captura a saída e o código de retorno do comando
	var output = []
	var result = OS.execute("cmd.exe", ["/c", commands], output, true)

	# Imprime o código de retorno e a saída para depuração
	print("Código de retorno:", result)
	for line in output:
		print("Saída do comando:", line)

	if result == 0:
		print("Pasta copiada com sucesso:", profile_name)
		# Após a cópia, tenta deletar a pasta de origem
		var delete_command = 'rmdir /S /Q "%s"' % source_path
		OS.execute("cmd.exe", ["/c", delete_command], output, true)
		print("Pasta de origem deletada após a cópia.")
	else:
		print("Falha ao copiar a pasta:", profile_name)
		print("Erro ao executar o comando, verifique se há permissões suficientes ou se a pasta está sendo usada.")



func _riot_configs_move_selected(new_profile_name: String):
	# Certifique-se de que new_profile_name seja uma string e não um objeto
	var profile_name = str(new_profile_name)  # Converte explicitamente para string

	# Caminho de origem na pasta profiles do programa
	var source_path = "profiles\\FOLDER_%s\\Riot Games" % profile_name

	# Verificar se a pasta de origem existe
	var source_dir = DirAccess.open(source_path)
	if source_dir == null:
		print("Erro: A pasta de origem não existe:", source_path)
		return
	else:
		source_dir.list_dir_end()  # Fechar o diretório

	# Caminho de destino na pasta %LOCALAPPDATA%
	var env_output = []
	OS.execute("cmd", ["/c", "echo %LOCALAPPDATA%"], env_output)
	var root_folder = env_output[0].strip_edges()
	var destination_path = "%s\\Riot Games" % root_folder

	print("Copiando de:", source_path)
	print("Para:", destination_path)

	# Primeiro, tenta deletar a pasta existente no %LOCALAPPDATA%
	var delete_command = 'rmdir /S /Q "%s"' % destination_path
	var delete_output = []
	var delete_result = OS.execute("cmd.exe", ["/c", delete_command], delete_output, true)

	print("Código de retorno da exclusão:", delete_result)
	for line in delete_output:
		print("Saída do comando de exclusão:", line)

	# Se a exclusão falhar, verificar se a pasta existe antes de copiar
	if delete_result != 0:
		print("Falha ao deletar a pasta existente ou a pasta já não existia:", destination_path)

	# Em seguida, copia a nova pasta do perfil selecionado para o %LOCALAPPDATA%
	var copy_command = '@echo off && xcopy "%s" "%s" /E /I /Y && exit' % [source_path, destination_path]
	var copy_output = []
	var copy_result = OS.execute("cmd.exe", ["/c", copy_command], copy_output, true)

	print("Código de retorno da cópia:", copy_result)
	for line in copy_output:
		print("Saída do comando de cópia:", line)

	if copy_result == 0:
		print("Pasta copiada com sucesso:", profile_name)
	else:
		print("Falha ao copiar a pasta:", profile_name)
		print("Erro ao executar o comando, verifique se há permissões suficientes ou se a pasta está sendo usada.")




func _account_folder_rename(old_name: String, new_name: String):
	
	var root_folder = "profiles"
	var old_folder_name = "FOLDER_" + old_name
	var new_folder_name = "FOLDER_" + new_name
	

	var commands = 'rename "%s\\%s" "%s"' % [root_folder, old_folder_name, new_folder_name]
	

	var result = OS.execute("cmd.exe", ["/c", commands])
	
	if result == 0:
		print("Pasta renomeada com sucesso.")
		

		var config_data = _load_config_file()
		if config_data != null and "profiles" in config_data:
			for profile in config_data["profiles"]:
				if profile["name"] == old_name:
					profile["files_location"] = "res://%s/%s" % [root_folder, new_folder_name]
					profile["image_path"] = "res://%s/%s/default_icon.png" % [root_folder, new_folder_name]
					profile["name"] = new_name
					break
			_save_config_file(config_data)
		else:
			print("Erro ao carregar o arquivo de configuração.")
	else:
		print("Falha ao renomear a pasta.")
	
func _account_folder_created(account_prof):
	
	var root_folder = "profiles"
	var folder_name = "FOLDER_" + account_prof.name
	
	var full_path = "%s\\%s" % [root_folder, folder_name]
	var commands = '@echo off && mkdir "%s" && exit' % full_path
	
	var _result = OS.execute("cmd.exe", ["/c", commands], [], false)
	
func _delete_folder_account_prof(account_prof):
	if account_prof == null or not is_instance_valid(account_prof):
		print("O objeto já foi liberado ou é inválido.")
		return
	
	var folder_name = "FOLDER_" + account_prof.name
	print("Nome da pasta a ser deletada: ", folder_name)

	var root_folder = "profiles"
	var full_path = "%s\\%s" % [root_folder, folder_name]
	var commands = '@echo off && rmdir /S /Q "%s" && exit' % full_path

	var _result = OS.execute("cmd.exe", ["/c", commands], [], false)

	if _result == 0:
		print("Pasta deletada com sucesso: ", folder_name)
	else:
		print("Falha ao deletar a pasta: ", folder_name)
	
	

func _load_config_file() -> Dictionary:
	var config_file_path = "res://config.json"
	if FileAccess.file_exists(config_file_path):
		var file = FileAccess.open(config_file_path, FileAccess.READ)
		var config_data = JSON.parse_string(file.get_as_text())
		file.close()
		if config_data != null and config_data is Dictionary:
			return config_data
	return {}

func _save_config_file(config_data: Dictionary):
	var file = FileAccess.open(config_file_path, FileAccess.WRITE)
	var json_string = JSON.stringify(config_data, "\t")
	file.store_string(json_string)
	file.close()

func _on_delete_button_pressed(account_prof):
	print("Botão delete pressionado para: ", account_prof.name)
	_delete_account_prof(account_prof)
	

func _on_edit_button_pressed(account_prof):
	print("Botão editar pressionado para: ", account_prof.name)
	_show_createmenu(account_prof)

func _show_createmenu(account_prof):
	createmenu.visible = true
	
	var profile_name = _get_profile_name_from_json(account_prof.name)
	if profile_name != null:
		profile_name_lineedit.text = profile_name

	var image_path = _get_image_path_from_json(account_prof.name)
	if image_path != "":
		var new_texture = load(image_path)
		if new_texture != null:
			createmenu_picture.texture_normal = new_texture

	var callable = Callable(self, "_on_create_button_pressed").bind(account_prof)
	
	if not create_button.is_connected("pressed", callable):
		create_button.connect("pressed", callable)


func _get_image_path_from_json(profile_name):
	var config_data = _load_config_file()

	if config_data != null and "profiles" in config_data:
		for profile in config_data["profiles"]:
			if profile.has("name") and profile["name"] == profile_name:
				return profile["image_path"]
	return ""

func _get_profile_name_from_json(profile_name):
	var config_data = _load_config_file()

	if config_data != null and "profiles" in config_data:
		for profile in config_data["profiles"]:
			if profile.has("name") and profile["name"] == profile_name:
				return profile["name"]
	return null
	
func _delete_account_prof(account_prof):
	
	_delete_folder_account_prof(account_prof)
	accounts_container.remove_child(account_prof)
	account_prof_list.erase(account_prof)
	account_prof.queue_free()

	var config_data = _load_config_file()
	if config_data != null and "profiles" in config_data:
		config_data["profiles"] = config_data["profiles"].filter(func(profile) -> bool:
			return profile["name"] != account_prof.name
		)
		_save_config_file(config_data)

	_reset_account_prof_scale(account_prof)
	active_mouse_menu = null

func _hide_all_mouse_menus():
	for account_prof in account_prof_list:
		var mouse_menu = account_prof.get_node("mouse_menu")
		if mouse_menu:
			mouse_menu.visible = false
	_reset_account_prof_scale(active_mouse_menu.get_parent())
	active_mouse_menu = null

func _rename_account_profs():
	for i in range(account_prof_list.size()):
		var account_prof = account_prof_list[i]
		var expected_name = "account_prof_" + str(i)
		if account_prof.name != expected_name:
			account_prof.name = expected_name

func _set_texture_for_account_prof(account_prof, image_path):
	var texture_rect = account_prof.get_node("Panel/TextureRect")
	if texture_rect:
		var new_texture = load(image_path)
		if new_texture != null:
			texture_rect.texture = new_texture
		else:
			print("Falha ao carregar a nova textura de:", image_path)
	else:
		print("TextureRect não encontrado no account_prof:", account_prof.name)

func _save_account_prof_to_json(profile_name, image_path):
	var config_data = _load_config_file()
	
	if config_data == null:
		config_data = {}
	if "profiles" not in config_data or config_data["profiles"] == null:
		config_data["profiles"] = []

	var new_profile = {
		"name": profile_name,
		"image_path": image_path,
		"files_location": "res://profiles/FOLDER_" + profile_name
	}

	config_data["profiles"].append(new_profile)
	_save_config_file(config_data)
	

func _load_account_prof_from_json(account_prof):
	var config_data = _load_config_file()

	if config_data != null and "profiles" in config_data and config_data["profiles"] != null:
		var profiles = config_data["profiles"]
		if profiles is Array:
			for profile in profiles:
				if profile != null and profile.has("name") and profile["name"] == account_prof.name:
					_set_texture_for_account_prof(account_prof, profile["image_path"])
					account_prof.name = profile["name"]
					break
	else:
		print("Nenhum perfil encontrado para:", account_prof.name)


func _load_existing_profiles():
	var config_data = _load_config_file()

	if config_data != null and "profiles" in config_data and config_data["profiles"] != null:
		var profiles = config_data["profiles"]
		if profiles is Array:
			for profile in profiles:
				var new_account_prof = account_prof_scene.instantiate()

				new_account_prof.name = profile["name"]
				accounts_container.add_child(new_account_prof)
				_load_account_prof_from_json(new_account_prof)
				account_prof_list.append(new_account_prof)

				_setup_mouse_menu(new_account_prof)
				_animate_account_prof(new_account_prof)
			
				new_account_prof.connect("pressed", Callable(self, "_on_account_prof_pressed").bind(new_account_prof))

	else:
		print("Nenhum perfil existente encontrado no config.json.")

	_move_add_prof_to_end()

func _move_add_prof_to_end():
	accounts_container.move_child(add_prof, accounts_container.get_child_count() - 1)

func _animate_account_prof(_account_prof):
	pass

func _on_create_button_pressed(account_prof):
	var new_profile_name = profile_name_lineedit.text.strip_edges()
	if new_profile_name == "":
		print("O nome do perfil não pode estar vazio!")
		return

	var old_profile_name = account_prof.name
	
	_account_folder_rename(old_profile_name, new_profile_name)
	
	account_prof.name = new_profile_name
	_rename_account_profs()

	print("Nome do perfil atualizado de '%s' para '%s'." % [old_profile_name, new_profile_name])

	createmenu.visible = false
	get_tree().reload_current_scene()
