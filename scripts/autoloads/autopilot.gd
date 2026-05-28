extends Node
## Autopilot — scripted boot/menu driver for the sanity-check harness.
##
## INERT in normal play. Activates only when launched with the env var
## PSZ_AUTOPILOT=1 (set by scripts/tools/autoplay/sanity_check.sh). When active
## it watches scene transitions and injects synthetic input to walk the
## first-run flow, printing `[sanity] …` checkpoints to stdout so the
## orchestrator can assert pass/fail from the log, then quits on the terminal
## checkpoint.
##
## Extending: add a branch in _drive_scene() for the next scene (e.g.
## character select / create) that injects the inputs to advance and logs a
## checkpoint. Keep checkpoints as stable `[sanity] …` strings — the
## orchestrator greps for them.

const INPUT_SELECT := "res://scenes/2d/input_select.tscn"
const TERMINAL_SCENE := "res://scenes/2d/title.tscn"
const STEP_DELAY := 0.8   # let a scene settle (slide-in / fade tweens) before acting
const QUIT_GRACE := 0.4

var _enabled := false
var _last_scene := ""
var _acted := {}


func _ready() -> void:
	_enabled = OS.has_environment("PSZ_AUTOPILOT") or ("--autopilot" in OS.get_cmdline_user_args())
	if not _enabled:
		set_process(false)
		return
	print("[sanity] autopilot enabled")
	set_process(true)


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	var path := cs.scene_file_path
	if path == "" or path == _last_scene:
		return
	_last_scene = path
	print("[sanity] scene: %s" % path)
	if _acted.has(path):
		return
	_acted[path] = true
	_drive_scene(path)


func _drive_scene(path: String) -> void:
	match path:
		INPUT_SELECT:
			_after(STEP_DELAY, _pick_keyboard)
		TERMINAL_SCENE:
			print("[sanity] checkpoint: reached title")
			print("[sanity] DONE ok")
			_after(QUIT_GRACE, func() -> void: get_tree().quit(0))


## Controller-config screen: pressing any key picks the keyboard scheme and
## routes on to the title (see input_select._on_detect_event).
func _pick_keyboard() -> void:
	print("[sanity] input_select: injecting keyboard keypress")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ENTER
	ev.keycode = KEY_ENTER
	ev.pressed = true
	Input.parse_input_event(ev)


func _after(seconds: float, cb: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(cb)
