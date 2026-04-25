# Mobile on-screen controls overlay.
# Spawned on every scene via autoload (project.godot/autoload). Activates
# only when the platform reports a touchscreen — desktop/CI runs are
# completely untouched.
#
# The joystick uses Godot 4's InputMap actions (move_*) so it folds into the
# same code path as the keyboard/gamepad input. Buttons (interact, dodge,
# pause, palette_swap) are TouchScreenButtons that emit their action when
# pressed/released.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

var _layer: CanvasLayer

func _ready() -> void:
	# Only activate when we're actually on a touchscreen device.
	if not DisplayServer.is_touchscreen_available():
		queue_free()
		return

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	add_child(_layer)

	# ---- Movement: virtual joystick bottom-left ----
	var joystick: VirtualJoystick = VirtualJoystickScene.instantiate()
	joystick.use_input_actions = true
	joystick.action_left = "move_left"
	joystick.action_right = "move_right"
	joystick.action_up = "move_forward"
	joystick.action_down = "move_backward"
	joystick.position = Vector2(80, 0)
	joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	joystick.position += Vector2(80, -240)
	_layer.add_child(joystick)

	# ---- Action buttons bottom-right ----
	# Stack: interact (top), dodge (mid), pause (small, top-right corner)
	_add_action_button("interact", "ACT", Vector2(-180, -210), Vector2(120, 120))
	_add_action_button("dodge",    "DOD", Vector2(-180, -350), Vector2(100, 100))
	_add_action_button("pause",    "II",  Vector2(-80, 40),    Vector2(80, 80))

func _add_action_button(action: String, label: String, offset: Vector2, size: Vector2) -> void:
	var btn := TouchScreenButton.new()
	btn.action = action
	btn.shape_visible = true
	btn.passby_press = true
	# Build a simple round shape so it's tappable.
	var shape := CircleShape2D.new()
	shape.radius = size.x * 0.5
	btn.shape = shape

	# Visible disc + label.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = size
	bg.position = -size * 0.5
	btn.add_child(bg)

	var lbl := Label.new()
	lbl.text = label
	lbl.size = size
	lbl.position = -size * 0.5
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(lbl)

	# Anchor by feeding screen-relative position
	var screen := DisplayServer.window_get_size()
	if offset.x < 0:
		btn.position.x = float(screen.x) + offset.x
	else:
		btn.position.x = offset.x
	if offset.y < 0:
		btn.position.y = float(screen.y) + offset.y
	else:
		btn.position.y = offset.y
	_layer.add_child(btn)
