extends Control

@onready var browser_button := $browserbutton
@onready var filedialog := $FileDialog
@onready var errorlabel_text := $errorlabel
@onready var closebutton = $closebutton
@onready var minimizebutton = $minimizebutton

@export var timedelay = 2

var config = {
	"launcher_settings": {
		"launcher_lang": "",
		"riotlocation": " ",
		}
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
		# Converte manualmente Vector2i para Vector2
		var window_position = Vector2(DisplayServer.window_get_position().x, DisplayServer.window_get_position().y)
		var new_position = window_position + event.position - drag_offset
		DisplayServer.window_set_position(new_position)

func _ready():
	DisplayServer.window_set_title("xxx")
	errorlabel_text.visible = false
	
	# Verifica se o arquivo JSON já existe
	if FileAccess.file_exists("res://config.json"):
		# Se o arquivo existe, muda diretamente para a cena principal
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		# Caso contrário, continue com a configuração inicial
		filedialog.current_dir = "C:/"
		filedialog.connect("dir_selected", _on_filedialog_dir_selected)
		browser_button.pressed.connect(_on_browser_button_pressed)
		closebutton.pressed.connect(_on_closebutton_pressed)
		minimizebutton.pressed.connect(_on_minimizebutton_pressed)

func _on_closebutton_pressed():
	get_tree().quit()

func _on_minimizebutton_pressed():
	get_tree().root.mode = Window.MODE_MINIMIZED

func _process(_delta):
	pass
	
func _on_browser_button_pressed():
	filedialog.popup()
	
func _on_filedialog_dir_selected(dir_path):
	# Atualiza o riotlocation com o caminho selecionado
	config["launcher_settings"]["riotlocation"] = dir_path

	var json_string = JSON.stringify(config, "\t")
	if dir_path.ends_with("Riot Client/") or dir_path.ends_with("Riot Client"):
		var config_file = FileAccess.open("res://config.json", FileAccess.WRITE)
		config_file.store_string(json_string)
		config_file.close()

		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		errorlabel_text.visible = true
