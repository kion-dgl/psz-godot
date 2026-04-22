extends Node
## InputConfig — stores the active control scheme and persists to user://input_config.json.
## Control schemes: "keyboard", "xinput", "switch", "ds_cross", "ds_circle".
## The three controller schemes all use identical button indices; they differ only in
## which face button is accept vs cancel (Nintendo swaps A↔B relative to Xbox; the two
## DualSense schemes let the player pick Cross or Circle as accept). Icon-glyph display
## will eventually key off the scheme name to show the right label set.

signal scheme_changed(new_scheme: String)

const SAVE_PATH := "user://input_config.json"

const SCHEMES := ["keyboard", "xinput", "switch", "ds_cross", "ds_circle"]
const SCHEME_LABELS := {
	"keyboard": "Keyboard",
	"xinput": "Xbox / X-Input",
	"switch": "Switch / Nintendo",
	"ds_cross": "DualSense (Cross accept)",
	"ds_circle": "DualSense (Circle accept)",
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


func accept_on_east() -> bool:
	# Schemes where the east face button is "accept" (physical A on Switch, Circle on
	# Japanese/PSZ-style DualSense). For xinput and ds_cross, accept is south.
	return current_scheme == "switch" or current_scheme == "ds_circle"


func _apply_button_mapping() -> void:
	## Remap joypad face buttons based on scheme. All controller families share the
	## same SDL button indices (0=south, 1=east, 2=west, 3=north); only accept/cancel
	## placement varies.
	if accept_on_east():
		_set_joypad_button(ACCEPT_ACTIONS, XBOX_B)   # east = index 1
		_set_joypad_button(CANCEL_ACTIONS, XBOX_A)   # south = index 0
		# Palette uses the three non-accept face buttons: west + south + east
		_set_joypad_button(X_ACTIONS, XBOX_X)        # action_1 → west
		_set_joypad_button(Y_ACTIONS, XBOX_A)        # action_2 → south
		_set_joypad_button(B_ACTIONS, XBOX_B)        # action_3 → east
	else:
		_set_joypad_button(ACCEPT_ACTIONS, XBOX_A)   # south = index 0
		_set_joypad_button(CANCEL_ACTIONS, XBOX_B)   # east = index 1
		# Palette uses the three non-accept face buttons: west + north + east
		_set_joypad_button(X_ACTIONS, XBOX_X)        # action_1 → west
		_set_joypad_button(Y_ACTIONS, XBOX_Y)        # action_2 → north
		_set_joypad_button(B_ACTIONS, XBOX_B)        # action_3 → east


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
	# Read-merge-write so a scheme change never clobbers user-authored fields
	# (preset, keyboard remaps). Fixes #128.
	var data: Dictionary = {}
	if FileAccess.file_exists(SAVE_PATH):
		var in_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if in_file:
			var parsed: Variant = JSON.parse_string(in_file.get_as_text())
			if parsed is Dictionary:
				data = parsed
	data["scheme"] = current_scheme
	var out_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if out_file:
		out_file.store_string(JSON.stringify(data))


func has_saved_config() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func set_scheme(scheme: String) -> void:
	if not scheme in SCHEMES:
		return
	current_scheme = scheme
	_apply_button_mapping()
	scheme_changed.emit(current_scheme)
	_save()


## Map of web key names to Godot physical keycodes
const KEY_MAP := {
	"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D,
	"E": KEY_E, "I": KEY_I, "J": KEY_J, "K": KEY_K, "L": KEY_L, "Q": KEY_Q,
	"ArrowUp": KEY_UP, "ArrowDown": KEY_DOWN, "ArrowLeft": KEY_LEFT, "ArrowRight": KEY_RIGHT,
	"Escape": KEY_ESCAPE, "Enter": KEY_ENTER, "Space": KEY_SPACE,
	"Backspace": KEY_BACKSPACE, "Tab": KEY_TAB, "Home": KEY_HOME, "End": KEY_END,
	"ShiftLeft": KEY_SHIFT, "ControlLeft": KEY_CTRL, "Delete": KEY_DELETE,
	"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4, "F5": KEY_F5,
	"F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8, "F9": KEY_F9, "F10": KEY_F10,
	"F11": KEY_F11, "F12": KEY_F12,
}

## Map of config key names to Godot action names
const ACTION_MAP := {
	"move_forward": "move_forward", "move_backward": "move_backward",
	"move_left": "move_left", "move_right": "move_right",
	"camera_left": "camera_left", "camera_right": "camera_right",
	"menu_toggle": "pause", "cancel": "ui_cancel", "accept": "ui_accept",
	"interact": "interact", "palette_swap": "palette_swap", "quick_weapon": "quick_weapon",
	"palette_1": "action_1", "palette_2": "action_2", "palette_3": "action_3",
}


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return

	# Legacy format: just scheme name
	if parsed.has("scheme"):
		var s: String = str(parsed["scheme"])
		if s in SCHEMES:
			current_scheme = s

	# Extended format: preset + keyboard remaps
	if parsed.has("preset") and parsed.has("keyboard"):
		var preset: String = str(parsed.get("preset", "modern"))
		print("[InputConfig] Loading preset: %s" % preset)
		var kb: Dictionary = parsed.get("keyboard", {})
		_apply_keyboard_config(kb)


func _apply_keyboard_config(kb: Dictionary) -> void:
	## Remap keyboard actions based on config JSON.
	for config_key in kb:
		var action_name: String = ACTION_MAP.get(str(config_key), "")
		if action_name.is_empty():
			continue
		var key_name: String = str(kb[config_key])
		var keycode: int = KEY_MAP.get(key_name, 0)
		if keycode == 0:
			print("[InputConfig] Unknown key: %s" % key_name)
			continue
		if not InputMap.has_action(action_name):
			continue
		# Remove existing keyboard events for this action
		var events := InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventKey:
				InputMap.action_erase_event(action_name, event)
		# Add new key
		var new_event := InputEventKey.new()
		new_event.physical_keycode = keycode
		new_event.device = -1
		InputMap.action_add_event(action_name, new_event)
		print("[InputConfig] Remapped %s → %s (%s)" % [action_name, key_name, keycode])
