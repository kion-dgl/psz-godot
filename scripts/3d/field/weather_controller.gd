class_name WeatherController
extends RefCounted

## Weather + stage-effects + embedded-light handling, extracted from
## ValleyFieldController.
##
## Holds a back-reference to the controller (`_c`) and delegates all
## controller-state access through it. Behavior is identical to the original
## inline implementation — this is a relocation refactor, not a logic change.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")

## Cache for stage effects JSON (keyed by stage_id, null = no file).
static var _stage_effects_cache: Dictionary = {}

## Cached radial gradient texture for spore particles.
static var _glow_dot_tex: ImageTexture = null

## Back-reference to the ValleyFieldController that owns this controller.
var _c


func _init(controller) -> void:
	_c = controller


func _spawn_weather() -> void:
	# Weather rides the field slot row (#655, unifying with #609's per-area
	# ask): a quest-authored session weather key overrides, otherwise the
	# area's slot row carries it (the snowfield's snow, the valley's sand).
	# Indoor stages skip.
	var weather: String = FieldSlotTableScript.resolve_weather(
		str(SessionManager.get_session().get("weather", "")), _c._slot)
	if weather.is_empty():
		return
	var stage_id: String = str(_c._current_cell.get("stage_id", ""))
	if _c._is_indoor_stage(stage_id):
		print("[ValleyField] Weather: skipping %s (indoor stage %s)" % [weather, stage_id])
		return
	var node := build_weather_node(weather)
	if not node:
		return
	_c._weather_node = node
	_c.player.add_child(_c._weather_node)
	# Defer a restart after the player transform has settled and the render
	# loop has had a chance to start. Without this, particles stay frozen
	# until the player or camera first moves.
	_kick_weather()
	print("[ValleyField] Weather: %s particles attached to player" % weather)


## The fully-configured weather particle node for a key (""-ish keys → null).
## Static + shared so the walk labs preview exactly what spawns in-field.
static func build_weather_node(weather: String) -> GPUParticles3D:
	if weather == "snow":
		return _build_snow_node()
	if weather == "sand":
		return _build_sand_node()
	if weather == "rain":
		return _build_rain_node()
	return null


static func _build_snow_node() -> GPUParticles3D:
	var snow := GPUParticles3D.new()
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	snow.name = "WeatherSnow"
	snow.amount = 300
	snow.lifetime = 4.0
	# Large local AABB so the snow volume is always considered visible
	# regardless of where the player is within the room. Without this, the
	# particle system can freeze until the camera moves.
	snow.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
	# Force deterministic simulation; default (fixed_fps=0, interpolate=true)
	# can freeze the particle sim until something invalidates the transform.
	snow.fixed_fps = 30
	snow.interpolate = false

	var snow_mat := ParticleProcessMaterial.new()
	snow_mat.direction = Vector3(0, -1, 0)
	snow_mat.spread = 10.0
	snow_mat.initial_velocity_min = 2.0
	snow_mat.initial_velocity_max = 3.5
	snow_mat.gravity = Vector3(0.3, -0.5, 0.1)
	snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_mat.emission_box_extents = Vector3(20, 0.5, 20)
	snow_mat.angle_min = 0.0
	snow_mat.angle_max = 360.0
	snow_mat.angular_velocity_min = -30.0
	snow_mat.angular_velocity_max = 30.0
	snow_mat.scale_min = 0.6
	snow_mat.scale_max = 1.4
	snow_mat.damping_min = 0.2
	snow_mat.damping_max = 0.5
	snow.process_material = snow_mat

	var snow_quad := QuadMesh.new()
	snow_quad.size = Vector2(0.08, 0.08)
	var snow_quad_mat := StandardMaterial3D.new()
	snow_quad_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
	snow_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	snow_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	snow_quad.material = snow_quad_mat
	snow.draw_pass_1 = snow_quad

	snow.preprocess = 4.0
	snow.position.y = 8.0
	return snow


## The valley's blowing dust (#648): unlike snow's fall, sand drifts
## horizontally through a low band, skimmed along the ground — a haze
## the player walks through, not weather they stand under.
static func _build_sand_node() -> GPUParticles3D:
	var sand := GPUParticles3D.new()
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sand.name = "WeatherSand"
	sand.amount = 240
	sand.lifetime = 5.0
	sand.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
	sand.fixed_fps = 30
	sand.interpolate = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1.0, -0.06, 0.35)
	mat.spread = 25.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 5.5
	mat.gravity = Vector3(0, -0.3, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(22, 1.5, 22)
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.angular_velocity_min = -40.0
	mat.angular_velocity_max = 40.0
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	mat.damping_min = 0.1
	mat.damping_max = 0.3
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	mat.turbulence_noise_scale = 2.0
	sand.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = Color(0.86, 0.73, 0.52, 0.45)
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = quad_mat
	sand.draw_pass_1 = quad

	sand.preprocess = 4.0
	sand.position.y = 3.0
	return sand


## The wetlands' drizzle (#649): the original's fall (~8u/s blue-gray
## streaks on FIXED_Y billboards through the volume above the player),
## taken to a LIGHT drizzle on the kion read-outs — the E stages' baked
## rainbow (s02_0_niji) reads only under soft rain and a hung sun.
## Slower than a storm but unmistakably falling, unlike snow's float or
## sand's drift; a plain particle billboard would pin the streak flat to
## the screen at glancing angles and read as fog.
static func _build_rain_node() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.name = "WeatherRain"
	rain.amount = 160
	rain.lifetime = 1.5
	rain.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
	rain.fixed_fps = 30
	rain.interpolate = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.12, -1.0, 0.05)
	mat.spread = 6.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 8.0
	mat.gravity = Vector3.ZERO
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 0.4, 25)
	mat.scale_min = 0.8
	mat.scale_max = 1.25
	rain.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.35)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = Color(0.5, 0.6, 0.8, 0.22)
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = quad_mat
	rain.draw_pass_1 = quad

	rain.preprocess = 4.0
	rain.position.y = 12.0
	return rain


func _kick_weather() -> void:
	# Wait a couple frames so the player transform is fully committed, then
	# restart the particle system. preprocess runs again on restart and the
	# snow appears already falling.
	await _c.get_tree().process_frame
	await _c.get_tree().process_frame
	if is_instance_valid(_c._weather_node):
		_c._weather_node.restart()


func _strip_embedded_lights(node: Node) -> void:
	## Remove any lights or environments baked into GLB models so the scene-level
	## WorldEnvironment + DirectionalLight3D (controlled by TimeManager) are the
	## sole authority on lighting.
	var to_remove: Array[Node] = []
	_collect_embedded_lights(node, to_remove)
	for n in to_remove:
		n.queue_free()


func _collect_embedded_lights(node: Node, out: Array[Node]) -> void:
	if node is DirectionalLight3D or node is OmniLight3D or node is SpotLight3D or node is WorldEnvironment:
		out.append(node)
		return
	for child in node.get_children():
		_collect_embedded_lights(child, out)


func _spawn_stage_effects(stage_id: String) -> void:
	# Check cache first
	if _stage_effects_cache.has(stage_id):
		var cached: Variant = _stage_effects_cache[stage_id]
		if cached == null:
			return
		_apply_stage_effects(cached as Dictionary, stage_id)
		return

	# Look for JSON alongside the stage GLB
	var area_id: String = SessionManager.get_current_area_id()
	var area_cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, GridGenerator.AREA_CONFIG["gurhacia"])
	var subfolder: String = _c._get_stage_subfolder(stage_id, area_cfg["folder"])
	var json_path := "res://assets/stages/%s/%s/lndmd/%s_effects.json" % [subfolder, stage_id, stage_id]

	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data: Dictionary = json.data as Dictionary
				_stage_effects_cache[stage_id] = data
				_apply_stage_effects(data, stage_id)
				return
			else:
				push_error("[ValleyField] Failed to parse %s: %s" % [json_path, json.get_error_message()])
	_stage_effects_cache[stage_id] = null


func _apply_stage_effects(data: Dictionary, stage_id: String) -> void:
	var effects: Array = data.get("effects", [])
	var count := 0
	for effect in effects:
		var category: String = str(effect.get("category", ""))
		if category == "placed":
			_spawn_placed_effect(effect)
			count += 1
	if count > 0:
		print("[ValleyField] Spawned %d stage effects for %s" % [count, stage_id])


func _spawn_placed_effect(effect: Dictionary) -> void:
	var pos_arr: Array = effect.get("position", [0, 0, 0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var color_arr: Array = effect.get("color", [1, 1, 1])
	var color := Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))

	var effect_type: String = str(effect.get("type", "spores"))

	# Plain light (#636/#657): an omni with no particle footprint — the s03b
	# cave anchors (water pools, mushroom clusters).
	if effect_type == "light":
		_spawn_plain_light(effect, pos, color)
		return

	var count: int = int(effect.get("count", 10))
	var radius: float = float(effect.get("radius", 1.0))
	var height: float = float(effect.get("height", 5.0))
	var speed: float = float(effect.get("speed", 1.0))
	var light_intensity: float = float(effect.get("light_intensity", 0.0))
	var light_radius: float = float(effect.get("light_radius", 5.0))

	var root := Node3D.new()
	root.name = "StageEffect_%s" % effect_type
	root.position = pos
	_c._map_root.add_child(root)

	var particles := GPUParticles3D.new()
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.name = "%sParticles" % effect_type.capitalize()
	particles.amount = count
	particles.lifetime = height / maxf(speed, 0.1)
	particles.visibility_aabb = AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2, height, radius * 2))

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
	# Fade in then out over lifetime
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.15, Color(color.r, color.g, color.b, 1.0))
	gradient.add_point(0.7, Color(color.r, color.g, color.b, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	mat.color_ramp = ramp
	particles.process_material = mat

	# Draw pass — soft glowing dot using radial gradient texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = color
	quad_mat.albedo_texture = create_glow_dot_texture()
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
		_attach_spore_light(root, pos, color, light_intensity, light_radius)


## Plain placed light (#636/#657): an omni with no particle footprint.
## Inverse-square 2.0 like every placed light; intensity rides the authored
## value directly (the ×12 spore multiplier is a punch-through-ambient
## correction specific to the bright A-night's lantern pools).
func _spawn_plain_light(effect: Dictionary, pos: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.name = "AnchorLight"
	light.light_color = color
	light.light_energy = float(effect.get("intensity", 1.0))
	light.omni_range = float(effect.get("radius", 6.0))
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.position = pos
	_c._map_root.add_child(light)


func _attach_spore_light(root: Node3D, pos: Vector3, color: Color,
		light_intensity: float, light_radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = "SporeLight"
	light.light_color = color
	# 12×: playtest wanted the lantern pools to punch through the bright
	# night ambient (1.5) — 8× read as a faint tint on the snow.
	light.light_energy = light_intensity * 12.0
	light.omni_range = light_radius * 2.0
	# 2.0 is true inverse-square (docs: class_omnilight3d). The old 0.8
	# held near-full brightness across the whole range and cut to zero at
	# the edge — lights read binary (bright-or-black) instead of falling
	# off (#646).
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.5, 0)
	root.add_child(light)
	print("[StageEffect] Spore light at %s energy=%.1f range=%.1f" % [pos, light.light_energy, light_radius])


## Soft radial glow-dot texture (cached). Public static so tool scenes
## (lantern_test) share it instead of carrying copies (#295).
static func create_glow_dot_texture() -> ImageTexture:
	if _glow_dot_tex:
		return _glow_dot_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_r := size / 2.0
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center) / max_r
			var alpha: float = clampf(1.0 - smoothstep(0.0, 1.0, dist), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_glow_dot_tex = ImageTexture.create_from_image(img)
	return _glow_dot_tex
