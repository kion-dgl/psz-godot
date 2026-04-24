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

## Face button actions, named by logical role. Accept/cancel flip between
## south and east depending on scheme; palette slots are scheme-independent
## and always occupy west + south + east physical positions.
const ACCEPT_ACTIONS := ["ui_accept", "interact"]
const CANCEL_ACTIONS := ["ui_cancel"]
const PALETTE_1_ACTIONS := ["action_1"]  # always on west
const PALETTE_2_ACTIONS := ["action_2"]  # always on south (overlaps accept when accept_on_south)
const PALETTE_3_ACTIONS := ["action_3"]  # always on east  (overlaps cancel when accept_on_south)
# action_4 (reserved): north — no binding yet, will land here when added.

## Physical face-button → Godot button index, per scheme. "xinput" uses the
## SDL-normalized layout (south=0, east=1, west=2, north=3). The "switch"
## scheme reflects what Linux's hid-nintendo driver exposes for a Switch Pro
## controller, which differs from SDL's normalized layout because it bypasses
## the gamepad DB. If a Switch controller on a different platform reports the
## normalized layout instead, the player should pick xinput in onboarding.
const FACE_INDICES: Dictionary = {
	"xinput":    {"south": 0, "east": 1, "west": 2, "north": 3},
	"switch":    {"south": 1, "east": 0, "west": 3, "north": 2},
	"ds_cross":  {"south": 0, "east": 1, "west": 2, "north": 3},
	"ds_circle": {"south": 0, "east": 1, "west": 2, "north": 3},
	"keyboard":  {"south": 0, "east": 1, "west": 2, "north": 3},  # no-op for keyboard
}

var current_scheme: String = "keyboard"
## Default to inverted because the orbit camera's natural rotation direction
## reads as "inverted" to most players — flipping the default makes the
## toggle label ("Invert Camera X: ON") match the camera behaviour on first
## boot instead of being misleading.
var invert_camera_x: bool = true


func _ready() -> void:
	_load()
	_apply_button_mapping()


func toggle_invert_camera_x() -> void:
	invert_camera_x = not invert_camera_x
	_save()


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
	## Schemes whose accept button is physically on the east face:
	##   - switch: Nintendo A is east
	##   - ds_circle: PSZ/JP PSO uses Circle (east)
	## For xinput/ds_cross, accept is south (Xbox A / Cross). Actual button
	## indices are resolved through FACE_INDICES per scheme, so an east-bound
	## accept here fires the correct physical button regardless of whether
	## the OS reports SDL-normalized or raw HID indices.
	return current_scheme == "switch" or current_scheme == "ds_circle"


func _face(position: String) -> int:
	var map: Dictionary = FACE_INDICES.get(current_scheme, FACE_INDICES["xinput"])
	return int(map.get(position, 0))


func _apply_button_mapping() -> void:
	## Palette assignment to physical positions is scheme-independent
	## (west/south/east, north reserved). The raw button indices those
	## positions correspond to come from FACE_INDICES[current_scheme] so the
	## same physical press fires the same action regardless of how the OS
	## reports buttons.
	_set_joypad_button(PALETTE_1_ACTIONS, _face("west"))
	_set_joypad_button(PALETTE_2_ACTIONS, _face("south"))
	_set_joypad_button(PALETTE_3_ACTIONS, _face("east"))

	if accept_on_east():
		_set_joypad_button(ACCEPT_ACTIONS, _face("east"))
		_set_joypad_button(CANCEL_ACTIONS, _face("south"))
	else:
		_set_joypad_button(ACCEPT_ACTIONS, _face("south"))
		_set_joypad_button(CANCEL_ACTIONS, _face("east"))


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
	data["invert_camera_x"] = invert_camera_x
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

	if parsed.has("invert_camera_x"):
		invert_camera_x = bool(parsed["invert_camera_x"])

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
