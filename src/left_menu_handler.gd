extends Control

# Signals emitted when a menu item is selected
signal home_selected
signal settings_selected
signal add_profile_selected

#region Node References (Assumes script is attached to leftmenu_side)
@onready var add_prof_button = $add_prof_button/Button
@onready var add_prof_button_panel = $add_prof_button
@onready var add_icon = $add_prof_button/Button/TextureRect
@onready var add_selected_panel = $add_prof_button/selected_panel

@onready var home_button = $home_button/Button
@onready var home_button_panel = $home_button
@onready var home_icon = $home_button/Button/TextureRect
@onready var home_selected_panel = $home_button/selected_panel

@onready var settings_button = $settings_button/Button
@onready var settings_button_panel = $settings_button
@onready var settings_icon = $settings_button/Button/TextureRect
@onready var settings_selected_panel = $settings_button/selected_panel

@onready var icon_highlight = $iconhighlight
@onready var glow_color = $iconhighlight/glow
@onready var glow_panel_color = $iconhighlight/Panel
#endregion

func _ready():
	# Connect button signals internally
	home_button.pressed.connect(_on_home_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	add_prof_button.pressed.connect(_on_add_prof_button_pressed)
	
	# Initialize UI state
	initialize_ui()

func initialize_ui():
	# Set initial state (Home selected)
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	home_selected_panel.visible = true
	
	# Reset icon colors (will be set correctly by _on_home_button_pressed)
	settings_icon.modulate = Color(1, 1, 1, 1)
	add_icon.modulate = Color(1, 1, 1, 1)
	
	# Set initial highlight position and color (Home)
	move_icon_highlight(home_button_panel.position.y) 
	_set_highlight_theme(Color(1, 0, 0, 0.1), Color(1, 0, 0, 1)) # Red theme for Home
	home_icon.modulate = Color(1, 0, 0, 1)


### --- Internal Button Handlers --- ###
func _on_home_button_pressed():
	_update_selected_panel_visuals(home_selected_panel, home_button_panel)
	_set_highlight_theme(Color(1, 0, 0, 0.1), Color(1, 0, 0, 1)) # Red theme
	home_icon.modulate = Color(1, 0, 0, 1)
	emit_signal("home_selected")

func _on_settings_button_pressed():
	_update_selected_panel_visuals(settings_selected_panel, settings_button_panel)
	_set_highlight_theme(Color(214/255.0, 129/255.0, 0, 0.5), Color(214/255.0, 129/255.0, 0, 1)) # Orange theme
	settings_icon.modulate = Color(214/255.0, 129/255.0, 0, 1)
	emit_signal("settings_selected")

func _on_add_prof_button_pressed():
	_update_selected_panel_visuals(add_selected_panel, add_prof_button_panel)
	_set_highlight_theme(Color(0, 0, 1, 0.5), Color(0, 0, 1, 1)) # Blue theme
	add_icon.modulate = Color(0, 0, 1, 1)
	emit_signal("add_profile_selected")

### --- Helper Functions --- ###

# Handles switching the visual selection indicator and moving the highlight.
func _update_selected_panel_visuals(selected_panel: Control, button_panel: Control):
	# Hide all selection indicators first.
	home_selected_panel.visible = false
	settings_selected_panel.visible = false
	add_selected_panel.visible = false
	
	# Reset icon colors.
	settings_icon.modulate = Color(1, 1, 1, 1)
	home_icon.modulate = Color(1, 1, 1, 1)
	add_icon.modulate = Color(1, 1, 1, 1)

	# Show the requested panel and move the highlight.
	selected_panel.visible = true
	move_icon_highlight(button_panel.position.y)
	# Note: Icon color modulation is now handled in the calling function (_on_..._pressed)

# Sets the color theme for the highlight effect.
func _set_highlight_theme(glow: Color, panel: Color):
	glow_color.color = glow
	var stylebox = glow_panel_color.get_theme_stylebox("panel")
	if stylebox is StyleBoxFlat: # Check type for safety
		stylebox.bg_color = panel
	else:
		printerr("Could not set highlight panel color - StyleBox is not StyleBoxFlat or not found.")

# Animates the highlight bar on the left menu.
func move_icon_highlight(target_y: float):
	# Assuming the highlight's parent is the leftmenu_side node itself.
	# Adjust the offset (e.g., +9) if needed based on your scene layout.
	var tween = create_tween().set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(icon_highlight, "position:y", target_y + 9, 0.1)

# Public function to programmatically select the home button (e.g., after creating a profile)
func select_home():
	_on_home_button_pressed() 