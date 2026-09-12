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
## rebuilds each mesh with the normals filled in. Materials and surface
## names are carried over; blend-shape meshes are left untouched.

static func ensure(root: Node) -> int:
	var fixed := 0
	if root is MeshInstance3D:
		fixed += _fix_mesh(root as MeshInstance3D)
	for child in root.get_children():
		fixed += ensure(child)
	return fixed


static func _fix_mesh(mi: MeshInstance3D) -> int:
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
		for i in range(out.size()):
			var n := out[i]
			out[i] = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
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
