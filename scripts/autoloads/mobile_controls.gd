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
#
# Visual: Kenney CC0 input-prompts sprites (Switch face buttons + dpad).
# Joystick comes from the MarcoFazioRandom virtual_joystick add-on.
# When ANY menu is active (start menu / shop overlay / character pick), the
# joystick is hidden and a real + cross dpad takes its place.

extends Node

const VirtualJoystickScene := preload("res://addons/virtual_joystick/virtual_joystick_scene.tscn")

# Kenney sprites (64x64 each, scaled at runtime).
const TEX_BTN_A      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_a.png")
const TEX_BTN_B      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_b.png")
const TEX_BTN_X      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_x.png")
const TEX_BTN_Y      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_y.png")
const TEX_BTN_PLUS   := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_plus.png")
const TEX_BTN_MINUS  := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_minus.png")
const TEX_BTN_HOME   := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_home.png")
const TEX_BTN_L      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_l.png")
const TEX_BTN_R      := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_button_r.png")
const TEX_DPAD_NONE  := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_dpad_none.png")
const TEX_DPAD_UP    := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_dpad_up.png")
const TEX_DPAD_DOWN  := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_dpad_down.png")
const TEX_DPAD_LEFT  := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_dpad_left.png")
const TEX_DPAD_RIGHT := preload("res://assets/kenney_input-prompts/Nintendo Switch/Default/switch_dpad_right.png")

# 1280×720 viewport coords.
const ACTION_INSET     := Vector2(180, 180)   # diamond centre, from bottom-right
const ACTION_RADIUS    := 95
const ACTION_BTN_SIZE  := 96                  # square sprite size (pixels)
const TOP_BTN_SIZE     := 64                  # plus/minus/home in top row
const TOP_INSET        := 24
const SHOULDER_BTN_SIZE := 80

const STICK_DEADZONE := 0.18
const SETTINGS_PATH := "user://mobile_controls.cfg"

# Dpad layout — switch_dpad_none.png is a 64x64 + cross sprite. Scale it up
# big enough that each arm is comfortably thumb-sized. 256 ≈ 4× original.
const DPAD_INSET   := Vector2(180, 180)   # centre, from bottom-left
const DPAD_PX      := 256                 # rendered size
const DPAD_ARM_HALF := 0.32               # arm hit-zone reach as fraction of DPAD_PX

var _layer: CanvasLayer
var _joystick: VirtualJoystick
var _dpad: Node2D
var _dpad_base_sprite: Sprite2D
var _dpad_dir_sprites: Dictionary = {}  # button_index -> Sprite2D
var _last_axis := Vector2.ZERO

# Menu-mode state. Re-evaluated every frame from authoritative sources
# (PsoStartMenu, SceneManager, current scene path) — there is no project-
# wide "menu open" signal so polling is the only reliable way.
var _menu_mode := false

const MENU_SCENES := {
	"res://scenes/2d/character_select.tscn": true,
	"res://scenes/2d/character_create.tscn": true,
}

# Scene paths that count as a "shop" overlay (storage, weapon shop, item
# shop, etc). Matched against SceneManager's overlay stack.
const SHOP_PATH_PREFIXES := [
	"res://scenes/2d/shops/",
	"res://scenes/2d/storage",
]

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
	_refresh_mode()  # initial visibility

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
	# We drive the joystick output ourselves and emit raw left-stick axis
	# events so the project's existing axis bindings light up unmodified.
	_joystick = VirtualJoystickScene.instantiate()
	_joystick.use_input_actions = false
	_joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	_joystick.position += Vector2(40, -40)
	_layer.add_child(_joystick)

	# ---- Dpad bottom-left (menu mode, hidden by default) ----
	_dpad = _build_dpad(v)
	_dpad.visible = false
	_layer.add_child(_dpad)

	# ---- A/B/X/Y diamond bottom-right, Switch face-button sprites ----
	# Diamond layout: A on the right (east), B at bottom (south), X at top
	# (north), Y on the left (west) — matches the SNES face plate.
	var c := Vector2(v.x - ACTION_INSET.x, v.y - ACTION_INSET.y)
	_add_sprite_button(JOY_BUTTON_A, TEX_BTN_A, c + Vector2( ACTION_RADIUS,  0), ACTION_BTN_SIZE)
	_add_sprite_button(JOY_BUTTON_B, TEX_BTN_B, c + Vector2( 0,  ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_sprite_button(JOY_BUTTON_X, TEX_BTN_X, c + Vector2( 0, -ACTION_RADIUS), ACTION_BTN_SIZE)
	_add_sprite_button(JOY_BUTTON_Y, TEX_BTN_Y, c + Vector2(-ACTION_RADIUS,  0), ACTION_BTN_SIZE)

	# ---- Top row: minus | plus(START) | home ----
	var top_y := TOP_INSET + TOP_BTN_SIZE * 0.5
	_add_sprite_button(JOY_BUTTON_BACK,  TEX_BTN_MINUS, Vector2(TOP_BTN_SIZE * 0.5 + TOP_INSET,        top_y), TOP_BTN_SIZE)
	_add_sprite_button(JOY_BUTTON_START, TEX_BTN_PLUS,  Vector2(v.x * 0.5,                              top_y), TOP_BTN_SIZE + 8)
	_add_sprite_button(JOY_BUTTON_GUIDE, TEX_BTN_HOME,  Vector2(v.x - TOP_BTN_SIZE * 0.5 - TOP_INSET,   top_y), TOP_BTN_SIZE)

	# ---- Shoulder row: L1 (PAL) on left, R1 on right ----
	var second_y := top_y + TOP_BTN_SIZE * 0.5 + SHOULDER_BTN_SIZE * 0.5 + 12
	_add_sprite_button(JOY_BUTTON_LEFT_SHOULDER,  TEX_BTN_L, Vector2(SHOULDER_BTN_SIZE * 0.5 + TOP_INSET, second_y), SHOULDER_BTN_SIZE)
	_add_sprite_button(JOY_BUTTON_RIGHT_SHOULDER, TEX_BTN_R, Vector2(v.x - SHOULDER_BTN_SIZE * 0.5 - TOP_INSET, second_y), SHOULDER_BTN_SIZE)

	print("[MobileControls] _build done")

func _add_sprite_button(button_index: int, tex: Texture2D, centre: Vector2, size: float) -> void:
	# TouchScreenButton with a Sprite2D visual (Kenney prompt). Keeps the
	# crisp UI look vs. drawing rounded panels at runtime.
	var btn := TouchScreenButton.new()
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size, size)
	btn.shape = shape
	btn.position = centre

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Kenney sprites are 64x64; scale to requested size.
	var scale_factor := size / 64.0
	sprite.scale = Vector2(scale_factor, scale_factor)
	btn.add_child(sprite)

	btn.pressed.connect(_on_btn_pressed.bind(button_index, sprite))
	btn.released.connect(_on_btn_released.bind(button_index, sprite))
	_layer.add_child(btn)

func _on_btn_pressed(button_index: int, sprite: Sprite2D) -> void:
	sprite.modulate = Color(0.7, 0.9, 1.4)  # tint blue-ish to show press
	_emit_button(button_index, true)

func _on_btn_released(button_index: int, sprite: Sprite2D) -> void:
	sprite.modulate = Color.WHITE
	_emit_button(button_index, false)

func _emit_button(button_index: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button_index
	ev.pressure = 1.0 if pressed else 0.0
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _process(_dt: float) -> void:
	# 1. Mirror joystick output to JoypadMotion left-stick axes.
	if _joystick:
		var out := _joystick.output
		if absf(out.x - _last_axis.x) > 0.02:
			_emit_axis(JOY_AXIS_LEFT_X, out.x if absf(out.x) > STICK_DEADZONE else 0.0)
		if absf(out.y - _last_axis.y) > 0.02:
			_emit_axis(JOY_AXIS_LEFT_Y, out.y if absf(out.y) > STICK_DEADZONE else 0.0)
		_last_axis = out

	# 2. Re-evaluate menu mode every frame. Cheap (a handful of flag reads)
	#    and the only reliable detector — there's no global "menu open" signal.
	var menu := _is_menu_active()
	if menu != _menu_mode:
		_menu_mode = menu
		print("[MobileControls] mode → %s" % ("DPAD" if menu else "STICK"))
		_refresh_mode()

func _is_menu_active() -> bool:
	# PSO start menu open?
	var pso := get_node_or_null("/root/PsoStartMenu")
	if pso and pso.has_method("is_open") and pso.is_open():
		return true
	# Any overlay scene pushed (shops + storage)?
	var sm := get_node_or_null("/root/SceneManager")
	if sm and sm.has_method("can_pop") and sm.can_pop():
		return true
	# Pause menu via GameState?
	var gs := get_node_or_null("/root/GameState")
	if gs and "is_pause_menu_open" in gs and gs.is_pause_menu_open:
		return true
	# Character select / create scenes?
	var scene := get_tree().current_scene
	if scene:
		var p := scene.scene_file_path
		if p in MENU_SCENES:
			return true
	return false

func _emit_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)

# ---- Dpad ------------------------------------------------------------------

func _build_dpad(v: Vector2) -> Node2D:
	# Switch dpad sprite (already a + cross) as the visual base, with one
	# directional highlight sprite per arm (initially hidden) layered on top.
	# A TouchScreenButton overlays each arm to dispatch JOY_BUTTON_DPAD_*.
	var root := Node2D.new()
	var c := Vector2(DPAD_INSET.x, v.y - DPAD_INSET.y)
	root.position = c

	_dpad_base_sprite = Sprite2D.new()
	_dpad_base_sprite.texture = TEX_DPAD_NONE
	_dpad_base_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var s := DPAD_PX / 64.0
	_dpad_base_sprite.scale = Vector2(s, s)
	root.add_child(_dpad_base_sprite)

	# Directional highlight overlays — same dimensions, hidden by default.
	for entry in [
		[JOY_BUTTON_DPAD_UP,    TEX_DPAD_UP],
		[JOY_BUTTON_DPAD_DOWN,  TEX_DPAD_DOWN],
		[JOY_BUTTON_DPAD_LEFT,  TEX_DPAD_LEFT],
		[JOY_BUTTON_DPAD_RIGHT, TEX_DPAD_RIGHT],
	]:
		var hi := Sprite2D.new()
		hi.texture = entry[1]
		hi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		hi.scale = Vector2(s, s)
		hi.visible = false
		root.add_child(hi)
		_dpad_dir_sprites[entry[0]] = hi

	# Hit zones — the + cross is symmetric so each arm is a third of the
	# sprite wide and ~half tall. Position them in the dpad root's local
	# coords so they follow the sprite.
	var arm := DPAD_PX * DPAD_ARM_HALF       # arm extent from centre
	var thick := DPAD_PX * 0.30              # arm thickness
	root.add_child(_make_arm(JOY_BUTTON_DPAD_UP,    Vector2( 0, -arm * 0.5), Vector2(thick, arm)))
	root.add_child(_make_arm(JOY_BUTTON_DPAD_DOWN,  Vector2( 0,  arm * 0.5), Vector2(thick, arm)))
	root.add_child(_make_arm(JOY_BUTTON_DPAD_LEFT,  Vector2(-arm * 0.5, 0),  Vector2(arm, thick)))
	root.add_child(_make_arm(JOY_BUTTON_DPAD_RIGHT, Vector2( arm * 0.5, 0),  Vector2(arm, thick)))
	return root

func _make_arm(button_index: int, centre_local: Vector2, size: Vector2) -> TouchScreenButton:
	var btn := TouchScreenButton.new()
	btn.shape_centered = true
	var shape := RectangleShape2D.new()
	shape.size = size
	btn.shape = shape
	btn.position = centre_local
	btn.pressed.connect(_on_dpad_pressed.bind(button_index))
	btn.released.connect(_on_dpad_released.bind(button_index))
	return btn

func _on_dpad_pressed(button_index: int) -> void:
	if button_index in _dpad_dir_sprites:
		_dpad_dir_sprites[button_index].visible = true
	_emit_button(button_index, true)

func _on_dpad_released(button_index: int) -> void:
	if button_index in _dpad_dir_sprites:
		_dpad_dir_sprites[button_index].visible = false
	_emit_button(button_index, false)

# ---- Mode swap -------------------------------------------------------------

func _refresh_mode() -> void:
	if _joystick:
		_joystick.visible = not _menu_mode
	if _dpad:
		_dpad.visible = _menu_mode

# ---- Options-screen toggle -------------------------------------------------

static func set_enabled(enabled: bool) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string("on" if enabled else "off")
		f.close()
