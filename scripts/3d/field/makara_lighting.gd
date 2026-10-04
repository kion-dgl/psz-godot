extends RefCounted
## Reference-room crystal accents; shared by production and the walk lab.
## Source-art cluster positions, two shadowless lights, no texture edits.
static func spawn_crystals(root: Node3D, stage_id: String) -> void:
	if stage_id != "s04a_lb3":
		return
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.22))
	gradient.set_color(1, Color(1, 1, 1, 0))
	texture.gradient = gradient
	for point in [Vector3(-6.5, 0.6, -13.5), Vector3(12.0, 0.8, 12.0)]:
		var light := OmniLight3D.new()
		light.name = "MakaraCrystalLight"
		light.position = point + Vector3(0, 1, 0)
		light.light_color = Color(0.12, 0.48, 1.0)
		light.light_energy = 0.8
		light.omni_range = 10.0
		light.shadow_enabled = false
		light.light_cull_mask &= ~MeshUtils.SHADOW_CATCHER_LAYER
		root.add_child(light, true)
		var glow := MeshInstance3D.new()
		glow.name = "MakaraCrystalGlow"
		glow.position = light.position
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := QuadMesh.new()
		quad.size = Vector2(6, 6)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_color = Color(0.08, 0.42, 1.0)
		material.albedo_texture = texture
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		glow.mesh = quad
		root.add_child(glow, true)
