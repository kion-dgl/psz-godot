extends Node
## TimeManager — In-game clock with day/night cycle and lighting control.
## Autoload that tracks time, calculates phase-based lighting, and applies
## it to 3D scenes with WorldEnvironment + DirectionalLight3D.

enum Phase { NIGHT, SUNRISE, DAY, SUNSET }

## Clock state
var current_hour: float = 10.0  # Start at 10am (daytime)
var time_speed: float = 1.0     # 1.0 = 1 real sec per game minute (full day in ~24 real min)
var paused: bool = false

## HUD
var _hud_layer: CanvasLayer
var _hud_label: Label

## Screen tint overlay (multiply blend for day/night atmosphere on unshaded geometry)
var _tint_layer: CanvasLayer
var _tint_rect: ColorRect

## Lighting configs per phase
var _configs: Dictionary = {
	Phase.DAY: {
		"sky_top": Color(0.3, 0.55, 0.65),
		"sky_horizon": Color(0.6, 0.7, 0.6),
		"ground_bottom": Color(0.15, 0.12, 0.08),
		"ground_horizon": Color(0.45, 0.42, 0.35),
		"ambient_color": Color(0.85, 0.9, 0.85),
		"ambient_energy": 0.7,
		"light_color": Color(1.0, 0.98, 0.94),
		"light_energy": 0.8,
		"light_pitch": -45.0,
		"tint": Color(1.0, 1.0, 1.0),
		"player_light": 0.0,
	},
	Phase.SUNSET: {
		"sky_top": Color(0.25, 0.15, 0.35),
		"sky_horizon": Color(0.85, 0.4, 0.2),
		"ground_bottom": Color(0.12, 0.08, 0.1),
		"ground_horizon": Color(0.5, 0.3, 0.2),
		"ambient_color": Color(0.9, 0.6, 0.4),
		"ambient_energy": 0.4,
		"light_color": Color(1.0, 0.4, 0.15),
		"light_energy": 0.5,
		"light_pitch": -10.0,
		"tint": Color(1.0, 0.75, 0.55),
		"player_light": 0.15,
	},
	Phase.NIGHT: {
		"sky_top": Color(0.02, 0.02, 0.08),
		"sky_horizon": Color(0.05, 0.08, 0.15),
		"ground_bottom": Color(0.02, 0.02, 0.04),
		"ground_horizon": Color(0.05, 0.06, 0.1),
		"ambient_color": Color(0.3, 0.35, 0.55),
		"ambient_energy": 0.25,
		"light_color": Color(0.7, 0.8, 1.0),
		"light_energy": 0.3,
		"light_pitch": -40.0,
		"tint": Color(0.25, 0.3, 0.5),
		"player_light": 0.5,
	},
	Phase.SUNRISE: {
		"sky_top": Color(0.25, 0.35, 0.55),
		"sky_horizon": Color(0.9, 0.55, 0.3),
		"ground_bottom": Color(0.12, 0.1, 0.08),
		"ground_horizon": Color(0.5, 0.35, 0.25),
		"ambient_color": Color(0.8, 0.65, 0.5),
		"ambient_energy": 0.4,
		"light_color": Color(1.0, 0.7, 0.4),
		"light_energy": 0.5,
		"light_pitch": -10.0,
		"tint": Color(0.85, 0.75, 0.6),
		"player_light": 0.15,
	},
}


func _ready() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 110
	add_child(_hud_layer)

	_hud_label = Label.new()
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.anchor_left = 0.5
	_hud_label.anchor_right = 0.5
	_hud_label.anchor_top = 0.0
	_hud_label.anchor_bottom = 0.0
	_hud_label.offset_left = -80
	_hud_label.offset_right = 80
	_hud_label.offset_top = 8
	_hud_label.offset_bottom = 32
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_hud_layer.add_child(_hud_label)
	_hud_layer.visible = false

	# Tint overlay — multiply-blended ColorRect for day/night atmosphere.
	# Sits below the HUD but above the 3D scene.
	_tint_layer = CanvasLayer.new()
	_tint_layer.layer = 105
	add_child(_tint_layer)
	_tint_rect = ColorRect.new()
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint_mat := CanvasItemMaterial.new()
	tint_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_tint_rect.material = tint_mat
	_tint_rect.color = Color(1, 1, 1, 1)
	_tint_layer.add_child(_tint_rect)
	_tint_layer.visible = false


func _process(delta: float) -> void:
	if paused:
		return
	current_hour += delta * time_speed / 60.0
	if current_hour >= 24.0:
		current_hour -= 24.0
	_update_hud()


func get_phase() -> String:
	if current_hour >= 21.0 or current_hour < 5.0:
		return "night"
	elif current_hour >= 5.0 and current_hour < 7.0:
		return "sunrise"
	elif current_hour >= 7.0 and current_hour < 17.0:
		return "day"
	else:
		return "sunset"


func get_lighting() -> Dictionary:
	if current_hour >= 21.0 or current_hour < 5.0:
		return _configs[Phase.NIGHT].duplicate()
	elif current_hour >= 5.0 and current_hour < 7.0:
		var t: float = (current_hour - 5.0) / 2.0
		return _lerp_config(_configs[Phase.NIGHT], _configs[Phase.DAY], t)
	elif current_hour >= 7.0 and current_hour < 17.0:
		return _configs[Phase.DAY].duplicate()
	else:
		var t: float = (current_hour - 17.0) / 4.0
		return _lerp_config(_configs[Phase.DAY], _configs[Phase.NIGHT], t)


func show_hud(visible: bool = true) -> void:
	_hud_layer.visible = visible
	_tint_layer.visible = visible


func apply_to_scene(env: Environment, sky_mat: ProceduralSkyMaterial, light: DirectionalLight3D) -> void:
	_hud_layer.visible = true
	_tint_layer.visible = true
	var cfg: Dictionary = get_lighting()

	sky_mat.sky_top_color = cfg["sky_top"]
	sky_mat.sky_horizon_color = cfg["sky_horizon"]
	sky_mat.ground_bottom_color = cfg["ground_bottom"]
	sky_mat.ground_horizon_color = cfg["ground_horizon"]

	env.ambient_light_color = cfg["ambient_color"]
	env.ambient_light_energy = cfg["ambient_energy"]

	light.light_color = cfg["light_color"]
	light.light_energy = cfg["light_energy"]
	light.rotation_degrees.x = cfg["light_pitch"]
	light.shadow_enabled = true

	# Screen-space tint for unshaded stage geometry
	_tint_rect.color = cfg["tint"]


func set_hour(h: float) -> void:
	current_hour = fmod(h, 24.0)
	if current_hour < 0.0:
		current_hour += 24.0


func _lerp_config(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var result := {}
	for key in from:
		var a = from[key]
		var b = to[key]
		if a is Color:
			result[key] = a.lerp(b, t)
		elif a is float:
			result[key] = lerpf(a, b, t)
		else:
			result[key] = b
	return result


func _update_hud() -> void:
	if not _hud_label or not _hud_layer.visible:
		return
	var h: int = int(current_hour) % 24
	var m: int = int(fmod(current_hour, 1.0) * 60.0)
	var phase: String = get_phase().capitalize()
	_hud_label.text = "%02d:%02d - %s" % [h, m, phase]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETRIGHT:
			set_hour(current_hour + 1.0)
			print("[TimeManager] Hour: %.1f  Phase: %s" % [current_hour, get_phase()])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BRACKETLEFT:
			set_hour(current_hour - 1.0)
			print("[TimeManager] Hour: %.1f  Phase: %s" % [current_hour, get_phase()])
			get_viewport().set_input_as_handled()
