extends RefCounted
## Low-budget cave life shared by gameplay and the walk lab. No particle lights.
const ROOT := "res://data/stage_configs/makara-particles/"
static var _leaf_texture: ImageTexture
static var _mote_texture: ImageTexture


static func falling() -> GPUParticles3D:
	var particles := _emitter("MakaraFallingLeaves", 96, 12.0, false)
	particles.position.y = 7.0
	particles.visibility_aabb = AABB(Vector3(-15, -14, -15), Vector3(30, 18, 30))
	var mat := particles.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(11, 1, 11)
	mat.direction = Vector3(0.15, -1, 0.08)
	mat.initial_velocity_min = 0.45
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0.015, -0.015, 0)
	mat.angular_velocity_min = -65.0
	mat.angular_velocity_max = 65.0
	return particles


static func spawn_floor(root: Node3D, stage_id: String) -> void:
	if not stage_id.begins_with("s04a_") and not stage_id.begins_with("s04b_"):
		return
	var path := ROOT + stage_id + ".json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return
	var points: Array = data.get("points", [])
	if points.is_empty():
		return
	var particles := _emitter("MakaraRisingFlowers", 64, 6.0, true)
	var tex := Image.create(points.size(), 1, false, Image.FORMAT_RGBF)
	var bounds := AABB(Vector3(points[0][0], points[0][1], points[0][2]), Vector3.ZERO)
	for i in points.size():
		var p: Array = points[i]
		tex.set_pixel(i, 0, Color(p[0], p[1] + 0.08, p[2]))
		bounds = bounds.expand(Vector3(p[0], p[1], p[2]))
	particles.visibility_aabb = bounds.grow(4.0)
	var mat := particles.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	mat.emission_point_texture = ImageTexture.create_from_image(tex)
	mat.emission_point_count = points.size()
	mat.direction = Vector3.UP
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.45
	mat.gravity = Vector3.ZERO
	root.add_child(particles)
	particles.restart()
	print("[Makara] 64 rising particles on %s hana2 patches" % stage_id)


static func _emitter(node_name: String, count: int, life: float, rising: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = count
	particles.lifetime = life
	particles.preprocess = life
	particles.fixed_fps = 20
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ParticleProcessMaterial.new()
	mat.spread = 15.0
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.scale_min = 0.65
	mat.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color.WHITE)
	fade.add_point(0.65, Color.WHITE)
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	particles.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.13) if rising else Vector2(0.1, 0.18)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.vertex_color_use_as_albedo = true
	draw.albedo_color = Color(1.0, 0.3, 0.38, 0.65)
	draw.albedo_texture = _texture(rising)
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = draw
	particles.draw_pass_1 = quad
	return particles


static func _texture(rising: bool) -> ImageTexture:
	var cached := _mote_texture if rising else _leaf_texture
	if cached != null:
		return cached
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / 16.0 - Vector2.ONE
			# A soft round rising mote, or a tapered leaf silhouette.
			var edge := uv.length() if rising else absf(uv.x) + uv.y * uv.y
			var alpha := clampf((1.0 - edge) * (1.5 if rising else 5.0), 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	cached = ImageTexture.create_from_image(image)
	if rising:
		_mote_texture = cached
	else:
		_leaf_texture = cached
	return cached
