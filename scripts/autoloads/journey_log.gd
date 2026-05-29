extends Node
## JourneyLog — lightweight, always-on instrumentation for capturing a real
## playthrough (e.g. a controller run on the Retroid) into a log the autopilot
## can be built from. Emits stable `[journey] …` lines:
##
##   [journey] scene <res://path>     — on every scene change (the screen sequence)
##   [journey] action <name>          — mapped menu action, 2D front-end screens only
##   [journey] joybtn <index>         — raw face-button press during controller onboarding
##
## Polls the Input singleton (not _input) so it observes every press regardless
## of which node consumed the event. Menu-action logging is limited to 2D screens
## so 3D field/city gameplay isn't spammed; scene logging is global.

const MENU_ACTIONS := [
	"ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right",
	"interact", "action_1", "action_2", "action_3", "quick_weapon",
	"palette_swap", "pause",
]
const INPUT_SELECT := "res://scenes/2d/input_select.tscn"

var _last_scene := ""
var _actions: Array = []          # MENU_ACTIONS filtered to those that exist
var _joy_prev: Dictionary = {}    # button_index -> down, for edge detection


func _ready() -> void:
	for a in MENU_ACTIONS:
		if InputMap.has_action(a):
			_actions.append(a)


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	var path := cs.scene_file_path

	if path != "" and path != _last_scene:
		_last_scene = path
		print("[journey] scene %s" % path)

	if path == INPUT_SELECT:
		# Onboarding maps raw buttons before actions exist — log press edges so
		# we capture which indices this controller emits for each face.
		for b in range(JOY_BUTTON_MAX):
			var down: bool = Input.is_joy_button_pressed(0, b)
			if down and not bool(_joy_prev.get(b, false)):
				print("[journey] joybtn %d" % b)
			_joy_prev[b] = down
		return

	if path.contains("/2d/"):
		for a in _actions:
			if Input.is_action_just_pressed(a):
				print("[journey] action %s" % a)
