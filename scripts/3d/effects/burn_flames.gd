extends RefCounted
## Small, short-lived flame patches scattered over the body, following its motion.
static func create() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 22
	particles.lifetime = 0.45
	particles.preprocess = 0.2
	particles.local_coords = true
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.gravity = Vector3(0, 0.3, 0)
	particles.initial_velocity_min = 0.15
	particles.initial_velocity_max = 0.4
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.3, 0.6, 0.22)
	particles.position.y = 0.85
	particles.scale_amount_min = 0.35
	particles.scale_amount_max = 0.6
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0, 0.2))
	size_curve.add_point(Vector2(0.25, 1.0))
	size_curve.add_point(Vector2(1, 0.0))
	particles.scale_amount_curve = size_curve
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 0.8, 0.2, 0.65), Color(1, 0.35, 0.03, 0.5), Color(0.8, 0.05, 0, 0)])
	gradient.offsets = PackedFloat32Array([0, 0.4, 1])
	particles.color_ramp = gradient
	var texture := GradientTexture2D.new()
	var mask := Gradient.new()
	mask.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	texture.gradient = mask
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0)
	var flame := QuadMesh.new()
	flame.size = Vector2(0.3, 0.45)
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_material.albedo_texture = texture
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_material.vertex_color_use_as_albedo = true
	flame.material = flame_material
	particles.mesh = flame
	return particles
