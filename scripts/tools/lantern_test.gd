extends Node3D
## Lantern test scene (#646) — one room, night rig, the authored lantern
## effects from the stage editor.
##
## Loads s03a_ga1 straight from its GLB, reads the SAME _effects.json the
## field controller's weather pass reads (assets/stages/<sub>/<stage>/lndmd/
## <stage>_effects.json), and spawns each placed effect with the identical
## parameter math as WeatherController._spawn_placed_effect (GPUParticles +
## OmniLight energy = light_intensity × 8, range = light_radius × 2). A
## minimal night environment stands in for TimeManager so the lantern pools
## are the star of the show. Slow auto-orbit; ESC quits.

const STAGE_ID := "s03a_ga1"
const STAGE_GLB := "res://assets/stages/snowfield_a/s03a_ga1/lndmd/s03a_ga1_m.glb"
const EFFECTS_JSON := "res://assets/stages/snowfield_a/s03a_ga1/lndmd/s03a_ga1_effects.json"

# TimeManager's NIGHT preset (scripts/autoloads/time_manager.gd).
const NIGHT_AMBIENT := Color(0.2, 0.25, 0.45)
const NIGHT_AMBIENT_ENERGY := 0.5
const NIGHT_SKY := Color(0.02, 0.02, 0.08)
const NIGHT_MOON_COLOR := Color(0.6, 0.7, 1.0)
const NIGHT_MOON_ENERGY := 0.25

const ORBIT_RADIUS := 38.0
const ORBIT_HEIGHT := 20.0
const ORBIT_SPEED_DEG := 6.0

var _camera: Camera3D
var _orbit_center := Vector3(0, 3, 0)
var _glow_dot_tex: ImageTexture


func _ready() -> void:
	_build_environment()
	_load_stage()
	var count := _spawn_effects_from_json()
	print("[LanternTest] %s ready — %d lantern effects from %s" % [STAGE_ID, count, EFFECTS_JSON])


func _process(_delta: float) -> void:
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if _camera:
		var angle := Time.get_ticks_msec() / 1000.0 * deg_to_rad(ORBIT_SPEED_DEG)
		_camera.position = _orbit_center + Vector3(
			cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(angle) * ORBIT_RADIUS)
		_camera.look_at(_orbit_center)


func _build_environment() -> void:
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 600.0
	_camera.position = Vector3(ORBIT_RADIUS, ORBIT_HEIGHT, 0)
	add_child(_camera)
	_camera.make_current()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NIGHT_AMBIENT
	env.ambient_light_energy = NIGHT_AMBIENT_ENERGY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = NIGHT_MOON_COLOR
	moon.light_energy = NIGHT_MOON_ENERGY
	moon.rotation_degrees = Vector3(-40, 30, 0)
	add_child(moon)


func _load_stage() -> void:
	var packed := load(STAGE_GLB) as PackedScene
	if packed == null:
		push_error("[LanternTest] failed to load %s" % STAGE_GLB)
		return
	var map_root := packed.instantiate() as Node3D
	map_root.name = "Map"
	add_child(map_root)


func _spawn_effects_from_json() -> int:
	if not FileAccess.file_exists(EFFECTS_JSON):
		push_error("[LanternTest] missing %s" % EFFECTS_JSON)
		return 0
	var file := FileAccess.open(EFFECTS_JSON, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[LanternTest] failed to parse %s: %s" % [EFFECTS_JSON, json.get_error_message()])
		return 0
	var count := 0
	for effect in (json.data as Dictionary).get("effects", []):
		if str(effect.get("category", "")) == "placed":
			_spawn_placed_effect(effect)
			count += 1
	return count


## Mirrors WeatherController._spawn_placed_effect (scripts/3d/field/
## weather_controller.gd) — same parameter mapping, so what reads well here
## reads well in the field.
func _spawn_placed_effect(effect: Dictionary) -> void:
	var pos_arr: Array = effect.get("position", [0, 0, 0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var color_arr: Array = effect.get("color", [1, 1, 1])
	var color := Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
	var p_count: int = int(effect.get("count", 10))
	var radius: float = float(effect.get("radius", 1.0))
	var height: float = float(effect.get("height", 5.0))
	var speed: float = float(effect.get("speed", 1.0))
	var light_intensity: float = float(effect.get("light_intensity", 0.0))
	var light_radius: float = float(effect.get("light_radius", 5.0))
	var effect_type := str(effect.get("type", "spores"))

	var root := Node3D.new()
	root.name = "StageEffect_%s" % effect_type
	root.position = pos
	add_child(root)

	var particles := GPUParticles3D.new()
	particles.name = "%sParticles" % effect_type.capitalize()
	particles.amount = p_count
	particles.lifetime = height / maxf(speed, 0.1)
	particles.visibility_aabb = AABB(
		Vector3(-radius, 0, -radius), Vector3(radius * 2, height, radius * 2))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = speed * 0.7
	mat.initial_velocity_max = speed * 1.3
	mat.gravity = Vector3(0, 0, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	mat.scale_min = 1.0
	mat.scale_max = 2.0
	mat.color = color
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.15, Color(color.r, color.g, color.b, 1.0))
	gradient.add_point(0.7, Color(color.r, color.g, color.b, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	mat.color_ramp = ramp
	particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = color
	quad_mat.albedo_texture = _get_glow_dot_texture()
	quad_mat.emission_enabled = true
	quad_mat.emission = color
	quad_mat.emission_energy_multiplier = 3.0
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mat.no_depth_test = true
	quad.material = quad_mat
	particles.draw_pass_1 = quad
	root.add_child(particles)

	if light_intensity > 0:
		var light := OmniLight3D.new()
		light.name = "LanternLight"
		light.light_color = color
		light.light_energy = light_intensity * 8.0
		light.omni_range = light_radius * 2.0
		light.omni_attenuation = 0.8
		root.add_child(light)


func _get_glow_dot_texture() -> ImageTexture:
	if _glow_dot_tex:
		return _glow_dot_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_r := size / 2.0
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center) / max_r
			var alpha: float = clampf(1.0 - _smoothstep(0.0, 1.0, dist), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_glow_dot_tex = ImageTexture.create_from_image(img)
	return _glow_dot_tex


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
