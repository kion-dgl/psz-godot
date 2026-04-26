# Mobile on-screen controls overlay.
#
# Pretends to be a virtual gamepad: every touch emits the SAME
# InputEventJoypadButton / InputEventJoypadMotion events a real Xbox or
# Switch controller would, with the standard SDL2 button indices Godot
# uses (JOY_BUTTON_A = 0, START = 6, LEFT_SHOULDER = 9, …). The project's
# existing InputConfig + InputMap handles the rest — whichever scheme the
# player picked on the input_select screen (xinput / switch / ds_cross /
# ds_circle / keyboard) is the one that dispatches B → ui_cancel,
# south-face → ui_accept, etc. No action-name-mirroring hacks.
#
# Activates on Android/iOS or any platform reporting a touchscreen. The
# user can disable via a future options screen by calling
# MobileControls.set_enabled(false), which writes user://mobile_controls.cfg.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

# 1280×720 viewport coords.
const ACTION_INSET     := Vector2(180, 180)   # diamond centre, from bottom-right
const ACTION_RADIUS    := 95
const ACTION_BTN_SIZE  := Vector2(80, 80)
const TOP_BTN_SIZE     := Vector2(110, 48)
const TOP_INSET        := 24

# Joystick deadzone for emitting axis events. Anything below this looks
# like noise to the InputMap layer; past it we emit the raw -1..+1 axis.
const STICK_DEADZONE := 0.18

const SETTINGS_PATH := "user://mobile_controls.cfg"

var _layer: CanvasLayer
var _joystick: VirtualJoystick
var _dpad: Node2D
var _last_axis := Vector2.ZERO

# Menu-mode state. When ANY of these flags is set we hide the analog
# joystick and show a 4-button dpad instead — discrete presses are easier
# than thumbing an analog stick to scroll a list.
var _shop_open := false
var _start_menu_open := false
var _on_menu_scene := false  # character_select / character_create

const MENU_SCENES := {
	"res://scenes/2d/character_select.tscn": true,
	"res://scenes/2d/character_create.tscn": true,
}

func _ready() -> void:
	if not _resolve_enabled():
		print("[MobileControls] disabled")
		queue_free()
		return
	print("[MobileControls] activating  os=%s" % OS.get_name())
	Input.set_emulate_mouse_from_touch(true)

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	add_child(_layer)
	_build()
	_wire_menu_signals()
	_check_menu_scene()

func _resolve_enabled() -> bool:
	var default := OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return default
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return default
	var v := f.get_as_text().strip_edges()
	f.close()
	return v != "off"

func _build() -> void:
	var v := get_viewport().get_visible_rect().size

	# ---- Joystick bottom-left (gameplay mode) ----
	# Disable the addon's built-in InputMap action emit — we drive the
	# joystick output ourselves and emit raw left-stick axis events instead,
	# so the project's existing axis bindings (move_*, ui_*) all light up
	# without us touching the InputMap.
	_joystick = VirtualJoystickScene.instantiate()
	_joystick.use_input_actions = false
	_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	_joystick.position += Vector2(40, -40)
	_layer.add_child(_joystick)

	# ---- Dpad bottom-left (menu mode, hidden by default) ----
	# Same anchor as the joystick. Visible only when the player is in a
	# shop / start menu / character-pick screen. Each direction emits
	# JOY_BUTTON_DPAD_* and the project's input scheme handles the rest.
	_dpad = _build_dpad(v)
	_dpad.visible = false
	_layer.add_child(_dpad)

	# ---- A/B/X/Y diamond bottom-right ----
	# A south = JOY_BUTTON_A (0)
	# B east  = JOY_BUTTON_B (1)
	# X west  = JOY_BUTTON_X (2)
	# Y north = JOY_BUTTON_Y (3)
	# Diamond layout: A on the right (east), B at bottom (south of centre),
	# X at top (north), Y on the left (west) — matches the SNES face plate.
	var c := Vector2(v.x - ACTION_INSET.x, v.y - ACTION_INSET.y)
	_add_button(JOY_BUTTON_A, "A", c + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_button(JOY_BUTTON_B, "B", c + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button(JOY_BUTTON_X, "X", c + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button(JOY_BUTTON_Y, "Y", c + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top row: LOG | START | II ----
	var top_y := TOP_INSET + TOP_BTN_SIZE.y * 0.5
	_add_button(JOY_BUTTON_BACK,  "LOG",   Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET,        top_y), TOP_BTN_SIZE)
	_add_button(JOY_BUTTON_START, "START", Vector2(v.x * 0.5,                                top_y), Vector2(140, 50))
	_add_button(JOY_BUTTON_GUIDE, "II",    Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET,   top_y), TOP_BTN_SIZE)

	# Second row top-left: PAL = L1 (left shoulder).
	var second_y := top_y + TOP_BTN_SIZE.y + 12
	_add_button(JOY_BUTTON_LEFT_SHOULDER,  "L1 / PAL", Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET, second_y), TOP_BTN_SIZE)
	# Right shoulder (R1) on the right edge — useful for whatever the project
	# binds it to (camera lock, weapon swap, etc).
	_add_button(JOY_BUTTON_RIGHT_SHOULDER, "R1", Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET, second_y), TOP_BTN_SIZE)

	print("[MobileControls] _build done — overlay active as virtual gamepad")

func _add_button(button_index: int, label: String, centre: Vector2, size: Vector2) -> void:
	# TouchScreenButton's `action` field is left empty — we emit raw gamepad
	# events from the pressed/released signals instead.
	var btn := TouchScreenButton.new()
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = size
	btn.shape = shape
	btn.position = centre

	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	var corner := int(min(size.x, size.y) * 0.5)
	sb.corner_radius_top_left = corner
	sb.corner_radius_top_right = corner
	sb.corner_radius_bottom_left = corner
	sb.corner_radius_bottom_right = corner
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_color = Color(1, 1, 1, 0.85)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.position = -size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(p)

	var l := Label.new()
	l.text = label
	l.size = size
	l.position = -size * 0.5
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_font_size_override("font_size", int(min(size.x, size.y) * 0.36))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(l)

	btn.pressed.connect(_emit_button.bind(button_index, true))
	btn.released.connect(_emit_button.bind(button_index, false))
	_layer.add_child(btn)

func _emit_button(button_index: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button_index
	ev.pressure = 1.0 if pressed else 0.0
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _process(_dt: float) -> void:
	# Mirror joystick analog output to JoypadMotion left-stick axes (X = 0,
	# Y = 1). Edge-emit only when crossing the deadzone or when the value
	# changes meaningfully so we don't spam the input pipeline every frame.
	if not _joystick:
		return
	var out := _joystick.output
	if absf(out.x - _last_axis.x) > 0.02:
		_emit_axis(JOY_AXIS_LEFT_X, out.x if absf(out.x) > STICK_DEADZONE else 0.0)
	if absf(out.y - _last_axis.y) > 0.02:
		_emit_axis(JOY_AXIS_LEFT_Y, out.y if absf(out.y) > STICK_DEADZONE else 0.0)
	_last_axis = out

func _emit_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)

# ---- Dpad ------------------------------------------------------------------

const DPAD_INSET   := Vector2(170, 170)   # centre, from bottom-left
const DPAD_BTN     := Vector2(70, 70)     # each direction button
const DPAD_RADIUS  := 70                  # centre-to-button distance

func _build_dpad(v: Vector2) -> Node2D:
	var root := Node2D.new()
	var c := Vector2(DPAD_INSET.x, v.y - DPAD_INSET.y)
	# 4-direction cross. Up/Down/Left/Right map to standard D-pad buttons.
	root.add_child(_make_button(JOY_BUTTON_DPAD_UP,    "▲", c + Vector2( 0, -DPAD_RADIUS), DPAD_BTN))
	root.add_child(_make_button(JOY_BUTTON_DPAD_DOWN,  "▼", c + Vector2( 0,  DPAD_RADIUS), DPAD_BTN))
	root.add_child(_make_button(JOY_BUTTON_DPAD_LEFT,  "◀", c + Vector2(-DPAD_RADIUS,  0), DPAD_BTN))
	root.add_child(_make_button(JOY_BUTTON_DPAD_RIGHT, "▶", c + Vector2( DPAD_RADIUS,  0), DPAD_BTN))
	return root

# Same as _add_button but RETURNS the node instead of adding to _layer, so
# the dpad subtree can own its own buttons.
func _make_button(button_index: int, label: String, centre: Vector2, size: Vector2) -> TouchScreenButton:
	var btn := TouchScreenButton.new()
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = size
	btn.shape = shape
	btn.position = centre

	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	var corner := int(min(size.x, size.y) * 0.5)
	sb.corner_radius_top_left = corner
	sb.corner_radius_top_right = corner
	sb.corner_radius_bottom_left = corner
	sb.corner_radius_bottom_right = corner
	sb.border_width_top = 3; sb.border_width_bottom = 3
	sb.border_width_left = 3; sb.border_width_right = 3
	sb.border_color = Color(1, 1, 1, 0.85)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.position = -size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(p)

	var l := Label.new()
	l.text = label
	l.size = size
	l.position = -size * 0.5
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_font_size_override("font_size", int(min(size.x, size.y) * 0.46))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(l)

	btn.pressed.connect(_emit_button.bind(button_index, true))
	btn.released.connect(_emit_button.bind(button_index, false))
	return btn

# ---- Menu-mode detection ---------------------------------------------------

func _wire_menu_signals() -> void:
	# GameState autoload broadcasts shop + pause-menu state. Connect both.
	if Engine.has_singleton("GameState") or has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if gs.has_signal("shop_opened"):
			gs.shop_opened.connect(func(_npc: String) -> void: _shop_open = true; _refresh_mode())
		if gs.has_signal("shop_closed"):
			gs.shop_closed.connect(func() -> void: _shop_open = false; _refresh_mode())
		if gs.has_signal("pause_menu_toggled"):
			gs.pause_menu_toggled.connect(func(open: bool) -> void: _start_menu_open = open; _refresh_mode())
	# Re-check menu scene flag whenever the active scene changes.
	get_tree().tree_changed.connect(_check_menu_scene)

func _check_menu_scene() -> void:
	var scene := get_tree().current_scene
	var is_menu := false
	if scene and scene.scene_file_path in MENU_SCENES:
		is_menu = true
	if is_menu != _on_menu_scene:
		_on_menu_scene = is_menu
		_refresh_mode()

func _refresh_mode() -> void:
	var menu := _shop_open or _start_menu_open or _on_menu_scene
	if _joystick:
		_joystick.visible = not menu
	if _dpad:
		_dpad.visible = menu

# Options-screen toggle.
static func set_enabled(enabled: bool) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string("on" if enabled else "off")
		f.close()
