class_name WeatherController
extends RefCounted

## Weather + stage-effects + embedded-light handling, extracted from
## ValleyFieldController.
##
## Holds a back-reference to the controller (`_c`) and delegates all
## controller-state access through it. Behavior is identical to the original
## inline implementation — this is a relocation refactor, not a logic change.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

## Cache for stage effects JSON (keyed by stage_id, null = no file).
static var _stage_effects_cache: Dictionary = {}

## Cached radial gradient texture for spore particles.
static var _glow_dot_tex: ImageTexture = null

## Back-reference to the ValleyFieldController that owns this controller.
var _c


func _init(controller) -> void:
	_c = controller


func _spawn_weather() -> void:
	var weather: String = str(SessionManager.get_session().get("weather", ""))
	if weather.is_empty():
		return
	var stage_id: String = str(_c._current_cell.get("stage_id", ""))
	if _c._is_indoor_stage(stage_id):
		print("[ValleyField] Weather: skipping %s (indoor stage %s)" % [weather, stage_id])
		return
	if weather == "snow":
		_c._weather_node = GPUParticles3D.new()
		_c._weather_node.name = "WeatherSnow"
		_c._weather_node.amount = 300
		_c._weather_node.lifetime = 4.0
		# Large local AABB so the snow volume is always considered visible
		# regardless of where the player is within the room. Without this, the
		# particle system can freeze until the camera moves.
		_c._weather_node.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
		# Force deterministic simulation; default (fixed_fps=0, interpolate=true)
		# can freeze the particle sim until something invalidates the transform.
		_c._weather_node.fixed_fps = 30
		_c._weather_node.interpolate = false

		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, -1, 0)
		mat.spread = 10.0
		mat.initial_velocity_min = 2.0
		mat.initial_velocity_max = 3.5
		mat.gravity = Vector3(0.3, -0.5, 0.1)
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(20, 0.5, 20)
		mat.angle_min = 0.0
		mat.angle_max = 360.0
		mat.angular_velocity_min = -30.0
		mat.angular_velocity_max = 30.0
		mat.scale_min = 0.6
		mat.scale_max = 1.4
		mat.damping_min = 0.2
		mat.damping_max = 0.5
		_c._weather_node.process_material = mat

		var quad := QuadMesh.new()
		quad.size = Vector2(0.08, 0.08)
		var quad_mat := StandardMaterial3D.new()
		quad_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
		quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = quad_mat
		_c._weather_node.draw_pass_1 = quad

		_c._weather_node.preprocess = 4.0
		_c._weather_node.position.y = 8.0
		_c.player.add_child(_c._weather_node)
		# Defer a restart after the player transform has settled and the render
		# loop has had a chance to start. Without this, snow stays frozen until
		# the player or camera first moves.
		_kick_weather()
		print("[ValleyField] Weather: snow particles attached to player")


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
	var count: int = int(effect.get("count", 10))
	var radius: float = float(effect.get("radius", 1.0))
	var height: float = float(effect.get("height", 5.0))
	var speed: float = float(effect.get("speed", 1.0))
	var light_intensity: float = float(effect.get("light_intensity", 0.0))
	var light_radius: float = float(effect.get("light_radius", 5.0))

	var effect_type: String = str(effect.get("type", "spores"))

	var root := Node3D.new()
	root.name = "StageEffect_%s" % effect_type
	root.position = pos
	_c._map_root.add_child(root)

	var particles := GPUParticles3D.new()
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

	# Point light for ambient glow
	if light_intensity > 0:
		var light := OmniLight3D.new()
		light.name = "SporeLight"
		light.light_color = color
		light.light_energy = light_intensity * 8.0
		light.omni_range = light_radius * 2.0
		light.omni_attenuation = 0.8
		light.shadow_enabled = false
		light.position = Vector3(0, 1.5, 0)
		root.add_child(light)
		print("[StageEffect] Spore light at %s energy=%.1f range=%.1f" % [pos, light.light_energy, light_radius])


static func _get_glow_dot_texture() -> ImageTexture:
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
