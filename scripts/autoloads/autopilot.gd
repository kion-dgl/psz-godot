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
const TITLE := "res://scenes/2d/title.tscn"
const CHAR_SELECT := "res://scenes/2d/character_select.tscn"
const CHAR_CREATE := "res://scenes/2d/character_create.tscn"
const CITY_PREFIX := "res://scenes/3d/city/"   # spawn after create (city_office, …)
const STEP_DELAY := 0.8   # let a scene settle (slide-in / fade tweens) before acting
const QUIT_GRACE := 0.4

var _enabled := false
var _last_scene := ""
var _acted := {}
var _cc_acted_step := -1   # character_create: last wizard step we acted on


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
	if path == INPUT_SELECT:
		_after(STEP_DELAY, _pick_keyboard)
	elif path == TITLE:
		print("[sanity] checkpoint: title")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_SELECT:
		print("[sanity] checkpoint: character_select")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_CREATE:
		print("[sanity] checkpoint: character_create")
		_cc_acted_step = -1
		_after(STEP_DELAY, _drive_char_create)
	elif path.begins_with(CITY_PREFIX):
		print("[sanity] checkpoint: reached city (%s)" % path)
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


## Inject a logical action press — works for handlers that check
## event.is_action_pressed (title / character select / create all do).
func _press_action(action: String) -> void:
	print("[sanity] press %s" % action)
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## Walk the character-create wizard by its actual _step (CLASS_SELECT=0,
## APPEARANCE=1, NAME_ENTRY=2): accept the defaults, then set + submit the name,
## which routes straight to the city (_on_name_submitted → _create_character).
## Re-arms until the scene leaves character_create.
func _drive_char_create() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CHAR_CREATE:
		return
	var step: int = int(node.get("_step"))
	if step != _cc_acted_step:
		_cc_acted_step = step
		match step:
			0, 1:  # CLASS_SELECT, APPEARANCE — accept the default
				_press_action("ui_accept")
			2:     # NAME_ENTRY — type the name and submit
				_enter_name(node)
	_after(0.8, _drive_char_create)


const CHAR_NAME := "humar"

func _enter_name(node: Node) -> void:
	var le := _find_line_edit(node)
	if le == null:
		print("[sanity] WARN: no LineEdit found for name entry")
		return
	le.text = CHAR_NAME
	print("[sanity] entering name: %s" % CHAR_NAME)
	le.text_submitted.emit(CHAR_NAME)


func _find_line_edit(n: Node) -> LineEdit:
	if n is LineEdit:
		return n
	for c in n.get_children():
		var found := _find_line_edit(c)
		if found:
			return found
	return null


func _after(seconds: float, cb: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(cb)
