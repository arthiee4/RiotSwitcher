extends Control

@onready var close_button = $x
@onready var minimize_button = $"-"

func _ready() -> void:
	# Connect the buttons to the action methods
	close_button.pressed.connect(_on_close_button_pressed)
	minimize_button.pressed.connect(_on_minimize_button_pressed)

# Function to close the window
func _on_close_button_pressed() -> void:
	get_tree().quit()  # Closes the game

# Function to minimize the window
func _on_minimize_button_pressed() -> void:
	get_tree().root.mode = Window.MODE_MINIMIZED
