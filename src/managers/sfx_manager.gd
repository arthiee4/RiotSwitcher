class_name SfxManager
extends Node

# Central SFX hub, attached to the `audio` node in Main.
# Uses official League of Legends Client (LCU Hextech UI) sound effects.

const ROLES: Array[StringName] = [
	&"click", &"hover", &"hover_play", &"toggle", &"nav", &"open", &"cancel", &"confirm", &"error",
]
const FALLBACK_ROLE: StringName = &"click"
const BASE_DETUNE := 0.0
const HOVER_COOLDOWN_MSEC := 35

const DEFAULT_STREAMS: Dictionary = {
	&"click": "res://assets/sfx/lol_click_gold.ogg",
	&"hover": "res://assets/sfx/lol_hover_generic.ogg",
	&"hover_play": "res://assets/sfx/lol_hover_gold.ogg",
	&"toggle": "res://assets/sfx/lol_toggle_checkbox.ogg",
	&"nav": "res://assets/sfx/lol_nav_tab.ogg",
	&"open": "res://assets/sfx/lol_open_dropdown.ogg",
	&"cancel": "res://assets/sfx/lol_cancel_close.ogg",
	&"confirm": "res://assets/sfx/lol_confirm_play.ogg",
	&"error": "res://assets/sfx/lol_error_noclick.ogg",
}

const DEFAULT_VOLUMES: Dictionary = {
	&"click": -8.0,
	&"hover": -12.0,
	&"hover_play": -10.0,
	&"toggle": -8.0,
	&"nav": -8.0,
	&"open": -9.0,
	&"cancel": -9.0,
	&"confirm": -7.0,
	&"error": -9.0,
}

static var instance: SfxManager = null

var _players: Dictionary = {}
var _base_pitch: Dictionary = {}
var _last_hover_msec: int = 0


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_players()

	if Engine.is_editor_hint():
		return

	_hook_existing_buttons()
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# Grabs the AudioStreamPlayer nodes created in the scene (or creates missing ones) and remembers their authored pitch.
func _cache_players() -> void:
	for role in ROLES:
		var player := get_node_or_null(String(role)) as AudioStreamPlayer
		if not player:
			player = AudioStreamPlayer.new()
			player.name = String(role)
			var stream_path: String = DEFAULT_STREAMS.get(role, "")
			if not stream_path.is_empty() and ResourceLoader.exists(stream_path):
				player.stream = load(stream_path)
			player.volume_db = float(DEFAULT_VOLUMES.get(role, -8.0))
			add_child(player)
		_players[role] = player
		_base_pitch[role] = player.pitch_scale


static func play(id: StringName, detune: float = BASE_DETUNE) -> void:
	if instance:
		instance._play(id, detune)


static func click() -> void:
	play(&"click")


static func hover() -> void:
	play(&"hover")


static func hover_play() -> void:
	play(&"hover_play")


static func cancel() -> void:
	play(&"cancel")


static func toggle() -> void:
	play(&"toggle")


static func nav() -> void:
	play(&"nav")


static func open() -> void:
	play(&"open")


static func confirm() -> void:
	play(&"confirm")


static func error() -> void:
	play(&"error")


func _play(id: StringName, detune: float) -> void:
	var role: StringName = id if _players.has(id) else FALLBACK_ROLE
	var player: AudioStreamPlayer = _players.get(role)
	if not player or not player.stream:
		return

	var base_pitch: float = _base_pitch.get(role, 1.0)
	if detune > 0.0:
		player.pitch_scale = base_pitch + randf_range(-detune, detune)
	else:
		player.pitch_scale = base_pitch
	player.play()


func _hook_existing_buttons() -> void:
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_register_button(node)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register_button(node)


func _register_button(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	if button.has_meta("_sfx_hooked"):
		return
	button.set_meta("_sfx_hooked", true)

	button.mouse_entered.connect(_on_button_mouse_entered.bind(button))

	if button is OptionButton:
		var option := button as OptionButton
		option.get_popup().about_to_popup.connect(_play_open_sound)
		option.item_selected.connect(_on_option_selected)
		return

	button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_mouse_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return
	if button.has_meta("sfx_silent") and bool(button.get_meta("sfx_silent")):
		return
	if button.has_meta("sfx_no_hover") and bool(button.get_meta("sfx_no_hover")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover_msec < HOVER_COOLDOWN_MSEC:
		return
	_last_hover_msec = now
	if button.has_meta("sfx_hover"):
		play(StringName(str(button.get_meta("sfx_hover"))))
		return
	var cat := _category_for(button)
	if cat == &"confirm":
		play(&"hover_play")
	else:
		play(&"hover")


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if button.has_meta("sfx_silent") and bool(button.get_meta("sfx_silent")):
		return
	play(_category_for(button))


func _play_open_sound() -> void:
	play(&"open")


func _on_option_selected(_index: int) -> void:
	play(&"click")


func _category_for(button: BaseButton) -> StringName:
	if button.has_meta("sfx"):
		return StringName(str(button.get_meta("sfx")))
	if button is CheckButton:
		return &"toggle"
	return &"click"
