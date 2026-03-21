extends Node
## InputConfig — stores the active control scheme and persists to user://input_config.json.
## Control schemes: "keyboard", "kb_mouse", "xinput", "switch"
## When "switch" is selected, swaps A↔B and X↔Y joypad buttons in the InputMap
## to match Nintendo physical layout (A=right, B=bottom vs Xbox A=bottom, B=right).

signal scheme_changed(new_scheme: String)

const SAVE_PATH := "user://input_config.json"

const SCHEMES := ["keyboard", "kb_mouse", "xinput", "switch"]
const SCHEME_LABELS := {
	"keyboard": "Keyboard",
	"kb_mouse": "KB + Mouse",
	"xinput": "Xbox / X-Input",
	"switch": "Switch / Nintendo",
}

## Actions that use face button A (Xbox=0, Switch=1) for confirm/interact
const ACCEPT_ACTIONS := ["ui_accept", "interact"]
## Actions that use face button B (Xbox=1, Switch=0) for cancel/back
const CANCEL_ACTIONS := ["ui_cancel"]
## Actions mapped to X button (Xbox=2, Switch=3)
const X_ACTIONS := ["action_1"]
## Actions mapped to Y button (Xbox=3, Switch=2)
const Y_ACTIONS := ["action_2"]
## Actions mapped to B button (Xbox=1, Switch=0) — same as cancel
const B_ACTIONS := ["action_3"]

## Xbox-standard button indices
const XBOX_A := 0
const XBOX_B := 1
const XBOX_X := 2
const XBOX_Y := 3

var current_scheme: String = "keyboard"


func _ready() -> void:
	_load()
	_apply_button_mapping()


func cycle(direction: int) -> void:
	var idx := SCHEMES.find(current_scheme)
	if idx == -1:
		idx = 0
	idx = (idx + direction + SCHEMES.size()) % SCHEMES.size()
	current_scheme = SCHEMES[idx]
	_apply_button_mapping()
	scheme_changed.emit(current_scheme)
	_save()


func get_label() -> String:
	return SCHEME_LABELS.get(current_scheme, current_scheme)


func is_switch() -> bool:
	return current_scheme == "switch"


func _apply_button_mapping() -> void:
	## Remap joypad face buttons based on scheme.
	## Switch layout: physical A is at button index 1, physical B at index 0.
	if current_scheme == "switch":
		_set_joypad_button(ACCEPT_ACTIONS, XBOX_B)   # Physical A on Switch = index 1
		_set_joypad_button(CANCEL_ACTIONS, XBOX_A)    # Physical B on Switch = index 0
		# Palette: same physical positions as Xbox, different labels
		# Left face (Y on Switch) = index 2, Bottom (B) = index 0, Right (A) = index 1
		_set_joypad_button(X_ACTIONS, XBOX_X)         # action_1 → index 2 = Switch Y
		_set_joypad_button(Y_ACTIONS, XBOX_A)         # action_2 → index 0 = Switch B
		_set_joypad_button(B_ACTIONS, XBOX_B)         # action_3 → index 1 = Switch A
	else:
		_set_joypad_button(ACCEPT_ACTIONS, XBOX_A)    # Standard Xbox layout
		_set_joypad_button(CANCEL_ACTIONS, XBOX_B)
		_set_joypad_button(B_ACTIONS, XBOX_B)
		_set_joypad_button(X_ACTIONS, XBOX_X)
		_set_joypad_button(Y_ACTIONS, XBOX_Y)


func _set_joypad_button(actions: Array, button_index: int) -> void:
	for action_name in actions:
		if not InputMap.has_action(action_name):
			continue
		# Find and replace the existing joypad button event
		var events := InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventJoypadButton:
				InputMap.action_erase_event(action_name, event)
		# Add new joypad button
		var new_event := InputEventJoypadButton.new()
		new_event.button_index = button_index
		new_event.device = -1
		InputMap.action_add_event(action_name, new_event)


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"scheme": current_scheme}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("scheme"):
		var s: String = str(parsed["scheme"])
		if s in SCHEMES:
			current_scheme = s
