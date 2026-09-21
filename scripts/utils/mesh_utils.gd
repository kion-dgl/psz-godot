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


## The GLB's alphaMode for a mirror-wrap surface, expressed for the fix
## shader's alpha_mode uniform: blend-capable imports (BLEND arrives from the
## Godot 4.5 GLTF importer as ALPHA_HASH on some meshes) stay blended; the
## scissor default is only right for MASK-style materials. Static so the
## runner can pin the mapping (#659 playtest: scissored water = missing pixels).
static func mirror_alpha_mode(transparency: int) -> int:
	match transparency:
		BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			return 0
		_:
			return 1


## Fix-table row for a material's albedo texture (bare filename key), or {}.
## Loaded once per process — the table is static data.
static var _fixes_cache: Dictionary = {}


static func fix_for_material(mat: StandardMaterial3D) -> Dictionary:
	if _fixes_cache.is_empty():
		_fixes_cache = load_texture_fixes()
	if not mat.albedo_texture:
		return {}
	return _fixes_cache.get(mat.albedo_texture.resource_path.get_file(), {})


## The field's per-surface material treatment, extracted from the valley
## controller's _fix_materials so tool scenes render EXACTLY what the field
## renders (the #659 walk lab's see-through pools were this pass missing):
## the fix row picks the branch — scrolling/"_fall" surfaces take the
## additive waterfall shader, mirror-wrap surfaces the wrap shader (keeping
## the GLB's alpha mode), everything else the generic duplicated material
## (per-vertex albedo, alpha scissor, always depth-draw). `cast_shadows`
## carries the slot's geometry_casts_shadows row — map geometry is
## collision-floor-deep and shadows off by default; a moon rig that stands
## on real shadows turns it on.
static func apply_field_materials(node: Node, fix_shader: Shader,
		waterfall_shader: Shader, cast_shadows := false) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# SmoothNormals._surface_count + _active_material, not the plain
		# override-count API — get_active_material() bounds-checks against the
		# override array, which only grows as overrides are set (the
		# one-surface strip bug, #646).
		for i in range(SmoothNormals._surface_count(mi)):
			var mat := SmoothNormals._active_material(mi, i)
			if not (mat is StandardMaterial3D):
				continue
			var std_mat := mat as StandardMaterial3D
			var fix := fix_for_material(std_mat)
			var has_scroll := fix.has("scrollX") or fix.has("scrollY")
			var is_waterfall := has_scroll \
					or (std_mat.albedo_texture and "_fall" in std_mat.albedo_texture.resource_path)
			if is_waterfall and waterfall_shader:
				# Waterfall / scrolling texture: additive blend + scrolling UV
				var shader_mat := ShaderMaterial.new()
				shader_mat.shader = waterfall_shader
				if std_mat.albedo_texture:
					shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
				shader_mat.set_shader_parameter("uv_scale", Vector3(
					float(fix.get("repeatX", 1.0)), float(fix.get("repeatY", 1.0)), 1.0))
				shader_mat.set_shader_parameter("uv_offset", Vector3(
					float(fix.get("offsetX", 0.0)), float(fix.get("offsetY", 0.0)), 0.0))
				var scroll_x: float = float(fix.get("scrollX", 0.0))
				var scroll_y: float = float(fix.get("scrollY", -0.35))
				shader_mat.set_shader_parameter("uv_scroll", Vector2(scroll_x, scroll_y))
				shader_mat.render_priority = 1
				mi.set_surface_override_material(i, shader_mat)
			elif str(fix.get("wrapS", "repeat")) == "mirror" \
					or str(fix.get("wrapT", "repeat")) == "mirror":
				# Mirror wrap: custom shader with wrap modes
				var shader_mat := ShaderMaterial.new()
				shader_mat.shader = fix_shader
				if std_mat.albedo_texture:
					shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
				shader_mat.set_shader_parameter("uv_scale", Vector3(
					float(fix.get("repeatX", 1.0)), float(fix.get("repeatY", 1.0)), 1.0))
				shader_mat.set_shader_parameter("uv_offset", Vector3(
					float(fix.get("offsetX", 0.0)), float(fix.get("offsetY", 0.0)), 0.0))
				shader_mat.set_shader_parameter("wrap_s",
					1 if str(fix.get("wrapS", "repeat")) == "mirror" else 0)
				shader_mat.set_shader_parameter("wrap_t",
					1 if str(fix.get("wrapT", "repeat")) == "mirror" else 0)
				# Keep the GLB's alphaMode (BLEND stays blended; the shader
				# default scissor hard-cuts smooth-alpha texels).
				shader_mat.set_shader_parameter("alpha_mode", mirror_alpha_mode(std_mat.transparency))
				mi.set_surface_override_material(i, shader_mat)
			else:
				var new_mat := std_mat.duplicate() as StandardMaterial3D
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				new_mat.vertex_color_use_as_albedo = true
				new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				new_mat.alpha_scissor_threshold = 0.1
				new_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				new_mat.texture_repeat = true
				if not fix.is_empty():
					new_mat.uv1_scale = Vector3(
						float(fix.get("repeatX", 1.0)), float(fix.get("repeatY", 1.0)), 1.0)
					new_mat.uv1_offset = Vector3(
						float(fix.get("offsetX", 0.0)), float(fix.get("offsetY", 0.0)), 0.0)
					if str(fix.get("wrapS", "repeat")) == "clamp" \
							or str(fix.get("wrapT", "repeat")) == "clamp":
						new_mat.texture_repeat = false
				mi.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		apply_field_materials(child, fix_shader, waterfall_shader, cast_shadows)


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
			# Keep the GLB's alphaMode (BLEND stays blended; the shader default
			# scissor hard-cuts smooth-alpha texels) — mirrors the field's
			# _fix_materials branch so lab renders read as the field does.
			shader_mat.set_shader_parameter("alpha_mode", mirror_alpha_mode(std.transparency))
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


## #648 enclosure test: does the sun reach this room's interior? PSO stage
## shells are closed boxes (walls, ceiling and backdrop in one mesh), so with
## geometry casting on the shell shadows its OWN interior — no dynamic sun
## shadow can exist inside, and the player blob must return (the blob-skip
## presumes the directional source actually reaches the player). Casts a few
## body-height rays from the room's floor grid toward `sun_dir` (direction
## TOWARD the sun, global space) against every mesh triangle: any clear ray
## counts the room as sun-open. Pure math — no physics space, safe from _ready.
## `floor_y` is the walkable surface height (the floor GLB's top); without it
## the shell AABB's mid-height stands in — the mesh min is useless (PSO
## backdrops skirt far below the floor).
static func sun_reaches_room(map_root: Node3D, sun_dir: Vector3, floor_y: float = NAN) -> bool:
	if map_root == null or not (sun_dir.length() > 0.5):
		return true
	var d := sun_dir.normalized()
	var aabb := global_mesh_aabb(map_root)
	if aabb.size == Vector3.ZERO:
		return true
	var y := floor_y + 1.5 if is_finite(floor_y) else aabb.get_center().y + 2.5
	var c := aabb.get_center()
	var q := aabb.size * 0.25
	var origins := [
		Vector3(c.x, y, c.z),
		Vector3(c.x - q.x, y, c.z - q.z),
		Vector3(c.x + q.x, y, c.z - q.z),
		Vector3(c.x - q.x, y, c.z + q.z),
		Vector3(c.x + q.x, y, c.z + q.z),
	]
	# Per-origin blocking: the room is sun-open iff ANY origin's ray escapes
	# every triangle. No facing prefilter — from inside a shell the blockers
	# present their back faces. (No primitive-counter early-out: lambdas
	# capture ints by value, so only the reference-type array propagates.)
	var blocked: Array = [false, false, false, false, false]
	_walk_triangles(map_root, func(p0: Vector3, p1: Vector3, p2: Vector3):
		for i in origins.size():
			if not blocked[i] and _segment_hit_triangle(origins[i], d, p0, p1, p2):
				blocked[i] = true
	)
	return blocked.has(false)


## AABB over every mesh instance under `root`, in global space. The field
## controller reads the floor shell's top from it; the shadow geometry here
## and the labs share the same walk.
static func global_mesh_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in collect_mesh_instances(root, []):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


## Every MeshInstance3D under `node`, depth-first, appended to `out`.
static func collect_mesh_instances(node: Node, out: Array) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		collect_mesh_instances(child, out)
	return out


## Every mesh triangle under `root` in global space, fed to `cb(p0, p1, p2)`.
static func _walk_triangles(root: Node, cb: Callable) -> void:
	for node in collect_mesh_instances(root, []):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.size() == 0:
				continue
			var xform := mi.global_transform
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.size() > 0:
				for t in range(0, idx.size() - 2, 3):
					cb.call(
						xform * verts[idx[t]],
						xform * verts[idx[t + 1]],
						xform * verts[idx[t + 2]])
			else:
				for t in range(0, verts.size() - 2, 3):
					cb.call(xform * verts[t], xform * verts[t + 1], xform * verts[t + 2])


## Möller–Trumbore ray/triangle hit (double-sided), within 300 units.
static func _segment_hit_triangle(o: Vector3, d: Vector3, p0: Vector3, p1: Vector3, p2: Vector3) -> bool:
	const EPS := 0.0001
	const MAX_T := 300.0
	var e1 := p1 - p0
	var e2 := p2 - p0
	var h := d.cross(e2)
	var det_a := e1.dot(h)
	if absf(det_a) < EPS:
		return false
	var inv := 1.0 / det_a
	var s := o - p0
	var u := s.dot(h) * inv
	if u < 0.0 or u > 1.0:
		return false
	var rk := s.cross(e1)
	var v := d.dot(rk) * inv
	if v < 0.0 or u + v > 1.0:
		return false
	var t := e2.dot(rk) * inv
	return t > EPS and t < MAX_T


## #648 shell carve-out: a stage shell that encloses the room must not CAST.
## The shells are single meshes (walls + ceiling + backdrop) — with casting
## on, a shell shadows its own interior, deleting the sun (and every dynamic
## shadow with it, the player's included). Each mesh is tested alone: one
## that blocks every sample ray BY ITSELF encloses the room and gets
## SHADOW_CASTING_SETTING_OFF; it still receives shadows, so the player and
## placed objects cast real ones on it. Partials (a wall, a rim) keep
## casting. Returns how many meshes were disarmed. Run it after the row's
## geometry-casting pass, with the applied sun's direction.
static func disable_enclosing_casters(map_root: Node3D, sun_dir: Vector3, floor_y: float = NAN) -> int:
	if map_root == null or not (sun_dir.length() > 0.5):
		return 0
	var d := sun_dir.normalized()
	var aabb := global_mesh_aabb(map_root)
	if aabb.size == Vector3.ZERO:
		return 0
	var y := floor_y + 1.5 if is_finite(floor_y) else aabb.get_center().y + 2.5
	var c := aabb.get_center()
	var q := aabb.size * 0.25
	var origins := [
		Vector3(c.x, y, c.z),
		Vector3(c.x - q.x, y, c.z - q.z),
		Vector3(c.x + q.x, y, c.z - q.z),
		Vector3(c.x - q.x, y, c.z + q.z),
		Vector3(c.x + q.x, y, c.z + q.z),
	]
	var disarmed := 0
	for node in collect_mesh_instances(map_root, []):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		# Containment first: a shell's bounds hold the whole sample volume.
		# A wide wall can block every sun ray by itself at a grazing angle,
		# but its thin bounds don't contain the samples — disarming it would
		# let the sun shine through a solid wall.
		var m_box := mi.global_transform * mi.get_aabb()
		var contains_all := true
		for o in origins:
			if not m_box.has_point(o):
				contains_all = false
				break
		# Far scenery: only the painted panorama at the room's very rim (the
		# edge mountains whose blocky shadows graze the border) disarms on
		# distance. Mid-ground mesas and rocks STAY armed — their shadows
		# must drape the props standing in the regions the authored bake
		# shades (a lit cart inside a baked-shadow strip reads broken, #648).
		# 70 units: past the play space, short of the rim panorama.
		var far_scenery := true
		for o in origins:
			if _aabb_point_distance(m_box, o) < 70.0:
				far_scenery = false
				break
		if far_scenery or (contains_all and _node_blocks_all(mi, origins, d)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disarmed += 1
	return disarmed


## Point-to-box distance (0 inside) — this Godot's AABB lacks distance_to.
static func _aabb_point_distance(box: AABB, p: Vector3) -> float:
	var q := Vector3(
		maxf(box.position.x - p.x, maxf(0.0, p.x - box.end.x)),
		maxf(box.position.y - p.y, maxf(0.0, p.y - box.end.y)),
		maxf(box.position.z - p.z, maxf(0.0, p.z - box.end.z)))
	return q.length()


## Do THIS node's own triangles block every origin ray? (The per-mesh half of
## sun_reaches_room — a mesh that does, encloses the sample volume.)
static func _node_blocks_all(node: MeshInstance3D, origins: Array, d: Vector3) -> bool:
	var blocked: Array = []
	for i in origins.size():
		blocked.append(false)
	_walk_triangles(node, func(p0: Vector3, p1: Vector3, p2: Vector3):
		for i in origins.size():
			if not blocked[i] and _segment_hit_triangle(origins[i], d, p0, p1, p2):
				blocked[i] = true
	)
	return not blocked.has(false)


## The player's blob shadow (#646): an unshaded dark disc that grounds the
## player when no directional light can shadow them — rows without a shadow
## source. The controller parents it and tracks the player each frame.
static func make_player_blob() -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = \
		"shader_type spatial;\n" + \
		"render_mode unshaded, cull_disabled, depth_test_disabled;\n\n" + \
		"void fragment() {\n" + \
		"\tfloat dist = length(UV - vec2(0.5)) * 2.0;\n" + \
		"\tfloat alpha = (1.0 - smoothstep(0.5, 1.0, dist)) * 0.35;\n" + \
		"\tALBEDO = vec3(0.0);\n" + \
		"\tALPHA = alpha;\n" + \
		"}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	blob.material_override = mat
	return blob


## #648 panorama placement: the compatibility renderer anchors its
## directional shadow pass at the LIGHT NODE'S position — for a panorama
## room (scenery painted on an enclosing shell) the eye must sit in the
## interior air, above the floor and below the ceiling. An eye at the
## origin sits at floor level — in bridge rooms, inside the chasm UNDER
## the deck, with geometry between the eye and the player, and the player
## standing on the deck loses its dynamic shadow entirely. Position is
## meaningless to a directional light's shading, so this only moves the
## shadow eye: midway up the interior, on the room's center column.
static func place_light_inside_room(light: DirectionalLight3D,
		map_root: Node3D, floor_top: float = NAN) -> void:
	if light == null or map_root == null:
		return
	var box := global_mesh_aabb(map_root)
	if box.size == Vector3.ZERO:
		return
	var base := floor_top if is_finite(floor_top) else box.position.y
	var y := clampf(lerpf(base, box.end.y, 0.6), base + 4.0, base + 30.0)
	var c := box.get_center()
	light.global_position = Vector3(c.x, y, c.z)




## #648 per-surface split: PSO rooms ship as ONE mesh with a dozen surfaces
## (backdrop, floor, bridge, props…), but casting is per-instance — an
## all-or-nothing carve-out either disarms the props with the shell or
## leaves the panorama casting square mountains. This splits every
## multi-surface MeshInstance into per-surface children (transform, surface
## materials, surface override materials, and casting carried over), so the
## enclosure test can judge each surface on its own geometry. Returns the
## number of instances created. Static room meshes only — run after the
## material pass, before the carve-out.
static func split_mesh_surfaces(root: Node3D) -> int:
	var created := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() <= 1:
			continue
		var parent := mi.get_parent()
		for s in range(mesh.get_surface_count()):
			var part := ArrayMesh.new()
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
			part.surface_set_material(0, mesh.surface_get_material(s))
			var child := MeshInstance3D.new()
			child.name = "%s_s%d" % [mi.name, s]
			child.mesh = part
			# Sibling of the original (same transform slot), so the freed
			# original can't take the split parts with it.
			child.transform = mi.transform
			child.cast_shadow = mi.cast_shadow
			var override: Material = mi.get_surface_override_material(s)
			if override:
				child.set_surface_override_material(0, override)
			parent.add_child(child)
			created += 1
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.queue_free()
	return created
