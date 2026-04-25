# Mobile on-screen controls overlay.
# Activates on Android/iOS or any platform reporting a touchscreen. Builds
# a CanvasLayer with: a virtual joystick anchored bottom-left, a SNES-style
# A/B/X/Y diamond bottom-right, START / LOG / II / PAL across the top.
# Joystick output → move_* InputMap actions; A also dispatches ui_accept,
# B + pause dispatch ui_cancel, joystick analog axis edge-mirrors to
# ui_left/right/up/down so menus respond to the same input.
#
# Controls a future options screen flips:
#   MobileControls.set_enabled(false)  → writes user://mobile_controls.cfg
#                                          and overlay disappears next boot.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

# Layout (1280×720 viewport).
const ACTION_INSET     := Vector2(180, 180)   # diamond centre, from bottom-right
const ACTION_RADIUS    := 95
const ACTION_BTN_SIZE  := Vector2(80, 80)
const TOP_BTN_SIZE     := Vector2(110, 48)
const TOP_INSET        := 24

const MENU_AXIS_THRESHOLD := 0.5
const ACTION_MIRROR := {
	"interact": "ui_accept",
	"start":    "ui_accept",
	"pause":    "ui_cancel",
}

const SETTINGS_PATH := "user://mobile_controls.cfg"

var _layer: CanvasLayer
var _joystick: VirtualJoystick
var _last_axis := Vector2.ZERO
var _ui_pressed := {}

func _ready() -> void:
	var enabled := _is_enabled_default()
	# Allow user override (options screen will write this file).
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			enabled = (f.get_as_text().strip_edges() != "off")
			f.close()
	if not enabled:
		print("[MobileControls] disabled by user setting")
		queue_free()
		return
	print("[MobileControls] activating  os=%s touchscreen=%s" % [OS.get_name(), DisplayServer.is_touchscreen_available()])
	Input.set_emulate_mouse_from_touch(true)

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	add_child(_layer)
	_build()

func _is_enabled_default() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

func _build() -> void:
	var v := get_viewport().get_visible_rect().size

	# ---- Joystick bottom-left (default size, just inset from corner) ----
	_joystick = VirtualJoystickScene.instantiate()
	_joystick.use_input_actions = true
	_joystick.action_left = "move_left"
	_joystick.action_right = "move_right"
	_joystick.action_up = "move_forward"
	_joystick.action_down = "move_backward"
	_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	_joystick.position += Vector2(40, -40)
	_layer.add_child(_joystick)

	# ---- A/B/X/Y diamond bottom-right ----
	# A right=interact, B bottom=dodge, X top=quick_weapon (menu), Y left=action_1.
	var c := Vector2(v.x - ACTION_INSET.x, v.y - ACTION_INSET.y)
	_add_button("interact",     "A", c + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_button("dodge",        "B", c + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("quick_weapon", "X", c + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("action_1",     "Y", c + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top row ----
	var top_y := TOP_INSET + TOP_BTN_SIZE.y * 0.5
	_add_button("start",     "START", Vector2(v.x * 0.5,                                 top_y), Vector2(140, 50))
	_add_button("pause",     "II",    Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET,    top_y), TOP_BTN_SIZE)
	_add_button("quest_log", "LOG",   Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET,          top_y), TOP_BTN_SIZE)
	# Second row, top-left: PAL for palette_swap.
	var second_y := top_y + TOP_BTN_SIZE.y + 12
	_add_button("palette_swap", "PAL", Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET, second_y), TOP_BTN_SIZE)
	print("[MobileControls] _build done")

func _add_button(action: String, label: String, centre: Vector2, size: Vector2) -> void:
	var btn := TouchScreenButton.new()
	btn.action = action
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

	if action in ACTION_MIRROR:
		var ui_action: String = ACTION_MIRROR[action]
		btn.pressed.connect(_press_ui.bind(ui_action))
		btn.released.connect(_release_ui.bind(ui_action))

	_layer.add_child(btn)

func _press_ui(ui_action: String) -> void:
	if not _ui_pressed.get(ui_action, false):
		_dispatch(ui_action, true)
		_ui_pressed[ui_action] = true

func _release_ui(ui_action: String) -> void:
	if _ui_pressed.get(ui_action, false):
		_dispatch(ui_action, false)
		_ui_pressed[ui_action] = false

# Inject a real InputEventAction so menus that listen via _input /
# _unhandled_input actually receive it. Input.action_press() only updates
# polled state and skips the event pipeline.
func _dispatch(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func _process(_dt: float) -> void:
	if not _joystick:
		return
	var out := _joystick.output
	_axis("ui_left",  -out.x, _last_axis.x < 0)
	_axis("ui_right",  out.x, _last_axis.x > 0)
	_axis("ui_up",    -out.y, _last_axis.y < 0)
	_axis("ui_down",   out.y, _last_axis.y > 0)
	_last_axis = out

func _axis(ui_action: String, current: float, was_active: bool) -> void:
	var now_active := current > MENU_AXIS_THRESHOLD
	if now_active and not was_active:
		_dispatch(ui_action, true)
	elif (not now_active) and was_active:
		_dispatch(ui_action, false)

# Options-screen API: MobileControls.set_enabled(false) to hide overlay
# next boot. Stores a tiny text file because JSON was overkill and the
# parser path turned out to be where the previous build was silently
# blowing up.
static func set_enabled(enabled: bool) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string("on" if enabled else "off")
		f.close()
