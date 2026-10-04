extends RefCounted
## Shrine B's versioned lighting and rebuilt pillar insets. The source art
## stays immutable; each loaded pillar separates its lower vessel from the shaft; the vessel retains stone
## detail beneath the soft teal emission. Both production and the walk lab use this exact path.

const ROOT := "res://data/stage_configs/shrine-lights/"
const POT_SHADER := preload("res://scripts/3d/field/shrine_pot_glow.gdshader")
static var _recipes: Dictionary = {}


static func recipe(stage_id: String) -> Dictionary:
	if not (stage_id.begins_with("s07a_") or stage_id.begins_with("s07b_") or stage_id.begins_with("s07e_")):
		return {}
	if not _recipes.has(stage_id):
		var path := ROOT + stage_id + ".json"
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
			if FileAccess.file_exists(path) else null
		_recipes[stage_id] = data if data is Dictionary else {}
	return _recipes[stage_id]


static func rebuild_pillars(root: Node3D, stage_id: String) -> int:
	if stage_id.begins_with("s07b_") and stage_id != "s07b_ga1":
		_split_floor_receivers(root)
	# Remove only the lamp cards, not unrelated scenery sharing their material.
	var lantern_material := "1_light3" if stage_id.begins_with("s07a_") else "1_blight"
	if stage_id.begins_with("s07e_"):
		lantern_material = "1_lighte"
	var lamps: Array = recipe(stage_id).get("effects", []).filter(func(e): return e.get("type") == "shrine_lantern")
	if not lamps.is_empty():
		# A rooms without a lighting override still have multi-surface meshes.
		if stage_id.begins_with("s07a_") or stage_id.begins_with("s07e_"):
			MeshUtils.split_mesh_surfaces(root)
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node.mesh as ArrayMesh
			if node.is_queued_for_deletion() or node.has_meta("lantern_cards_removed") or mesh == null or mesh.get_surface_count() != 1:
				continue
			var mat := mesh.surface_get_material(0)
			if mat == null or mat.resource_name != lantern_material:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var kept := PackedInt32Array()
			for t in range(0, indices.size(), 3):
				var is_lamp := false
				for lamp in lamps:
					var matches := true
					for j in range(3):
						var v := vertices[indices[t+j]]
						matches = matches and v.y < 4.0 and Vector2(v.x-float(lamp.position[0]), v.z-float(lamp.position[2])).length() < 2.0
					is_lamp = is_lamp or matches
				if not is_lamp:
					kept.append_array(indices.slice(t,t+3))
			if kept.is_empty():
				node.visible = false
				node.queue_free()
			else:
				arrays[Mesh.ARRAY_INDEX] = kept
				var replacement := ArrayMesh.new()
				replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				replacement.surface_set_material(0, mat)
				var active: Material = node.get_active_material(0)
				node.mesh = replacement
				node.set_surface_override_material(0, active)
				node.set_meta("lantern_cards_removed", true)
	var centers: Array = recipe(stage_id).get("pillar_centers", [])
	if centers.is_empty():
		return 0
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.is_queued_for_deletion() or mi.has_meta("shrine_insets"):
			continue
		var source := mi.mesh as ArrayMesh
		if source == null or source.get_surface_count() != 1:
			continue # The shared material path splits the source first.
		var material := source.surface_get_material(0)
		if material == null or material.resource_name not in ["1_line", "1_line2"]:
			continue
		var arrays := source.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in range(vertices.size()):
				indices.append(i)
		var stone := _buffer()
		var inset := _buffer()
		for t in range(0, indices.size(), 3):
			var polygon: Array = []
			var eligible := false
			for center in centers:
				var inside := true
				for j in range(3):
					var p: Vector3 = mi.transform * vertices[indices[t + j]]
					inside = inside and p.y > 0.25 and \
						Vector2(p.x - float(center[0]), p.z - float(center[1])).length() < 2.1
				eligible = eligible or inside
			for j in range(3):
				var i := indices[t + j]
				polygon.append([vertices[i], normals[i] if not normals.is_empty() else Vector3.UP,
					uvs[i], colors[i] if not colors.is_empty() else Color.WHITE])
			if not eligible:
				_emit(polygon, stone)
				continue
			# Isolate the entire column from the room's shared surfaces. The
			# shader supplies a faint fill everywhere and the band only below.
			_emit(polygon, inset)
		if inset[0].is_empty():
			continue
		var frame := ArrayMesh.new()
		if not stone[0].is_empty():
			frame.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(stone))
			frame.surface_set_material(0, material)
		var active := mi.get_active_material(0)
		mi.mesh = frame
		if frame.get_surface_count() > 0:
			mi.set_surface_override_material(0, active)
		mi.set_meta("shrine_insets", true)
		var core := MeshInstance3D.new()
		core.name = "TealPillarInsets"
		var core_mesh := ArrayMesh.new()
		core_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(inset))
		var glow := ShaderMaterial.new()
		glow.shader = POT_SHADER
		glow.resource_name = "ShrineTealInset"
		var source_material := material as StandardMaterial3D
		var fix := MeshUtils.fix_for_material(source_material)
		glow.set_shader_parameter("albedo_texture", source_material.albedo_texture)
		glow.set_shader_parameter("uv_scale", Vector2(float(fix.get("repeatX", 1)), float(fix.get("repeatY", 1))))
		glow.set_shader_parameter("uv_offset", Vector2(float(fix.get("offsetX", 0)), float(fix.get("offsetY", 0))))
		glow.set_shader_parameter("mirror_s", fix.get("wrapS", "repeat") == "mirror")
		glow.set_shader_parameter("mirror_t", fix.get("wrapT", "repeat") == "mirror")
		glow.set_meta("shrine_source_material", source_material)
		core_mesh.surface_set_material(0, glow)
		core.mesh = core_mesh
		core.layers = mi.layers
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(core)
		count += inset[0].size() / 3
	return count


static func _buffer() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray()]


static func _arrays(buffer: Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer[0]
	arrays[Mesh.ARRAY_NORMAL] = buffer[1]
	arrays[Mesh.ARRAY_TEX_UV] = buffer[2]
	arrays[Mesh.ARRAY_COLOR] = buffer[3]
	return arrays


static func _emit(poly: Array, buffer: Array) -> void:
	for i in range(1, poly.size() - 1):
		var a: Vector3 = poly[0][0]
		var b: Vector3 = poly[i][0]
		var c: Vector3 = poly[i + 1][0]
		if (b - a).cross(c - a).length_squared() < 0.0000000001:
			continue
		for vertex in [poly[0], poly[i], poly[i + 1]]:
			for k in range(4):
				buffer[k].append(vertex[k])



## Keep distant lanterns out of each floor patch's 16-light object budget.
## Only flat walk-height surfaces are split; clipping preserves the texture,
## normals, vertex shading, silhouette and collision exactly.
static func _split_floor_receivers(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.is_queued_for_deletion() or mi.has_meta("shrine_floor_patch"):
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 1:
			continue
		var box := mesh.get_aabb()
		if box.position.y < -1.0 or box.end.y > 1.0 or box.size.y > 1.0 or maxf(box.size.x, box.size.z) <= 8.0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var cs: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			for i in range(vs.size()):
				ix.append(i)
		var patches: Dictionary = {}
		for t in range(0, ix.size(), 3):
			var triangle: Array = []
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for j in range(3):
				var i := ix[t+j]
				triangle.append([vs[i], ns[i], uv[i], cs[i] if not cs.is_empty() else Color.WHITE])
				low = low.min(vs[i])
				high = high.max(vs[i])
			for x in range(floori(low.x/8.0), floori(high.x/8.0)+1):
				for z in range(floori(low.z/8.0), floori(high.z/8.0)+1):
					var polygon: Array = triangle
					for plane in [[0,x*8.0,true],[0,(x+1)*8.0,false],[2,z*8.0,true],[2,(z+1)*8.0,false]]:
						polygon = _clip_position(polygon, int(plane[0]), float(plane[1]), bool(plane[2]))
						if polygon.size()<3:
							break
					if polygon.size() < 3:
						continue
					var key := Vector2i(x,z)
					if not patches.has(key):
						patches[key] = _buffer()
					_emit(polygon, patches[key])
		for key in patches:
			if patches[key][0].is_empty():
				continue
			var part := ArrayMesh.new()
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(patches[key]))
			part.surface_set_material(0, mesh.surface_get_material(0))
			var child := MeshInstance3D.new()
			child.name = "ShrineFloorPatch"
			child.mesh = part
			child.set_surface_override_material(0, mi.get_active_material(0))
			child.transform = mi.transform
			child.layers = mi.layers
			child.cast_shadow = mi.cast_shadow
			child.set_meta("shrine_floor_patch", true)
			mi.get_parent().add_child(child)
		mi.visible = false
		mi.queue_free()


static func _clip_position(poly: Array, axis: int, boundary: float, greater: bool) -> Array:
	var result: Array = []
	if poly.is_empty():
		return result
	var prev: Array = poly[-1]
	var prev_d: float = prev[0][axis] - boundary
	for current in poly:
		var d: float = current[0][axis] - boundary
		var a_inside := prev_d >= 0.0 if greater else prev_d <= 0.0
		var b_inside := d >= 0.0 if greater else d <= 0.0
		if a_inside != b_inside:
			var weight := prev_d / (prev_d-d)
			result.append([prev[0].lerp(current[0],weight), prev[1].lerp(current[1],weight).normalized(),
				prev[2].lerp(current[2],weight), prev[3].lerp(current[3],weight)])
		if b_inside:
			result.append(current)
		prev = current
		prev_d = d
	return result


## Imported stage resources remain immutable; only the instance overrides change.
static func make_double_sided(root: Node3D, stage_id: String) -> void:
	if not (stage_id.begins_with("s07a_") or stage_id.begins_with("s07b_") or stage_id.begins_with("s07e_")):
		return
	var materials: Dictionary = {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node.is_queued_for_deletion() or node.mesh == null:
			continue
		if node.material_override:
			node.material_override = _double_sided_material(node.material_override, materials)
		else:
			for surface in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(surface)
				if material:
					node.set_surface_override_material(surface, _double_sided_material(material, materials))


static func _double_sided_material(source: Material, cache: Dictionary) -> Material:
	if cache.has(source):
		return cache[source]
	var material := source.duplicate() as Material
	cache[source] = material
	if material is BaseMaterial3D:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif material is ShaderMaterial and material.shader and not material.shader.code.contains("cull_disabled"):
		var shader := Shader.new()
		var code: String = material.shader.code
		code = code.replace("cull_back", "cull_disabled").replace("cull_front", "cull_disabled")
		if not code.contains("cull_disabled"):
			code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;")
		shader.code = code
		material.shader = shader
	if source.next_pass:
		material.next_pass = _double_sided_material(source.next_pass, cache)
	return material
