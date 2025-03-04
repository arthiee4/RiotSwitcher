extends Control

@onready var close_button = $x
@onready var minimize_button = $"-"

func _ready() -> void:
	# Conectar os botões aos métodos de ação
	close_button.pressed.connect(_on_close_button_pressed)
	minimize_button.pressed.connect(_on_minimize_button_pressed)

# Função para fechar a janela
func _on_close_button_pressed() -> void:
	get_tree().quit()  # Fecha o jogo

# Função para minimizar a janela
func _on_minimize_button_pressed() -> void:
	get_tree().root.mode = Window.MODE_MINIMIZED
