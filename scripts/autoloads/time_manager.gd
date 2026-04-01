extends Node
## TimeManager — In-game clock with day/night cycle and lighting control.
## Autoload that tracks time, calculates phase-based lighting, and applies
## it to 3D scenes with WorldEnvironment + DirectionalLight3D.
##
## Stage geometry uses shaded materials with vertex_color_use_as_albedo,
## so DirectionalLight3D + ambient light drive the day/night atmosphere
## directly.  Scene lights (OmniLight3D, SpotLight3D) also affect geometry.

enum Phase { NIGHT, SUNRISE, DAY, SUNSET }

## Clock state
var current_hour: float = 10.0  # Start at 10am (daytime)
var time_speed: float = 1.0     # 1.0 = 1 real sec per game minute (full day in ~24 real min)
var paused: bool = false

## HUD
var _hud_layer: CanvasLayer
var _hud_label: Label
var stage_label: String = ""  # Set by field controller for debug display

## Lighting configs per phase — drives real 3D lighting (no screen tint)
var _configs: Dictionary = {
	Phase.DAY: {
		"sky_top": Color(0.3, 0.55, 0.65),
		"sky_horizon": Color(0.6, 0.7, 0.6),
		"ground_bottom": Color(0.15, 0.12, 0.08),
		"ground_horizon": Color(0.45, 0.42, 0.35),
		"ambient_color": Color(0.9, 0.92, 0.88),
		"ambient_energy": 0.9,
		"light_color": Color(1.0, 0.98, 0.94),
		"light_energy": 0.6,
		"light_pitch": -45.0,
	},
	Phase.SUNSET: {
		"sky_top": Color(0.2, 0.1, 0.3),
		"sky_horizon": Color(0.95, 0.45, 0.15),
		"ground_bottom": Color(0.15, 0.08, 0.04),
		"ground_horizon": Color(0.6, 0.3, 0.1),
		"ambient_color": Color(0.85, 0.5, 0.2),
		"ambient_energy": 0.55,
		"light_color": Color(1.0, 0.5, 0.1),
		"light_energy": 0.7,
		"light_pitch": -12.0,
	},
	Phase.NIGHT: {
		"sky_top": Color(0.02, 0.02, 0.08),
		"sky_horizon": Color(0.05, 0.08, 0.15),
		"ground_bottom": Color(0.02, 0.02, 0.04),
		"ground_horizon": Color(0.05, 0.06, 0.1),
		"ambient_color": Color(0.2, 0.25, 0.45),
		"ambient_energy": 0.3,
		"light_color": Color(0.6, 0.7, 1.0),
		"light_energy": 0.2,
		"light_pitch": -40.0,
	},
	Phase.SUNRISE: {
		"sky_top": Color(0.25, 0.35, 0.55),
		"sky_horizon": Color(0.9, 0.55, 0.3),
		"ground_bottom": Color(0.12, 0.1, 0.08),
		"ground_horizon": Color(0.5, 0.35, 0.25),
		"ambient_color": Color(0.75, 0.6, 0.45),
		"ambient_energy": 0.55,
		"light_color": Color(1.0, 0.7, 0.4),
		"light_energy": 0.5,
		"light_pitch": -12.0,
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
	_hud_label.offset_left = -140
	_hud_label.offset_right = 140
	_hud_label.offset_top = 8
	_hud_label.offset_bottom = 32
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_hud_layer.add_child(_hud_label)
	_hud_layer.visible = false


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
	elif current_hour >= 5.0 and current_hour < 6.0:
		# Early sunrise: NIGHT → SUNRISE
		var t: float = current_hour - 5.0
		return _lerp_config(_configs[Phase.NIGHT], _configs[Phase.SUNRISE], t)
	elif current_hour >= 6.0 and current_hour < 7.0:
		# Late sunrise: SUNRISE → DAY
		var t: float = current_hour - 6.0
		return _lerp_config(_configs[Phase.SUNRISE], _configs[Phase.DAY], t)
	elif current_hour >= 7.0 and current_hour < 17.0:
		return _configs[Phase.DAY].duplicate()
	elif current_hour >= 17.0 and current_hour < 19.0:
		# Early sunset: DAY → SUNSET
		var t: float = (current_hour - 17.0) / 2.0
		return _lerp_config(_configs[Phase.DAY], _configs[Phase.SUNSET], t)
	else:
		# Late sunset: SUNSET → NIGHT (19:00–21:00)
		var t: float = (current_hour - 19.0) / 2.0
		return _lerp_config(_configs[Phase.SUNSET], _configs[Phase.NIGHT], t)


func show_hud(visible: bool = true) -> void:
	_hud_layer.visible = visible


func apply_to_scene(env: Environment, sky_mat: ProceduralSkyMaterial, light: DirectionalLight3D, moonlight: DirectionalLight3D = null) -> void:
	_hud_layer.visible = DebugConfig.show_time_room
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

	# Moonlight — cool fill from opposite side of sun, fades in at night
	if moonlight:
		var moon_energy: float = _get_moonlight_energy()
		moonlight.light_energy = moon_energy
		moonlight.visible = moon_energy > 0.01
		if moonlight.visible:
			moonlight.rotation_degrees = Vector3(cfg["light_pitch"], light.rotation_degrees.y + 180.0, 0)


func is_dark() -> bool:
	## Returns true when it's dark enough to show entity glow lights (sunset through sunrise).
	return current_hour >= 19.0 or current_hour < 6.0


func _get_moonlight_energy() -> float:
	## Returns moonlight intensity: 0 during day, ramps up at sunset, full at night,
	## ramps down at sunrise.
	if current_hour >= 21.0 or current_hour < 5.0:
		return 0.35  # Full moonlight
	elif current_hour >= 17.0 and current_hour < 21.0:
		# Sunset: fade in from 0 → 0.35
		var t: float = (current_hour - 17.0) / 4.0
		return lerpf(0.0, 0.35, t)
	elif current_hour >= 5.0 and current_hour < 7.0:
		# Sunrise: fade out from 0.35 → 0
		var t: float = (current_hour - 5.0) / 2.0
		return lerpf(0.35, 0.0, t)
	return 0.0  # Day


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
	if stage_label.is_empty():
		_hud_label.text = "%02d:%02d - %s" % [h, m, phase]
	else:
		_hud_label.text = "%02d:%02d - %s  [%s]" % [h, m, phase, stage_label]


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
