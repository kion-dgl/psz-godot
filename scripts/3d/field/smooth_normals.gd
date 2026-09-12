class_name SmoothNormals
## Generates smooth vertex normals for meshes whose GLB shipped without a
## NORMAL attribute.
##
## The DS exports are unlit (KHR_materials_unlit), so the exporter wrote no
## normals — and Godot's glTF import does not generate them either: the
## render arrays come back with ARRAY_NORMAL = nil. The renderer then shades
## every fragment with the same default normal, so N·L is constant across a
## whole mesh — flat "ambient-only" lighting that flips when the object
## rotates instead of per-side diffuse shading. Every stage room and the
## player model are affected; the vertex-color bake masked it on rooms.
##
## The fix accumulates area-weighted face normals per vertex (the same
## math as three.js computeVertexNormals, which the LightingLab used) and
## rebuilds each mesh with the normals filled in. Low-poly DS geometry then
## gets seam-welding + Laplacian smoothing passes: vertices duplicated at
## texture-UV seams would otherwise each carry their own normal (a visible
## crease line), and big facets interpolate harshly between vertex normals —
## blending each vertex toward its neighbors' average softens both.
## Materials and surface names are carried over; blend-shape meshes are left
## untouched.

static func ensure(root: Node, smooth_passes: int = 1) -> int:
	var fixed := 0
	if root is MeshInstance3D:
		fixed += _fix_mesh(root as MeshInstance3D, smooth_passes)
	for child in root.get_children():
		fixed += ensure(child, smooth_passes)
	return fixed


static func _fix_mesh(mi: MeshInstance3D, smooth_passes: int) -> int:
	var mesh := mi.mesh
	if not (mesh is ArrayMesh):
		return 0
	var am := mesh as ArrayMesh
	if am.get_blend_shape_count() > 0:
		return 0

	var rebuilt := false
	var replacement := ArrayMesh.new()
	for s in range(am.get_surface_count()):
		var arrays := am.surface_get_arrays(s)
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals is PackedVector3Array and not (normals as PackedVector3Array).is_empty():
			replacement.add_surface_from_arrays(am.surface_get_primitive_type(s), arrays)
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var out := PackedVector3Array()
		out.resize(verts.size())
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
		# Position hash — seam-duplicated vertices (same position, separate
		# index for UV purposes) must share one normal or they leave a crease.
		var pos_to_rep := {}
		for i in range(verts.size()):
			var key := Vector3i(
				int(round(verts[i].x * 4096.0)),
				int(round(verts[i].y * 4096.0)),
				int(round(verts[i].z * 4096.0)))
			if not pos_to_rep.has(key):
				pos_to_rep[key] = i
		var neighbors: Array = []
		neighbors.resize(verts.size())
		for t in range(tri_count):
			var a: int = t * 3 if idx.size() == 0 else idx[t * 3]
			var b: int = t * 3 + 1 if idx.size() == 0 else idx[t * 3 + 1]
			var c: int = t * 3 + 2 if idx.size() == 0 else idx[t * 3 + 2]
			# Unnormalized cross = area-weighted accumulation, so big faces
			# dominate their vertices' normals — smooth shading.
			var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			out[a] += face
			out[b] += face
			out[c] += face
			# Edge adjacency through position representatives, so smoothing
			# crosses both index edges and UV-seam splits.
			var ra: int = pos_to_rep[_pos_key(verts[a])]
			var rb: int = pos_to_rep[_pos_key(verts[b])]
			var rc: int = pos_to_rep[_pos_key(verts[c])]
			_link(neighbors, ra, rb)
			_link(neighbors, ra, rc)
			_link(neighbors, rb, rc)
		for i in range(out.size()):
			var n := out[i]
			out[i] = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
		# Weld seam twins: one shared normal per position.
		for i in range(verts.size()):
			var rep: int = pos_to_rep[_pos_key(verts[i])]
			if rep != i:
				out[rep] += out[i]
		for i in range(verts.size()):
			var rep2: int = pos_to_rep[_pos_key(verts[i])]
			if rep2 != i:
				out[i] = out[rep2]
		for key in pos_to_rep:
			var r: int = pos_to_rep[key]
			out[r] = out[r].normalized() if out[r].length_squared() > 1e-10 else Vector3.UP
		# Laplacian smoothing: blend each vertex normal toward its neighbors'
		# average. Softens the harsh facets of big low-poly triangles.
		for pass_i in range(smooth_passes):
			var snapshot := out.duplicate()
			for i in range(out.size()):
				var rep: int = pos_to_rep[_pos_key(verts[i])]
				var adj = neighbors[rep]
				if adj == null or adj.is_empty():
					continue
				var avg := Vector3.ZERO
				for j in adj:
					avg += snapshot[j]
				avg /= float(adj.size())
				out[i] = (snapshot[i].lerp(avg, 0.5)).normalized()
		arrays[Mesh.ARRAY_NORMAL] = out
		replacement.add_surface_from_arrays(am.surface_get_primitive_type(s), arrays)
		rebuilt = true

	if not rebuilt:
		return 0
	for s in range(am.get_surface_count()):
		replacement.surface_set_material(s, am.surface_get_material(s))
		if am.surface_get_name(s) != "":
			replacement.surface_set_name(s, am.surface_get_name(s))
	mi.mesh = replacement
	return 1


static func _pos_key(v: Vector3) -> Vector3i:
	return Vector3i(
		int(round(v.x * 4096.0)),
		int(round(v.y * 4096.0)),
		int(round(v.z * 4096.0)))


static func _link(neighbors: Array, a: int, b: int) -> void:
	if a == b:
		return
	if neighbors[a] == null:
		neighbors[a] = []
	if not (neighbors[a] as Array).has(b):
		(neighbors[a] as Array).append(b)
