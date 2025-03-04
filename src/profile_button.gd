extends Control

@onready var glow_effect = $bg1/bg2/glow

##profile_button
@onready var profile_button = $bg1/bg2/Button
@onready var profile_button_icon_state = $bg1/bg2/Button/TextureRect

@onready var bg1_button = $bg1

@onready var stop_icon = preload("res://assets/user_icons/stop.png")
@onready var play_icon = preload("res://assets/user_icons/play.png")

var client_is_running = false

#hover style
func _on_bg_1_mouse_entered() -> void:
	var tween = create_tween()
	tween.tween_property(glow_effect, "modulate", Color(1, 1, 1, 0.4), 0.060)  # Tempo reduzido para 0.1 segundos
func _on_bg_1_mouse_exited() -> void:
	var tween = create_tween()
	tween.tween_property(glow_effect, "modulate", Color(1, 1, 1, 0.0), 0.060)  # Tempo reduzido para 0.1 segundos

##button functions here
func _on_profile_button_pressed() -> void:
	client_is_running = !client_is_running
	
	##client running sequence here
	if client_is_running:
		profile_button_icon_state.texture = stop_icon
		print("starting client...")
		
	##client stopping sequence here
	else:
		profile_button_icon_state.texture = play_icon
		print("stopping client...")
