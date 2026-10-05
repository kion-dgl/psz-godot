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


## E's imported sky walls obscure the Environment sky. Hide only the
## s04_0_skye surface and s04_1_moon card; keep the ruins, flowers and crystals.
static func prepare_stage(root: Node3D, stage_id: String, slot: Dictionary = {}) -> void:
	if stage_id == "s04b_ga1":
		_prepare_b_reference(root)
		return
	if stage_id != "s04e_ia1":
		return
	MeshUtils.split_mesh_surfaces(root)
	var removed := 0
	for node in MeshUtils.collect_mesh_instances(root, []):
		var mi := node as MeshInstance3D
		if mi.is_queued_for_deletion() or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			_apply_ambient_material(mi, i, slot)
			var material := mi.mesh.surface_get_material(i)
			if material != null and material.resource_name == "1_skye":
				_remove_sky_triangles(mi, i)
				removed += 1
			elif material != null and material.resource_name == "tuki":
				mi.visible = false
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				removed += 1
				break
	print("[Makara E] hidden sky/moon surfaces: %d; using Environment sky" % removed)


static func _remove_sky_triangles(mi: MeshInstance3D, index: int) -> void:
	# The sky atlas also contains doorway columns in its bottom strip.
	# Keep those triangles; only the upper atlas region is the old skybox.
	var arrays := mi.mesh.surface_get_arrays(index)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for start in range(0, indices.size(), 3):
		if uvs[indices[start]].y > 0.81 and uvs[indices[start + 1]].y > 0.81 \
				and uvs[indices[start + 2]].y > 0.81:
			kept.append_array(indices.slice(start, start + 3))
	var source := mi.mesh.surface_get_material(index)
	var active := mi.get_active_material(index)
	arrays[Mesh.ARRAY_INDEX] = kept
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, source)
	mi.mesh = mesh
	mi.set_surface_override_material(0, active)
	print("[Makara E] retained %d doorway triangles; removed %d sky triangles" % [
		kept.size() / 3, (indices.size() - kept.size()) / 3])


static func _apply_ambient_material(mi: MeshInstance3D, index: int, slot: Dictionary) -> void:
	var source := mi.get_active_material(index)
	if source is StandardMaterial3D:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/3d/field/makara_ambient_stage.gdshader")
		mat.set_shader_parameter("albedo_texture", source.albedo_texture)
		mat.set_shader_parameter("albedo_color", source.albedo_color)
		mat.set_shader_parameter("uv_scale", source.uv1_scale)
		mat.set_shader_parameter("uv_offset", source.uv1_offset)
		mat.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
		_configure_floor_shadow(mi, index, mat, slot)
		mi.set_surface_override_material(index, mat)
	elif source is ShaderMaterial:
		# Retain mirror wrapping and the authored UV fix on the floor.
		var mat := source.duplicate() as ShaderMaterial
		var shader := Shader.new()
		shader.code = source.shader.code + "\nvoid light() {}\n"
		mat.shader = shader
		_configure_floor_shadow(mi, index, mat, slot)
		mi.set_surface_override_material(index, mat)


static func _configure_floor_shadow(mi: MeshInstance3D, index: int,
		mat: ShaderMaterial, slot: Dictionary) -> void:
	var original := mi.mesh.surface_get_material(index)
	if original == null or not original.resource_name.begins_with("1_yuka"):
		return
	# Opaque floor receives the renderer's shadow map. Its custom light term
	# substitutes ambient for LIGHT_COLOR/energy, retaining the baked albedo.
	var code := mat.shader.code.replace("void light() {}", "")
	code = code.replace("ALPHA = tex.a * albedo_color.a;", "")
	code = code.replace("ALPHA_SCISSOR_THRESHOLD = 0.1;", "")
	code += "\nrender_mode ambient_light_disabled;\n"
	code += "uniform vec4 floor_ambient : source_color = vec4(1.0);\n"
	code += "uniform float floor_ambient_energy = 0.5;\n"
	code += "void light() { DIFFUSE_LIGHT += floor_ambient.rgb * (floor_ambient_energy / PI) * mix(0.35, 1.0, ATTENUATION); }\n"
	var shader := Shader.new()
	shader.code = code
	mat.shader = shader
	mat.set_shader_parameter("floor_ambient", slot.get("ambient_color", Color.WHITE))
	mat.set_shader_parameter("floor_ambient_energy", slot.get("ambient_energy", 0.5))
	mi.set_meta("makara_floor_material", mat)


static func refresh_ambient(root: Node3D, env: Environment) -> void:
	if root == null:
		return
	for node in MeshUtils.collect_mesh_instances(root, []):
		if node.has_meta("makara_floor_material"):
			var mat: ShaderMaterial = node.get_meta("makara_floor_material")
			mat.set_shader_parameter("floor_ambient", env.ambient_light_color)
			mat.set_shader_parameter("floor_ambient_energy", env.ambient_light_energy)


static func _prepare_b_reference(root: Node3D) -> void:
	# Preserve the painted light pools and distant scenery, with a subdued
	# cool tint. Unshaded stage materials cannot receive the actor lights.
	for node in MeshUtils.collect_mesh_instances(root, []):
		var mi := node as MeshInstance3D
		for index in mi.mesh.get_surface_count():
			var source := mi.get_active_material(index)
			if source is StandardMaterial3D:
				var mat := source.duplicate() as StandardMaterial3D
				mat.albedo_color *= Color(0.72, 0.75, 0.8)
				mi.set_surface_override_material(index, mat)
			elif source is ShaderMaterial:
				var mat := source.duplicate() as ShaderMaterial
				var tint: Variant = mat.get_shader_parameter("albedo_color")
				if tint is Color:
					mat.set_shader_parameter("albedo_color", tint * Color(0.72, 0.75, 0.8))
				mi.set_surface_override_material(index, mat)
	# Broad, shadowless actor accents above the central baked floor patches.
	for point in [Vector3(-3, 4, -9), Vector3(3, 4, 10)]:
		var light := OmniLight3D.new()
		light.name = "MakaraIndirectFill"
		light.position = point
		light.light_color = Color(0.9, 0.94, 1.0)
		light.light_energy = 0.35
		light.omni_range = 11.0
		light.shadow_enabled = false
		light.light_cull_mask &= ~MeshUtils.SHADOW_CATCHER_LAYER
		root.add_child(light, true)
