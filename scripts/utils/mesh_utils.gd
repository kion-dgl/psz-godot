class_name MeshUtils
## Shared mesh helpers. Deduplicated from the identical `_apply_texture_recursive`
## in character_create.gd and character_select.gd — #294.


## Walk `node` and its descendants; duplicate every existing
## StandardMaterial3D surface override and point its albedo at `texture`.
## Unlike apply_texture_recursive it leaves material-less surfaces alone,
## and `nearest` controls the filter (field_npc historically skips it).
## Deduplicated from the identical `_apply_texture` in companion_npc /
## weapon_test / enemy_base / field_npc / enemy_spawn — #294 / #215-C7.
static func apply_texture(node: Node, texture: Texture2D, nearest := true) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_texture = texture
				if nearest:
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		apply_texture(child, texture, nearest)


## Walk `node` and its descendants; for every MeshInstance3D surface, override the
## material's albedo with `texture` (nearest-filtered). Existing StandardMaterial3D
## surfaces are duplicated so the source material isn't mutated; surfaces with no
## material get a fresh StandardMaterial3D.
static func apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface_idx in range(mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(surface_idx)
				if mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
				elif mat == null:
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
	for child in node.get_children():
		apply_texture_recursive(child, texture)


## Load the global texture-fix table, keyed by texture filename (the "#N"
## material-index suffix GLTF keys carry is stripped). Shared by the field
## lighting tool scenes (#657 — third copy was the flag).
static func load_texture_fixes() -> Dictionary:
	var fixes := {}
	var file := FileAccess.open("res://data/stage_configs/global-texture-fixes.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			for key in json.data:
				fixes[str(key).split("#")[0]] = json.data[key]
		file.close()
	return fixes


## The field controller's mirror-wrap pass, extracted for the tool scenes:
## surfaces whose texture fix asks for mirror wrap get the custom shader —
## Godot can't mirror-repeat imported textures natively.
static func apply_mirror_wrap_fixes(node: Node, fixes: Dictionary, fix_shader: Shader) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# SmoothNormals._surface_count + _active_material, not the plain
		# override-count API — get_active_material() bounds-checks against the
		# override array, which only grows as overrides are set (the
		# one-surface strip bug, #646).
		for i in range(SmoothNormals._surface_count(mi)):
			var mat := SmoothNormals._active_material(mi, i)
			if not (mat is StandardMaterial3D):
				continue
			var std := mat as StandardMaterial3D
			if not std.albedo_texture:
				continue
			var fix: Dictionary = fixes.get(std.albedo_texture.resource_path.get_file(), {})
			var wrap_s: String = str(fix.get("wrapS", "repeat"))
			var wrap_t: String = str(fix.get("wrapT", "repeat"))
			if wrap_s != "mirror" and wrap_t != "mirror":
				continue
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = fix_shader
			shader_mat.set_shader_parameter("albedo_texture", std.albedo_texture)
			shader_mat.set_shader_parameter("albedo_color", std.albedo_color)
			shader_mat.set_shader_parameter("uv_scale", Vector3(
				float(fix.get("repeatX", 1.0)), float(fix.get("repeatY", 1.0)), 1.0))
			shader_mat.set_shader_parameter("uv_offset", Vector3(
				float(fix.get("offsetX", 0.0)), float(fix.get("offsetY", 0.0)), 0.0))
			shader_mat.set_shader_parameter("wrap_s", 1 if wrap_s == "mirror" else 0)
			shader_mat.set_shader_parameter("wrap_t", 1 if wrap_t == "mirror" else 0)
			mi.set_surface_override_material(i, shader_mat)
	for child in node.get_children():
		apply_mirror_wrap_fixes(child, fixes, fix_shader)


## #657 glow pass: surfaces whose material is named in `passes` (keyed by
## material resource name) get an emissive tint + authored roughness so
## anchor meshes read as light sources. Materials are duplicated before
## mutation — imported GLB materials are shared across stages. Returns the
## number of surfaces touched.
static func apply_glow_materials(node: Node, passes: Dictionary) -> int:
	if passes.is_empty():
		return 0
	var touched := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(SmoothNormals._surface_count(mi)):
			var mat := SmoothNormals._active_material(mi, i)
			if mat is StandardMaterial3D \
					and passes.has((mat as StandardMaterial3D).resource_name):
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				var glow: Dictionary = passes[std.resource_name]
				var e: Array = glow.get("emission", [1, 1, 1])
				std.emission_enabled = true
				std.emission = Color(float(e[0]), float(e[1]), float(e[2]))
				std.emission_energy_multiplier = float(glow.get("energy", 0.5))
				std.roughness = float(glow.get("roughness", 0.5))
				mi.set_surface_override_material(i, std)
				touched += 1
	for child in node.get_children():
		touched += apply_glow_materials(child, passes)
	return touched
