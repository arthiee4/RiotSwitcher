extends Control

@onready var browser_button := $browserbutton
@onready var filedialog := $FileDialog
@onready var errorlabel_text := $errorlabel
@onready var closebutton = $closebutton
@onready var minimizebutton = $minimizebutton

var config_file_path = "res://config.json"  
var selected_language: String = "--locale=en_US"  # Você pode remover essa linha se ela não for mais necessária

@export var timedelay = 2

var config = {
	"launcher_settings": {
		"launcher_lang": "",
		"riotlocation": "",
	},
	"launcher_boot": 0
}

var dragging = false
var drag_offset = Vector2()

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_offset = event.position
		else:
			dragging = false

	if event is InputEventMouseMotion and dragging:
		var window_position = Vector2(DisplayServer.window_get_position().x, DisplayServer.window_get_position().y)
		var new_position = window_position + event.position - drag_offset
		DisplayServer.window_set_position(new_position)
		
func _process(_delta):
	pass

func _ready():
	DisplayServer.window_set_title("xxx")
	errorlabel_text.visible = false
	
	if not FileAccess.file_exists(config_file_path):
		_save_config_file(config)
		print("Arquivo config.json criado com as configurações iniciais.")
	else:
		var config_data = _load_config_file()

		if config_data is Dictionary:
			if "launcher_boot" in config_data and config_data["launcher_boot"] == 1:
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			else:
				_continue_initial_setup()
		else:
			print("Erro: O arquivo config.json não está formatado corretamente.")

func _continue_initial_setup():
	browser_button.pressed.connect(_on_browser_button_pressed)
	filedialog.connect("dir_selected", _on_filedialog_dir_selected)
	
	filedialog.current_dir = "C:/"
	closebutton.pressed.connect(_on_closebutton_pressed)
	minimizebutton.pressed.connect(_on_minimizebutton_pressed)

func _on_closebutton_pressed():
	get_tree().quit()

func _on_minimizebutton_pressed():
	get_tree().root.mode = Window.MODE_MINIMIZED
	
func _on_browser_button_pressed():
	print("Botão pressionado")
	if filedialog:
		filedialog.popup()
	else:
		print("Erro: FileDialog não está configurado corretamente.")
	
func _on_filedialog_dir_selected(dir_path):
	config["launcher_settings"]["riotlocation"] = dir_path

	if dir_path.ends_with("Riot Client/") or dir_path.ends_with("Riot Client"):
		config["launcher_boot"] = 1
		_save_config_file(config)
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		errorlabel_text.visible = true

func _load_config_file() -> Dictionary:
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
