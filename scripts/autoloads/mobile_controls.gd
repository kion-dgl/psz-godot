# Mobile on-screen controls — DIAGNOSTIC BUILD.
# Strips back to the absolute minimum so we can confirm whether the
# autoload runs at all on Android. If you see a giant red "[MOBILE
# CONTROLS LOADED]" banner on top of the screen, the autoload + the
# CanvasLayer are working, and the issue is with the joystick / buttons
# specifically. If you DON'T see it, the autoload itself is failing
# (queue_free, parse error, or never reached).

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

func _ready() -> void:
	print("[MobileControls] _ready start  os=%s touchscreen=%s" % [OS.get_name(), DisplayServer.is_touchscreen_available()])
	# UNCONDITIONAL on every platform for diagnosis. We'll re-add the
	# Android/touch gate once we know the overlay shows.

	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "MobileControls"
	add_child(layer)

	# 1. Giant red banner at the top — pure smoke test.
	var banner := Label.new()
	banner.text = "[MOBILE CONTROLS LOADED]"
	banner.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
	banner.add_theme_font_size_override("font_size", 28)
	banner.position = Vector2(20, 20)
	layer.add_child(banner)
	print("[MobileControls] added banner")

	# 2. Try the joystick (default size + position from the .tscn, no overrides).
	var joystick: VirtualJoystick = VirtualJoystickScene.instantiate()
	joystick.use_input_actions = true
	joystick.action_left = "move_left"
	joystick.action_right = "move_right"
	joystick.action_up = "move_forward"
	joystick.action_down = "move_backward"
	# Anchor preset BOTTOM_LEFT then offset inward so the disc sits on
	# the corner. Anchors > raw position math because the joystick scene
	# already has internal anchors of its own and we don't want to fight
	# them.
	joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	joystick.position += Vector2(40, -joystick.size.y - 40)
	layer.add_child(joystick)
	print("[MobileControls] added joystick at %s size=%s" % [joystick.position, joystick.size])

	# 3. Single test button mid-right (action_1 → palette slot 1).
	var btn := TouchScreenButton.new()
	btn.action = "action_1"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 120)
	btn.shape = shape
	btn.shape_centered = true
	# Position in OS pixel coords (same as banner above).
	var v := get_viewport().get_visible_rect().size
	btn.position = Vector2(v.x - 100, v.y * 0.5)
	# Visible body
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.corner_radius_top_left = 60
	sb.corner_radius_top_right = 60
	sb.corner_radius_bottom_left = 60
	sb.corner_radius_bottom_right = 60
	sb.border_width_top = 4
	sb.border_width_bottom = 4
	sb.border_width_left = 4
	sb.border_width_right = 4
	sb.border_color = Color(1, 1, 1, 1)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(120, 120)
	p.position = Vector2(-60, -60)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(p)
	var lbl := Label.new()
	lbl.text = "BTN"
	lbl.size = Vector2(120, 120)
	lbl.position = Vector2(-60, -60)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	layer.add_child(btn)
	print("[MobileControls] added test button at %s viewport=%s" % [btn.position, v])

	print("[MobileControls] _ready DONE")
