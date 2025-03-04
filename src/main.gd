extends Control

### --- Node References --- ###

# Info Menu Side
@onready var infomenu_side = $infomenu_side
@onready var infomenu_side_anim = $infomenu_side/infomenu_side_anim

# Content Side
@onready var profiles_grid = $contet_side/GridContainer
const add_profile_button = preload("res://scenes/components/profile_button.tscn")

# Left Menu Side
@onready var add_prof_button = $leftmenu_side/add_prof_button/Button
@onready var add_prof_button_panel = $leftmenu_side/add_prof_button
@onready var add_icon = $leftmenu_side/add_prof_button/Button/TextureRect

@onready var home_button = $leftmenu_side/home_button/Button
@onready var home_button_panel = $leftmenu_side/home_button
@onready var home_icon = $leftmenu_side/home_button/Button/TextureRect

@onready var settings_button = $leftmenu_side/settings_button/Button
@onready var settings_button_panel = $leftmenu_side/settings_button
@onready var settings_icon = $leftmenu_side/settings_button/Button/TextureRect

@onready var icon_highlight = $leftmenu_side/iconhighlight
@onready var glow_color = $leftmenu_side/iconhighlight/glow
@onready var glow_panel_color = $leftmenu_side/iconhighlight/Panel

# Selected Panels
@onready var home_selected_panel = $leftmenu_side/home_button/selected_panel
@onready var settings_selected_panel = $leftmenu_side/settings_button/selected_panel
@onready var add_selected_panel = $leftmenu_side/add_prof_button/selected_panel

# Settings Menu
@onready var settings_menu = $settings_menu
@onready var add_menu = $add_menu

# Add Menu
@onready var backgrounds = $add_menu/bg_select/backgrounds
@onready var preview_background = $add_menu/preview/bgexample3/preview_bg
var background_images = []

# Background Buttons
@onready var bgexample1 = $add_menu/bg_select/backgrounds/bgexample1/Button
@onready var bgexample2 = $add_menu/bg_select/backgrounds/bgexample2/Button
@onready var bgexample3 = $add_menu/bg_select/backgrounds/bgexample3/Button
@onready var bgexample4 = $add_menu/bg_select/backgrounds/bgexample4/Button
@onready var bgexample5 = $add_menu/bg_select/backgrounds/bgexample5/Button
@onready var bgexample6 = $add_menu/bg_select/backgrounds/bgexample6/Button
@onready var bgexample7 = $add_menu/bg_select/backgrounds/bgexample7/Button
@onready var bgexample8 = $add_menu/bg_select/backgrounds/bgexample8/Button
@onready var bgexample9 = $add_menu/bg_select/backgrounds/bgexample9/Button
@onready var bgexample10 = $add_menu/bg_select/backgrounds/bgexample10/Button
@onready var bgexample11 = $add_menu/bg_select/backgrounds/bgexample11/Button
@onready var bgexample12 = $add_menu/bg_select/backgrounds/bgexample12/Button

# Custom Image Upload
@onready var browser_button = $add_menu/upload_custom_bg/browser_button
@onready var filedialog = $add_menu/creation/create_button/FileDialog

# Profile Name on adding
@onready var profile_name = $add_menu/profile_name/LineEdit
@onready var profile_name_preview = $add_menu/preview/preview_profile_name

# Profile name released
@onready var user_profile_name = $contet_side/GridContainer/profile_button/profile_name
@onready var user_profile_background = $contet_side/GridContainer/profile_button/bg1/Panel/profile_bg

# Create Button
@onready var create_button = $add_menu/creation/create_button

### --- Conditions --- ###
var profile_selected = false
var client_is_running = false
var info_side_visible = false

### --- Profile Counter --- ###
var profile_counter: int = 0


### --- Initialization --- ###
func _ready():
	# Load background images and connect buttons dynamically
	load_background_images()
	
	# Connect signals
	connect_signals()
	
	# Initialize UI state
	initialize_ui()
	
	load_profiles()

	load_profile_counter()
func load_profile_counter():
	var json_path = "res://Data/profiles_data.json"
	var json = FileAccess.open(json_path, FileAccess.READ)
	if not json:
		print("Erro: Não foi possível carregar os perfis.")
		return
	
	var json_string = json.get_as_text()
	json.close()
	
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		print("Erro ao interpretar JSON dos perfis.")
		return
	
	var data = json_parser.get_data()
	
	if data.has("profiles"):
		profile_counter = data["profiles"].size()  # Define o contador com base no número de perfis existentes
	else:
		profile_counter = 0  # Se não houver perfis, começa do zero
func load_profiles():
	var json_path = "res://Data/profiles_data.json"
	var json = FileAccess.open(json_path, FileAccess.READ)
	if not json:
		print("Erro: Não foi possível carregar os perfis.")
		return
	
	var json_string = json.get_as_text()
	json.close()
	
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		print("Erro ao interpretar JSON dos perfis.")
		return
	
	var data = json_parser.get_data()
	
	if not data.has("profiles"):
		print("Nenhum perfil encontrado.")
		return
	
	# Itera sobre os perfis no array
	for profile_data in data["profiles"]:
		if profile_data is Dictionary:
			var new_profile = add_profile_button.instantiate()
			profiles_grid.add_child(new_profile)
			
			var profile_name_text = profile_data.get("profile_name", "Perfil Desconhecido")
			new_profile.name = profile_name_text
			
			var profile_label = new_profile.find_child("profile_name", true, false)
			if profile_label:
				profile_label.text = profile_name_text
			
			var texture_rect = new_profile.get_node_or_null("bg1/Panel/profile_bg")
			if texture_rect:
				var image_path = profile_data.get("custom_background_image", "")
				if image_path and FileAccess.file_exists(image_path):
					texture_rect.texture = load(image_path)
				else:
					texture_rect.texture = preload("res://default_profile_image.png")

			print("Perfil carregado:", profile_name_text)

func deploy_test():
	pass
func modify_config_json(path: String, key_path: Array, new_value) -> void:
	var json = FileAccess.open(path, FileAccess.READ)
	if not json:
		print("Erro: Arquivo JSON não encontrado ou não pode ser aberto.")
		return
	
	var json_string = json.get_as_text()
	json.close()
	
	var json_parser = JSON.new()
	if json_parser.parse(json_string) != OK:
		print("Erro ao fazer parse do JSON.")
		return
	
	var data = json_parser.get_data()
	
	if not (data is Dictionary):
		data = {}  # Se o JSON não for um dicionário, cria um novo.

	var current_data = data
	for i in range(key_path.size() - 1):
		var key = key_path[i]

	# Verifica se está no caminho correto para o array de perfis
	if key_path[-1] == "profiles":
		if not current_data.has("profiles"):
			current_data["profiles"] = []  # Cria a chave "profiles" como um array, se não existir.
		current_data["profiles"].append(new_value)

	var modified_json_string = JSON.stringify(data, "\t")
	var save_file = FileAccess.open(path, FileAccess.WRITE)
	if save_file:
		save_file.store_string(modified_json_string)
		save_file.close()
		print("JSON modificado e salvo com sucesso.")
	else:
		print("Erro ao salvar o JSON.")


				
### --- Background Image Loading --- ###
func load_background_images():
	for i in range(1, 13):
		var image_path = "res://assets/backgrounds/profiles_bg/{0}.png".format([i])
		var image = load(image_path)
		if image:
			background_images.append(image)
		
		var button = get_node("add_menu/bg_select/backgrounds/bgexample{0}/Button".format([i]))
		if button:
			button.pressed.connect(on_button_pressed.bind(i - 1))  # Index starts at 0
			
func load_custom_background(image_path: String):
	var image = Image.load_from_file(image_path)
	if image:
		var texture = ImageTexture.create_from_image(image)
		preview_background.texture = texture
		
		print("Custom background loaded and displayed in preview.")
	else:
		print("Failed to load custom background image.")

### --- Signal Connections --- ###
func connect_signals():
	profile_name.text_changed.connect(update_profile_name_preview)
	filedialog.filters = ["*.png, *.jpg ; PNG and JPG Files"]
	filedialog.file_selected.connect(_on_file_selected)
	browser_button.pressed.connect(_on_browser_button_pressed)
	create_button.pressed.connect(_on_create_button_pressed)
	add_prof_button.pressed.connect(_on_add_prof_button_pressed)

### --- UI Initialization --- ###
func initialize_ui():
	# Initially, all selected panels are hidden
	glow_color.color = Color(1, 0, 0, 0.1)
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	home_selected_panel.visible = true  # Default value
	
	# Set the initial position of the icon highlight to the home button
	move_icon_highlight(home_button_panel.position.y)

### --- Profile Creation --- ###
func _on_create_button_pressed():
	var profile_name_text = profile_name.text.strip_edges()
	var background_texture = preview_background.texture

	if profile_name_text.is_empty():
		print("Erro: Nome do perfil não pode estar vazio.")
		return

	if not background_texture:
		print("Erro: Selecione uma imagem de fundo.")
		return

	# Gera o ID único usando o nome do perfil
	var profile_id = generate_unique_id()

	# Caminho da imagem de fundo (custom ou padrão)
	var background_path = ""
	if background_texture.resource_path:  # Se for uma imagem customizada
		background_path = background_texture.resource_path
	else:  # Se for uma imagem padrão
		background_path = "res://assets/backgrounds/profiles_bg/default.png"  # Defina um caminho padrão

	# Criação direta do perfil
	var new_profile = add_profile_button.instantiate()
	profiles_grid.add_child(new_profile)
	new_profile.name = profile_name_text
	new_profile.visible = true

	# Atualiza o nome do perfil
	var profile_label = new_profile.find_child("profile_name", true, false)
	if profile_label:
		profile_label.text = profile_name_text

	# Atualiza a imagem de fundo
	var texture_rect = new_profile.get_node_or_null("bg1/Panel/profile_bg")
	if texture_rect:
		texture_rect.texture = background_texture

	# Dados do novo perfil
	var new_profile_data = {
		"profile_name": profile_name_text,
		"custom_background_image": background_path
	}

	# Adiciona o novo perfil ao JSON
	modify_config_json("res://Data/profiles_data.json", ["profiles"], new_profile_data)

	# Limpa os campos do formulário
	profile_name.text = ""
	preview_background.texture = null

	# Volta para o menu home
	_on_home_button_pressed()
	print_profiles()


### --- File Dialog Handling --- ###
func _on_browser_button_pressed():
	filedialog.popup_centered()
func _on_file_selected(path):
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var file_content = file.get_buffer(file.get_length())
		file.close()
		
		var file_name = path.get_file()  # Obtém o nome do arquivo salvo
		print(file_name)
		
		var destination_path = "res://Data/UserBackground/" + file_name
		var destination_file = FileAccess.open(destination_path, FileAccess.WRITE)
		if destination_file:
			destination_file.store_buffer(file_content)
			destination_file.close()
			
			# Atualiza a imagem de fundo do perfil atual
			preview_background.texture = load(destination_path)
			
			# Salva o caminho da imagem no JSON, associado ao nome do perfil
			var profile_id = generate_unique_id()  # Usa o nome do perfil como ID
			modify_config_json("res://Data/profiles_data.json", ["profiles", profile_id, "custom_background_image"], destination_path)
			
			print("Arquivo salvo com sucesso e associado ao perfil:", profile_id)
		else:
			print("Erro ao salvar o arquivo.")
	else:
		print("Erro ao ler o arquivo.")

### --- Profile Name Update --- ###
func update_profile_name_preview(user_input: String):
	profile_name_preview.text = user_input


func on_button_pressed(i: int):
	if i >= 0 and i < background_images.size():
		preview_background.texture = background_images[i]
		

### --- Selected Panel Management --- ###
func update_selected_panel(selected_panel: Control, button_panel: Control):
	home_selected_panel.visible = false
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	
	settings_menu.visible = false
	add_menu.visible = false
	
	settings_icon.modulate = Color(1, 1, 1, 1)
	home_icon.modulate = Color(1, 1, 1, 1)
	add_icon.modulate = Color(1, 1, 1, 1)
	
	selected_panel.visible = true
	move_icon_highlight(button_panel.position.y)
	
	if selected_panel == settings_selected_panel:
		settings_menu.visible = true
	if selected_panel == add_selected_panel:
		add_menu.visible = true

### --- Icon Highlight Movement --- ###
func move_icon_highlight(target_y: float):
	var tween = create_tween()
	tween.tween_property(icon_highlight, "position:y", target_y + 9, 0.1)
	tween.set_ease(Tween.EASE_OUT_IN)

### --- Button Handlers --- ###
func _on_home_button_pressed():
	update_selected_panel(home_selected_panel, home_button_panel)
	glow_color.color = Color(1, 0, 0, 0.1)
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 0, 0, 1)
	home_icon.modulate = Color(1, 0, 0, 1)

func _on_settings_button_pressed():
	update_selected_panel(settings_selected_panel, settings_button_panel)
	glow_color.color = Color(214, 129, 0, 0.5)
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(214, 129, 0, 1)
	settings_icon.modulate = Color(214, 129, 0, 1)
	
func _on_add_prof_button_pressed():
	update_selected_panel(add_selected_panel, add_prof_button_panel)
	glow_color.color = Color(0, 0, 1, 1)
	var styleboxss = glow_panel_color.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(0, 0, 1, 1)
	add_icon.modulate = Color(0, 0, 1, 1)
	

### --- Profile List Printing --- ###
func print_profiles():
	print("Current Profiles:")
	for profile in profiles_grid.get_children():
		print(profile.name)

### --- Button Hover Effects --- ###
func _on_settings_button_mouse_entered():
	var styleboxss = settings_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.2)

func _on_settings_button_mouse_exited():
	var styleboxss = settings_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.0)

func _on_add_button_mouse_entered():
	var styleboxss = add_prof_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.2)

func _on_add_button_mouse_exited():
	var styleboxss = add_prof_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.0)

func _on_home_button_mouse_entered():
	var styleboxss = home_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.2)

func _on_home_button_mouse_exited():
	var styleboxss = home_button_panel.get_theme_stylebox("panel")
	styleboxss.bg_color = Color(1, 1, 1, 0.0)
func generate_unique_id() -> String:
	return profile_name_preview.text
