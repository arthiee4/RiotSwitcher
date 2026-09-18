class_name SfxManager
extends Node

## Central SFX hub, attached to the `audio` node in Main.
##
## Every semantic event is an explicit AudioStreamPlayer child of `audio`,
## configured in the scene (stream + pitch_scale + volume_db), so sounds can be
## swapped and balanced from the Inspector without touching code.
##
## Event names: click / toggle / nav / open / cancel / confirm / error.
## The current .wav mapping (see the scene):
##   12_scn1_btn_11 -> click, toggle, confirm
##   40_scn3_btn_2  -> nav, open
##   10_scn1_btn_1  -> cancel, error
##
## Every BaseButton gets a click automatically. To customize:
##   - node.set_meta("sfx", &"cancel")   -> plays that event
##   - node.set_meta("sfx_silent", true) -> no automatic sound
##   - call SfxManager.confirm() etc. manually for non-button events.

const ROLES: Array[StringName] = [
	&"click", &"toggle", &"nav", &"open", &"cancel", &"confirm", &"error",
]
const FALLBACK_ROLE: StringName = &"click"
const BASE_DETUNE := 0.03

static var instance: SfxManager = null

var _players: Dictionary = {}
var _base_pitch: Dictionary = {}


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


## Grabs the AudioStreamPlayer nodes created in the scene and remembers their
## authored pitch so per-play detune never accumulates.
func _cache_players() -> void:
	for role in ROLES:
		var player := get_node_or_null(String(role)) as AudioStreamPlayer
		if player:
			_players[role] = player
			_base_pitch[role] = player.pitch_scale


#region Static API
static func play(id: StringName, detune: float = BASE_DETUNE) -> void:
	if instance:
		instance._play(id, detune)


static func click() -> void:
	play(&"click")


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
#endregion


func _play(id: StringName, detune: float) -> void:
	var role: StringName = id if _players.has(id) else FALLBACK_ROLE
	var player: AudioStreamPlayer = _players.get(role)
	if not player or not player.stream:
		return

	var base_pitch: float = _base_pitch.get(role, 1.0)
	player.pitch_scale = base_pitch + randf_range(-detune, detune)
	player.play()


#region Automatic button hooking
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

	if button is OptionButton:
		var option := button as OptionButton
		option.get_popup().about_to_popup.connect(_play_open_sound)
		option.item_selected.connect(_on_option_selected)
		return

	button.pressed.connect(_on_button_pressed.bind(button))


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
#endregion
