extends RefCounted
## Shared player/enemy burn: reuse the existing enemy flame mesh and particle tuning.
static func create() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.amount = 36
	particles.lifetime = 0.65
	particles.preprocess = 0.3
	particles.direction = Vector3.UP
	particles.spread = 20.0
	particles.gravity = Vector3(0, 1.5, 0)
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.55
	particles.position.y = 0.7
	particles.scale_amount_min = 0.4
	particles.scale_amount_max = 0.8
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 0.95, 0.3, 0.95), Color(1, 0.35, 0.03, 0.8), Color(0.8, 0.05, 0, 0)])
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
	flame.size = Vector2(0.65, 1.1)
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
