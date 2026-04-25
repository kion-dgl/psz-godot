# Mobile on-screen controls overlay — emulator-style layout.
# Spawned on every scene via autoload. Activates only when the platform
# reports a touchscreen. Joystick on bottom-left drives move_*; an A/B/X/Y
# diamond on bottom-right covers the action verbs; START at top-center;
# camera shoulder buttons at top-left/right.
#
# Visuals are utility-grade (translucent rounded buttons with text labels).
# Swap for sprite-based skins later — the layout + InputMap mappings are
# the hard part.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

# Tunable layout
const JOYSTICK_INSET   := Vector2(120, 220)   # from bottom-left corner
const ACTION_INSET     := Vector2(180, 200)   # from bottom-right (centre of diamond)
const ACTION_RADIUS    := 80                  # distance from diamond centre to each button
const ACTION_BTN_SIZE  := Vector2(110, 110)
const START_BTN_SIZE   := Vector2(120, 60)
const SHOULDER_SIZE    := Vector2(140, 70)
const TOP_INSET        := 32                  # px from top edge

var _layer: CanvasLayer

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		queue_free()
		return

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	add_child(_layer)

	var screen := DisplayServer.window_get_size()

	# ---- Movement: virtual joystick bottom-left ----
	var joystick: VirtualJoystick = VirtualJoystickScene.instantiate()
	joystick.use_input_actions = true
	joystick.action_left = "move_left"
	joystick.action_right = "move_right"
	joystick.action_up = "move_forward"
	joystick.action_down = "move_backward"
	joystick.position = Vector2(JOYSTICK_INSET.x, float(screen.y) - JOYSTICK_INSET.y)
	_layer.add_child(joystick)

	# ---- Emulator-style action diamond bottom-right ----
	# Y at top, X at left, A at right, B at bottom (SNES layout).
	var diamond_centre := Vector2(float(screen.x) - ACTION_INSET.x, float(screen.y) - ACTION_INSET.y)
	_add_button("interact",      "A",  Color(0.96, 0.46, 0.42, 0.85), diamond_centre + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_button("dodge",         "B",  Color(0.42, 0.74, 0.96, 0.85), diamond_centre + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("palette_swap",  "X",  Color(0.55, 0.96, 0.65, 0.85), diamond_centre + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("quick_weapon",  "Y",  Color(0.96, 0.85, 0.42, 0.85), diamond_centre + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top-center START ----
	var start_pos := Vector2(float(screen.x) * 0.5 - START_BTN_SIZE.x * 0.5, float(TOP_INSET))
	_add_button("start",         "START", Color(0.7, 0.7, 0.7, 0.6), start_pos + START_BTN_SIZE * 0.5, START_BTN_SIZE)
	# Pause sits next to start — small, top-right corner — handy for menu
	var pause_pos := Vector2(float(screen.x) - 90 - 24, float(TOP_INSET))
	_add_button("pause",         "II",    Color(0.6, 0.6, 0.6, 0.55), pause_pos + Vector2(45, 25), Vector2(90, 50))
	# Quest log next to pause
	var qlog_pos := Vector2(24, float(TOP_INSET))
	_add_button("quest_log",     "LOG",   Color(0.6, 0.6, 0.6, 0.55), qlog_pos + Vector2(45, 25), Vector2(90, 50))

	# ---- Camera shoulder buttons (under START) ----
	var shoulder_y := float(TOP_INSET) + 70
	_add_button("camera_left",   "◀ CAM", Color(0.45, 0.45, 0.55, 0.6), Vector2(24 + SHOULDER_SIZE.x * 0.5, shoulder_y + SHOULDER_SIZE.y * 0.5), SHOULDER_SIZE)
	_add_button("camera_right",  "CAM ▶", Color(0.45, 0.45, 0.55, 0.6), Vector2(float(screen.x) - 24 - SHOULDER_SIZE.x * 0.5, shoulder_y + SHOULDER_SIZE.y * 0.5), SHOULDER_SIZE)

func _add_button(action: String, label: String, color: Color, centre: Vector2, size: Vector2) -> void:
	# TouchScreenButton is a Node2D; positions are top-left of its shape.
	# We accept a CENTRE point here and offset the visual children to match.
	var btn := TouchScreenButton.new()
	btn.action = action
	btn.shape_visible = false
	btn.passby_press = false
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = size
	btn.shape = shape
	btn.position = centre

	# Visible body — rounded rectangle via StyleBoxFlat applied to a Panel.
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = int(size.y * 0.5)
	sb.corner_radius_top_right = int(size.y * 0.5)
	sb.corner_radius_bottom_left = int(size.y * 0.5)
	sb.corner_radius_bottom_right = int(size.y * 0.5)
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

	_layer.add_child(btn)
