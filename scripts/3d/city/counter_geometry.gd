extends RefCounted
## Supplemental faces for the DS hall's open-backed props. Keep this in the
## repository: the original room GLB comes from the downloadable asset pack.
## Call before city material fixes so these faces receive the same treatment.

const FACES_PATH := "res://data/stage_geometry/s00e_sa2_completion.json"


static func apply(stage: Node) -> int:
	if stage == null or stage.find_child("CounterCompletion", true, false) != null:
		return 0
	var source: MeshInstance3D = null
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		var candidate := node as MeshInstance3D
		if candidate.mesh != null and candidate.mesh.get_surface_count() == 30:
			source = candidate
			break
	if source == null:
		push_error("[CounterGeometry] Expected the 30-surface s00e_sa2 mesh")
		return 0
	_join_water_panels(source)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACES_PATH))
	var materials: Dictionary = {}
	for i in source.mesh.get_surface_count():
		var material := source.mesh.surface_get_material(i)
		if material != null:
			materials[material.resource_name] = material
	# Validate every material before adding anything; don't show a partial patch.
	for surface: Dictionary in spec.surfaces:
		if not materials.has(surface.material):
			push_error("[CounterGeometry] Missing source material: %s" % surface.material)
			return 0
	var mesh := ArrayMesh.new()
	var triangle_count := 0
	for surface: Dictionary in spec.surfaces:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(materials[surface.material])
		for triangle: Array in surface.triangles:
			# JSON uses glTF counterclockwise winding; Godot uses clockwise.
			for index in [2, 1, 0]:
				var vertex: Dictionary = triangle[index]
				builder.set_normal(_vec3(vertex.NORMAL))
				builder.set_uv(Vector2(vertex.TEXCOORD_0[0], vertex.TEXCOORD_0[1]))
				var color: Array = vertex.COLOR_0
				builder.set_color(Color(color[0], color[1], color[2]))
				builder.add_vertex(_vec3(vertex.POSITION))
			triangle_count += 1
		builder.index()
		builder.commit(mesh)
	var completion := MeshInstance3D.new()
	completion.name = "CounterCompletion"
	completion.mesh = mesh
	# Coordinates are local to the original mesh, including its imported frame.
	source.add_child(completion)
	print("[CounterGeometry] Added %d triangles" % triangle_count)
	return triangle_count


static func _vec3(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


static func _join_water_panels(source: MeshInstance3D) -> void:
	# The teleport pool ends at world Z=93.358, but the hall pool starts
	# at Z=90.553, 0.333 units lower. Their alpha layers add across that
	# strip. Their endpoint UVs already match: join those endpoints at the
	# hall waterline rather than drawing two overlapping transparent sheets.
	var original := source.mesh as ArrayMesh
	var water_index := -1
	for i in original.get_surface_count():
		var material := original.surface_get_material(i)
		if material != null and material.resource_name == "mizu_COLOR_0":
			water_index = i
			break
	if water_index < 0:
		push_error("[CounterGeometry] Missing water surface")
		return
	var arrays := original.surface_get_arrays(water_index)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lower_y := INF
	var upper_y := -INF
	for p in vertices:
		lower_y = minf(lower_y, p.y)
		upper_y = maxf(upper_y, p.y)
	if upper_y - lower_y < 0.01:
		return
	var upper_end := -INF
	var lower_start := INF
	var seam_width := 0.0
	for p in vertices:
		if p.y > lower_y + 0.01:
			upper_end = maxf(upper_end, p.z)
		else:
			lower_start = minf(lower_start, p.z)
	for p in vertices:
		if absf(p.z - lower_start) < 0.001 and absf(p.y - lower_y) < 0.001:
			seam_width = maxf(seam_width, absf(p.x))
	for i in vertices.size():
		if vertices[i].y > lower_y + 0.01:
			var p := vertices[i]
			p.y = lower_y
			if absf(p.z - upper_end) < 0.001:
				p.z = lower_start
				p.x = signf(p.x) * seam_width
			vertices[i] = p
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var water := ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	water.surface_set_material(0, original.surface_get_material(water_index))
	water.surface_set_name(0, original.surface_get_name(water_index))
	# Keep every other surface's packed buffers (and LODs) verbatim. Only
	# this scene instance receives the new mesh; the asset pack stays intact.
	var surfaces: Array = original.get("_surfaces").duplicate(true)
	surfaces[water_index] = water.get("_surfaces")[0]
	var patched := ArrayMesh.new()
	patched.set("_surfaces", surfaces)
	source.mesh = patched
