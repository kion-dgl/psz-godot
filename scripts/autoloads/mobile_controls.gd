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
const JOYSTICK_INSET   := Vector2(140, 160)   # from bottom-left, fixed-mode centre
const ACTION_INSET     := Vector2(180, 180)   # from bottom-right (centre of diamond)
const ACTION_RADIUS    := 95                  # button distance from diamond centre
const ACTION_BTN_SIZE  := Vector2(80, 80)
const TOP_BTN_SIZE     := Vector2(110, 48)
const TOP_INSET        := 24

# Persistent settings file. The user can flip this from an options screen
# later — for now we just default ON for any mobile/touchscreen device.
const SETTINGS_PATH := "user://mobile_controls_settings.json"

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
	# Decide whether to activate. ON by default on Android/iOS (regardless of
	# what is_touchscreen_available() reports — it's been flaky on first
	# boot). User can opt out via mobile_controls_settings.json (a future
	# options screen will write that file).
	var is_mobile_platform := OS.has_feature("android") or OS.has_feature("ios")
	var has_touch := DisplayServer.is_touchscreen_available()
	var enabled_by_default := is_mobile_platform or has_touch
	var enabled := _load_setting("enabled", enabled_by_default)
	if not enabled:
		queue_free()
		return
	# Mirror desktop behaviour: emulate touch from mouse so we can sanity-test
	# the overlay on a desktop debug build.
	Input.set_emulate_mouse_from_touch(true)

	print("[MobileControls] activating — platform_mobile=%s touch=%s" % [is_mobile_platform, has_touch])

	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "MobileControls"
	# follow_viewport_enabled keeps the layer in scene coords under canvas_items stretch.
	_layer.follow_viewport_enabled = true
	add_child(_layer)

	# Wait one frame so the viewport size is settled (especially on first boot
	# where DisplayServer can return 0×0 momentarily).
	await get_tree().process_frame
	var v := get_viewport().get_visible_rect().size
	if v.x < 1 or v.y < 1:
		v = Vector2(1280, 720)  # fallback to project default
	get_viewport().size_changed.connect(_relayout)
	print("[MobileControls] building overlay at viewport size %sx%s" % [v.x, v.y])
	_build(v)

func _build(v: Vector2) -> void:
	# ---- Movement: visible joystick anchored bottom-left ----
	# Keep this dead simple: instantiate the addon scene with its DEFAULTS
	# (FIXED mode, ALWAYS visible) and just translate the whole Control so
	# the visible base sits in the bottom-left corner. No size overrides,
	# no Base reparenting — the previous build's tweaks broke the addon's
	# internal _base_default_position capture and apparently took the rest
	# of the scene tree down with it.
	_joystick = VirtualJoystickScene.instantiate()
	_joystick.use_input_actions = true
	_joystick.action_left = "move_left"
	_joystick.action_right = "move_right"
	_joystick.action_up = "move_forward"
	_joystick.action_down = "move_backward"
	# Anchor in scene coords. The joystick's hit area is whatever Control
	# size the .tscn ships with (typically a few hundred px across).
	_joystick.position = Vector2(JOYSTICK_INSET.x, v.y - JOYSTICK_INSET.y - 90)
	_layer.add_child(_joystick)

	# ---- A/B/X/Y diamond bottom-right (SNES layout) ----
	# A right = interact, B bottom = dodge, X top = quick weapon (menu),
	# Y left = action_palette slot 1.
	var diamond_centre := Vector2(v.x - ACTION_INSET.x, v.y - ACTION_INSET.y)
	_add_button("interact",      "A", diamond_centre + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_button("dodge",         "B", diamond_centre + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("quick_weapon",  "X", diamond_centre + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_button("action_1",      "Y", diamond_centre + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top row: START centre, II right, LOG left ----
	var start_pos := Vector2(v.x * 0.5, TOP_INSET + TOP_BTN_SIZE.y * 0.5)
	_add_button("start",         "START", start_pos,                                                                          Vector2(140, 50))
	_add_button("pause",         "II",    Vector2(v.x - TOP_BTN_SIZE.x * 0.5 - TOP_INSET, TOP_INSET + TOP_BTN_SIZE.y * 0.5), TOP_BTN_SIZE)
	_add_button("quest_log",     "LOG",   Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET,        TOP_INSET + TOP_BTN_SIZE.y * 0.5), TOP_BTN_SIZE)

	# ---- Second row: PAL (palette swap) under LOG ----
	var second_y := TOP_INSET + TOP_BTN_SIZE.y + 12 + TOP_BTN_SIZE.y * 0.5
	_add_button("palette_swap",  "PAL",   Vector2(TOP_BTN_SIZE.x * 0.5 + TOP_INSET, second_y), TOP_BTN_SIZE)

func _relayout() -> void:
	# Tear down + rebuild on resize. Cheap — only a handful of nodes.
	for c in _layer.get_children():
		c.queue_free()
	_build(get_viewport().get_visible_rect().size)

func _add_button(action: String, label: String, centre: Vector2, size: Vector2) -> void:
	# White outlined circle/pill with a centred label. Transparent fill so
	# what's behind the button stays visible.
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
	sb.bg_color = Color(0, 0, 0, 0)        # fully transparent fill
	var corner := int(min(size.x, size.y) * 0.5)
	sb.corner_radius_top_left = corner
	sb.corner_radius_top_right = corner
	sb.corner_radius_bottom_left = corner
	sb.corner_radius_bottom_right = corner
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_color = Color(1, 1, 1, 0.85)  # white outline
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = size
	panel.position = -size * 0.5
	# Don't intercept touches — TouchScreenButton needs them.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(panel)

	var lbl := Label.new()
	lbl.text = label
	lbl.size = size
	lbl.position = -size * 0.5
	lbl.add_theme_color_override("font_color", Color.WHITE)
	# Subtle dark drop-shadow so the white text stays readable on bright bg.
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_font_size_override("font_size", int(min(size.x, size.y) * 0.36))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	# Mirror to ui_* if applicable
	if action in ACTION_MIRROR:
		var ui_action: String = ACTION_MIRROR[action]
		btn.pressed.connect(_press_ui.bind(ui_action))
		btn.released.connect(_release_ui.bind(ui_action))

	_layer.add_child(btn)

func _press_ui(ui_action: String) -> void:
	if not _ui_state.get(ui_action, false):
		_dispatch_action(ui_action, true)
		_ui_state[ui_action] = true

func _release_ui(ui_action: String) -> void:
	if _ui_state.get(ui_action, false):
		_dispatch_action(ui_action, false)
		_ui_state[ui_action] = false

# Inject a real InputEventAction so `_input` / `_unhandled_input` listeners
# (which is how Godot UI scenes typically read menu nav) actually receive
# the event. Input.action_press()/action_release() only update the polled
# state — they do NOT dispatch through the input event pipeline, so menus
# that listen via _unhandled_input never see them.
func _dispatch_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

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
		_dispatch_action(ui_action, true)
	elif (not now_active) and was_active:
		_dispatch_action(ui_action, false)

# --- Persistent settings (an options screen will write these later) ---

func _load_setting(key: String, default_value: Variant) -> Variant:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return default_value
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return default_value
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return default_value
	var d: Dictionary = parsed
	if not d.has(key):
		return default_value
	return d[key]

static func set_enabled(enabled: bool) -> void:
	# Call from an options screen: e.g. MobileControls.set_enabled(false)
	# then reload the current scene to apply.
	var d: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				d = parsed
	d["enabled"] = enabled
	var w := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify(d))
		w.close()
