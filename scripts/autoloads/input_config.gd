extends Node
## InputConfig — stores the active control scheme and persists to
## user://input_config.json.
##
## Two storage models coexist:
##
## 1. **Positional** (the new model, set by the multi-step input_select
##    flow): a per-position button-index mapping the player established
##    by pressing each of the 4 face buttons in turn. Robust to driver
##    quirks (Linux hid-nintendo reports south=1/east=0 for Switch Pro;
##    SDL-normalized reports south=0/east=1; the positional mapping
##    captures whichever indices THIS user's controller emits).
##
## 2. **Scheme-name** (legacy, kept as a derived read-only view): one of
##    "keyboard"/"xinput"/"switch"/"ds_cross"/"ds_circle". Some downstream
##    callers (field_hud icon glyphs, settings label) still key off the
##    scheme name; we derive it from the positional fields so they keep
##    working without changes.
##
## Migration: when an old config (just `{"scheme": "xinput"}`) is read on
## load, we infer the positional fields from FACE_INDICES_DEFAULT[scheme]
## and write the new shape back on next save. No re-onboarding required.

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
## south and east depending on accept_position; palette slots are
## scheme-independent and always occupy west + south + east physical positions.
const ACCEPT_ACTIONS := ["ui_accept", "interact"]
const CANCEL_ACTIONS := ["ui_cancel"]
const PALETTE_1_ACTIONS := ["action_1"]  # always on west
const PALETTE_2_ACTIONS := ["action_2"]  # always on south
const PALETTE_3_ACTIONS := ["action_3"]  # always on east
const QUICK_WEAPON_ACTIONS := ["quick_weapon"]

## SDL-normalized layout — used as the default face mapping for newly-detected
## controllers (and during migration from legacy "scheme"-only configs) where
## we don't have an explicit user-pressed mapping yet. "switch" uses Linux's
## hid-nintendo layout, which inverts south↔east relative to SDL. The user
## can override any of these by re-running the input_select onboarding from
## the settings menu ("Reconfigure Controls").
const FACE_INDICES_DEFAULT: Dictionary = {
	"xbox":        {"south": 0, "east": 1, "west": 2, "north": 3},
	"switch":      {"south": 1, "east": 0, "west": 3, "north": 2},
	"playstation": {"south": 0, "east": 1, "west": 2, "north": 3},
}

# ── State ─────────────────────────────────────────────────────────────

## "controller" | "keyboard"
var device: String = "keyboard"

## "xbox" | "switch" | "playstation" — only meaningful when device == "controller"
var controller_type: String = "xbox"

## Per-position button indices captured during onboarding (or migrated from
## FACE_INDICES_DEFAULT for legacy configs).
var face_mapping: Dictionary = {"south": 0, "east": 1, "west": 2, "north": 3}

## "west" | "south" | "east" — chosen by the player in PICK_ACCEPT.
var accept_position: String = "south"

## "west" | "south" | "east" — chosen by the player in PICK_CANCEL from
## whichever two faces are NOT accept. Falls back to the legacy "south
## unless accept is south else east" rule for migrated / unset configs.
var cancel_position: String = "east"

## Derived: legacy scheme name. Updated whenever device/type/accept_position
## change. Treat as read-only externally — write via set_controller_config /
## set_keyboard / cycle.
var current_scheme: String = "keyboard"

## Right-stick X invert toggle (unchanged from before).
var invert_camera_x: bool = false
## Right-stick Y axis tilts the orbit camera up/down. Off by default
## until enough playtesters opt in.
var enable_camera_y: bool = false


func _ready() -> void:
	_load()
	_apply_button_mapping()


# ── Camera toggles (unchanged) ────────────────────────────────────────

func toggle_invert_camera_x() -> void:
	invert_camera_x = not invert_camera_x
	_save()


func toggle_enable_camera_y() -> void:
	enable_camera_y = not enable_camera_y
	_save()


# ── Scheme picker API ─────────────────────────────────────────────────

## Cycle through the 5 derived scheme names. Kept for back-compat with
## any caller that hasn't migrated to set_controller_config. The settings
## menu now uses "Reconfigure Controls" instead of cycling, so in practice
## this should only fire from tests.
func cycle(direction: int) -> void:
	var idx := SCHEMES.find(current_scheme)
	if idx == -1:
		idx = 0
	idx = (idx + direction + SCHEMES.size()) % SCHEMES.size()
	set_scheme(SCHEMES[idx])


## Legacy entry point: set the active scheme by name. Translates into the
## positional fields by re-applying FACE_INDICES_DEFAULT for the matching
## type, then persists.
func set_scheme(scheme: String) -> void:
	if not _apply_scheme_no_save(scheme):
		return
	scheme_changed.emit(current_scheme)
	_save()


## Same as set_scheme but skips the disk write. Used by:
##   • set_scheme (composed into the public API)
##   • the test runner (which deliberately doesn't want to clobber a dev's
##     on-disk input_config.json when exercising scheme bindings)
##   • the legacy-format migration path in _load
##
## Returns false if the scheme name isn't recognized.
func _apply_scheme_no_save(scheme: String) -> bool:
	if not scheme in SCHEMES:
		return false
	if scheme == "keyboard":
		device = "keyboard"
	else:
		device = "controller"
		match scheme:
			"xinput":
				controller_type = "xbox"
				accept_position = "south"
			"switch":
				controller_type = "switch"
				accept_position = "east"
			"ds_cross":
				controller_type = "playstation"
				accept_position = "south"
			"ds_circle":
				controller_type = "playstation"
				accept_position = "east"
		face_mapping = (FACE_INDICES_DEFAULT[controller_type] as Dictionary).duplicate()
		# Legacy schemes never split cancel out; pick the conventional one.
		cancel_position = "south" if accept_position != "south" else "east"
	_recompute_scheme()
	_apply_button_mapping()
	return true


## New entry point used by the multi-step input_select onboarding.
## type: "xbox" | "switch" | "playstation"
## face: { south: int, east: int, west: int, north: int }
## accept: "west" | "south" | "east"
## cancel: "west" | "south" | "east" — must differ from accept
func set_controller_config(type: String, face: Dictionary, accept: String, cancel: String = "") -> void:
	device = "controller"
	controller_type = type
	face_mapping = face.duplicate()
	accept_position = accept
	# Default cancel falls on south unless that's already accept, else east.
	# Same rule the migration path uses so older saves and skipping the
	# PICK_CANCEL step both land on the same conventional mapping.
	if cancel == "" or cancel == accept:
		cancel = "south" if accept != "south" else "east"
	cancel_position = cancel
	_recompute_scheme()
	_apply_button_mapping()
	scheme_changed.emit(current_scheme)
	_save()


## Sister entry point: pick keyboard. Uses fixed defaults; no per-key
## mapping yet (deferred until international-layout complaints come in).
func set_keyboard() -> void:
	device = "keyboard"
	_recompute_scheme()
	_apply_button_mapping()
	scheme_changed.emit(current_scheme)
	_save()


## Nuke the saved config and reset to defaults. Used by the settings
## menu's "Reconfigure Controls" entry before re-routing the player to
## input_select.tscn.
func clear() -> void:
	device = "keyboard"
	controller_type = "xbox"
	face_mapping = (FACE_INDICES_DEFAULT["xbox"] as Dictionary).duplicate()
	accept_position = "south"
	cancel_position = "east"
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func get_label() -> String:
	return SCHEME_LABELS.get(current_scheme, current_scheme)


func is_switch() -> bool:
	return current_scheme == "switch"


func accept_on_east() -> bool:
	return accept_position == "east"


func has_saved_config() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ── Internals ─────────────────────────────────────────────────────────

func _recompute_scheme() -> void:
	if device == "keyboard":
		current_scheme = "keyboard"
		return
	match controller_type:
		"xbox":
			current_scheme = "xinput"
		"switch":
			current_scheme = "switch"
		"playstation":
			current_scheme = "ds_cross" if accept_position == "south" else "ds_circle"
		_:
			current_scheme = "xinput"


func _face(position: String) -> int:
	return int(face_mapping.get(position, 0))


func _apply_button_mapping() -> void:
	## Palette assignment to physical positions is scheme-independent
	## (west/south/east, north holds quick_weapon). The raw button indices
	## come from face_mapping so the same physical press fires the same
	## action regardless of how the OS reports buttons.
	_set_joypad_button(PALETTE_1_ACTIONS, _face("west"))
	_set_joypad_button(PALETTE_2_ACTIONS, _face("south"))
	_set_joypad_button(PALETTE_3_ACTIONS, _face("east"))
	_set_joypad_button(QUICK_WEAPON_ACTIONS, _face("north"))

	# Accept and cancel = whichever faces the player picked during onboarding
	# (each one of west / south / east). PICK_CANCEL filters the cards down
	# to the two faces that weren't picked as accept so they can't collide.
	_set_joypad_button(ACCEPT_ACTIONS, _face(accept_position))
	_set_joypad_button(CANCEL_ACTIONS, _face(cancel_position))


func _set_joypad_button(actions: Array, button_index: int) -> void:
	for action_name in actions:
		if not InputMap.has_action(action_name):
			continue
		var events := InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventJoypadButton:
				InputMap.action_erase_event(action_name, event)
		var new_event := InputEventJoypadButton.new()
		new_event.button_index = button_index
		new_event.device = -1
		InputMap.action_add_event(action_name, new_event)


func _save() -> void:
	# Read-merge-write so a control change never clobbers user-authored
	# fields (preset, keyboard remaps from the future config UI). Fixes #128.
	var data: Dictionary = {}
	if FileAccess.file_exists(SAVE_PATH):
		var in_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if in_file:
			var parsed: Variant = JSON.parse_string(in_file.get_as_text())
			if parsed is Dictionary:
				data = parsed
	# New positional fields are the source of truth. `scheme` is written
	# alongside as a denormalized hint so older builds can roll back
	# gracefully and tests that bind to scheme keep working.
	data["device"] = device
	data["controller_type"] = controller_type
	data["face_mapping"] = face_mapping
	data["accept_position"] = accept_position
	data["cancel_position"] = cancel_position
	data["scheme"] = current_scheme
	data["invert_camera_x"] = invert_camera_x
	data["enable_camera_y"] = enable_camera_y
	var out_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if out_file:
		out_file.store_string(JSON.stringify(data))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return

	# New positional format: take the positional fields directly.
	if parsed.has("device") and parsed.has("face_mapping"):
		device = str(parsed.get("device", "keyboard"))
		controller_type = str(parsed.get("controller_type", "xbox"))
		var fm: Variant = parsed.get("face_mapping", {})
		if fm is Dictionary:
			face_mapping = (fm as Dictionary).duplicate()
		accept_position = str(parsed.get("accept_position", "south"))
		# cancel_position is new in this build — older positional configs
		# don't have it. Fall back to the legacy "south unless accept is
		# south else east" rule so upgrading saves don't surprise the player.
		var default_cancel := "south" if accept_position != "south" else "east"
		cancel_position = str(parsed.get("cancel_position", default_cancel))
		_recompute_scheme()
	# Legacy format: only the "scheme" name was written. Infer positional
	# fields from FACE_INDICES_DEFAULT so the player doesn't get re-prompted
	# on upgrade. Trigger a save so the file is rewritten in the new shape.
	elif parsed.has("scheme"):
		var s: String = str(parsed["scheme"])
		if s in SCHEMES:
			if _apply_scheme_no_save(s):
				_save()
			return

	if parsed.has("invert_camera_x"):
		invert_camera_x = bool(parsed["invert_camera_x"])

	if parsed.has("enable_camera_y"):
		enable_camera_y = bool(parsed["enable_camera_y"])

	# Extended format: preset + keyboard remaps (future config UI)
	if parsed.has("preset") and parsed.has("keyboard"):
		var preset: String = str(parsed.get("preset", "modern"))
		print("[InputConfig] Loading preset: %s" % preset)
		var kb: Dictionary = parsed.get("keyboard", {})
		_apply_keyboard_config(kb)


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


func _apply_keyboard_config(kb: Dictionary) -> void:
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
		var events := InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventKey:
				InputMap.action_erase_event(action_name, event)
		var new_event := InputEventKey.new()
		new_event.physical_keycode = keycode
		new_event.device = -1
		InputMap.action_add_event(action_name, new_event)
		print("[InputConfig] Remapped %s → %s (%s)" % [action_name, key_name, keycode])
