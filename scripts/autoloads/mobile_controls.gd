# Mobile on-screen controls overlay — emulator-style layout.
#
# - Joystick on bottom-left drives move_* AND mirrors to ui_left/right/up/down
#   so it works in menus too.
# - A/B/X/Y diamond on bottom-right covers the action verbs. A also mirrors
#   to ui_accept and B to ui_cancel so dialog/menu prompts respond.
# - START at top-centre, pause/quest_log/cam shoulders around it.
# - Activates only when DisplayServer.is_touchscreen_available() so desktop
#   / CI runs are unaffected.
# - Layout uses the SCENE viewport size (not OS window pixels) so positions
#   stay correct under canvas_items stretch on high-DPI Android.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

# Layout constants — in scene/viewport units. Project viewport is 1280×720
# (16:9); stretch/aspect="keep" gives us letterbox/pillarbox on non-16:9
# phones so the visible-rect remains 1280×720 in scene units regardless of
# the OS pixel dims.
const JOYSTICK_INSET   := Vector2(160, 200)   # from bottom-left corner
const ACTION_INSET     := Vector2(200, 200)   # from bottom-right (centre of diamond)
const ACTION_RADIUS    := 80                  # button distance from diamond centre
const ACTION_BTN_SIZE  := Vector2(120, 120)
const TOP_BTN_SIZE     := Vector2(130, 56)
const TOP_INSET        := 24

# Joystick → menu mirror. When the joystick output crosses these in any
# direction we synthesize the corresponding ui_* edge event so menu
# cursors scroll with the same stick.
const MENU_AXIS_THRESHOLD := 0.5

# Action mirroring (game action → UI action). Buttons that fire these will
# also fire the ui_* equivalent.
const ACTION_MIRROR := {
	"interact": "ui_accept",
	"pause":    "ui_cancel",
	"start":    "ui_accept",
}

var _layer: CanvasLayer
var _joystick: VirtualJoystick
var _last_axis := Vector2.ZERO
var _action_state := {}      # action → bool currently pressed
var _ui_state := {}          # ui action → bool we currently have pressed

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		queue_free()
		return

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	# follow_viewport_enabled keeps the layer in scene coords under canvas_items stretch.
	_layer.follow_viewport_enabled = true
	add_child(_layer)

	# Use scene/viewport size, NOT DisplayServer.window_get_size() (that returns
	# OS pixels, which on a high-DPI phone is much bigger than the mobile
	# viewport — buttons get placed off-screen).
	var v := get_viewport().get_visible_rect().size
	# Also re-layout if the viewport size changes (orientation flip etc).
	get_viewport().size_changed.connect(_relayout)
	_build(v)

func _build(v: Vector2) -> void:
	# ---- Movement: virtual joystick bottom-left ----
	_joystick = VirtualJoystickScene.instantiate()
	_joystick.use_input_actions = true
	_joystick.action_left = "move_left"
	_joystick.action_right = "move_right"
	_joystick.action_up = "move_forward"
	_joystick.action_down = "move_backward"
	_joystick.position = Vector2(JOYSTICK_INSET.x, v.y - JOYSTICK_INSET.y)
	_layer.add_child(_joystick)

	# ---- A/B/X/Y diamond bottom-right (SNES-style) ----
	var diamond_centre := Vector2(v.x - ACTION_INSET.x, v.y - ACTION_INSET.y)
	_add_button("interact",      "A", Color(0.96, 0.46, 0.42, 0.85), diamond_centre + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_button("dodge",         "B", Color(0.42, 0.74, 0.96, 0.85), diamond_centre + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("palette_swap",  "X", Color(0.55, 0.96, 0.65, 0.85), diamond_centre + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("quick_weapon",  "Y", Color(0.96, 0.85, 0.42, 0.85), diamond_centre + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top row ----
	var start_pos := Vector2(v.x * 0.5, TOP_INSET + TOP_BTN_SIZE.y * 0.5)
	_add_button("start",         "START", Color(0.7, 0.7, 0.7, 0.7), start_pos, Vector2(150, 60))
	_add_button("pause",         "II",    Color(0.6, 0.6, 0.6, 0.6), Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET, TOP_INSET + TOP_BTN_SIZE.y * 0.5), TOP_BTN_SIZE)
	_add_button("quest_log",     "LOG",   Color(0.6, 0.6, 0.6, 0.6), Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET, TOP_INSET + TOP_BTN_SIZE.y * 0.5), TOP_BTN_SIZE)

	# ---- Camera shoulder buttons ----
	var shoulder_y := TOP_INSET + TOP_BTN_SIZE.y + 12 + TOP_BTN_SIZE.y * 0.5
	_add_button("camera_left",   "◀ CAM", Color(0.45, 0.45, 0.55, 0.6), Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET, shoulder_y), TOP_BTN_SIZE)
	_add_button("camera_right",  "CAM ▶", Color(0.45, 0.45, 0.55, 0.6), Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET, shoulder_y), TOP_BTN_SIZE)

func _relayout() -> void:
	# Tear down + rebuild on resize. Cheap — only a handful of nodes.
	for c in _layer.get_children():
		c.queue_free()
	_build(get_viewport().get_visible_rect().size)

func _add_button(action: String, label: String, color: Color, centre: Vector2, size: Vector2) -> void:
	var btn := TouchScreenButton.new()
	btn.action = action
	btn.shape_visible = false
	btn.passby_press = false
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = size
	btn.shape = shape
	btn.position = centre

	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	var corner := int(min(size.x, size.y) * 0.5)
	sb.corner_radius_top_left = corner
	sb.corner_radius_top_right = corner
	sb.corner_radius_bottom_left = corner
	sb.corner_radius_bottom_right = corner
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(1, 1, 1, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = size
	panel.position = -size * 0.5
	btn.add_child(panel)

	var lbl := Label.new()
	lbl.text = label
	lbl.size = size
	lbl.position = -size * 0.5
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", int(min(size.x, size.y) * 0.32))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(lbl)

	# Mirror to ui_* if applicable
	if action in ACTION_MIRROR:
		var ui_action: String = ACTION_MIRROR[action]
		btn.pressed.connect(_press_ui.bind(ui_action))
		btn.released.connect(_release_ui.bind(ui_action))

	_layer.add_child(btn)

func _press_ui(ui_action: String) -> void:
	if not _ui_state.get(ui_action, false):
		Input.action_press(ui_action)
		_ui_state[ui_action] = true

func _release_ui(ui_action: String) -> void:
	if _ui_state.get(ui_action, false):
		Input.action_release(ui_action)
		_ui_state[ui_action] = false

func _process(_dt: float) -> void:
	# Mirror joystick analog axis → ui_left/right/up/down so menus respond
	# to the same stick. Edge-triggered: press once when crossing threshold,
	# release when returning to centre.
	if not _joystick:
		return
	var out := _joystick.output
	_axis_mirror("ui_left",  -out.x, _last_axis.x < 0)
	_axis_mirror("ui_right",  out.x, _last_axis.x > 0)
	_axis_mirror("ui_up",    -out.y, _last_axis.y < 0)
	_axis_mirror("ui_down",   out.y, _last_axis.y > 0)
	_last_axis = out

func _axis_mirror(ui_action: String, current: float, was_active: bool) -> void:
	var now_active := current > MENU_AXIS_THRESHOLD
	if now_active and not was_active:
		Input.action_press(ui_action)
	elif (not now_active) and was_active:
		Input.action_release(ui_action)
