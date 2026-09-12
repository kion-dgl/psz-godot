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
		# Winding consistency: two triangles sharing an edge (by position)
		# must traverse it in OPPOSITE directions. BFS-propagate flip flags
		# from that rule; backwards-wound triangles then contribute negated
		# face normals below instead of normals pointing into the surface.
		var flip_flags := PackedByteArray()
		flip_flags.resize(tri_count)
		var edge_tris := {}
		var tri_edges: Array = []
		tri_edges.resize(tri_count)
		for t in range(tri_count):
			var va: int = t * 3 if idx.size() == 0 else idx[t * 3]
			var vb: int = t * 3 + 1 if idx.size() == 0 else idx[t * 3 + 1]
			var vc: int = t * 3 + 2 if idx.size() == 0 else idx[t * 3 + 2]
			var edges := [
				[_pos_key(verts[va]), _pos_key(verts[vb])],
				[_pos_key(verts[vb]), _pos_key(verts[vc])],
				[_pos_key(verts[vc]), _pos_key(verts[va])],
			]
			tri_edges[t] = edges
			for e in edges:
				var ek := _edge_key(e[0], e[1])
				if not edge_tris.has(ek):
					edge_tris[ek] = []
				(edge_tris[ek] as Array).append(t)
		var visited := {}
		for seed_tri in range(tri_count):
			if visited.has(seed_tri):
				continue
			var component: Array = []
			var queue: Array = [seed_tri]
			visited[seed_tri] = true
			while not queue.is_empty():
				var t: int = queue.pop_front()
				component.append(t)
				for e in (tri_edges[t] as Array):
					var ek := _edge_key(e[0], e[1])
					var tris_on_edge: Array = edge_tris[ek]
					if tris_on_edge.size() != 2:
						continue
					var other: int = tris_on_edge[0] if tris_on_edge[1] == t else tris_on_edge[1]
					if visited.has(other):
						continue
					# Same-direction traversal of the shared edge → opposite
					# flip state; opposite traversal → same flip state.
					var mine_forward: bool = e[0] < e[1]
					var other_edge: Array = []
					for oe in (tri_edges[other] as Array):
						if _edge_key(oe[0], oe[1]) == ek:
							other_edge = oe
							break
					var other_forward: bool = other_edge[0] < other_edge[1]
					flip_flags[other] = flip_flags[t] if (mine_forward != other_forward) else (1 - flip_flags[t])
					visited[other] = true
					queue.append(other)
			# Global orientation for the component: islands can be
			# consistently wound yet globally backwards — normals into the
			# surface, forever unlit. Closed/curved islands: point normals
			# away from the island's own centroid. FLAT islands (walkway
			# planks, sheets) degenerate — the centroid lies in-plane, the
			# alignment dot is ~0 — so they use frame cues instead: face UP
			# if roughly horizontal, face the room center if vertical.
			var centroid := Vector3.ZERO
			var vert_count := 0
			var seen_verts := {}
			for t in component:
				for vi in _tri_indices(idx, t):
					if not seen_verts.has(vi):
						seen_verts[vi] = true
						centroid += verts[vi]
						vert_count += 1
			if vert_count > 0:
				centroid /= float(vert_count)
				var sum_face := Vector3.ZERO
				var total_area := 0.0
				for t in component:
					var tri := _tri_indices(idx, t)
					var fn := (verts[tri[1]] - verts[tri[0]]).cross(verts[tri[2]] - verts[tri[0]])
					if flip_flags[t]:
						fn = -fn
					sum_face += fn
					total_area += fn.length()
				var flip_island := false
				if total_area > 1e-9 and sum_face.length() > 0.95 * total_area:
					# Flat island — all faces nearly parallel.
					var n := sum_face.normalized()
					if absf(n.y) > 0.7:
						flip_island = n.y < 0.0
					else:
						flip_island = n.dot(-centroid) < 0.0
				else:
					var alignment := 0.0
					for t in component:
						var tri := _tri_indices(idx, t)
						var fn := (verts[tri[1]] - verts[tri[0]]).cross(verts[tri[2]] - verts[tri[0]])
						if flip_flags[t]:
							fn = -fn
						var fc := (verts[tri[0]] + verts[tri[1]] + verts[tri[2]]) / 3.0
						alignment += fn.dot(fc - centroid)
					flip_island = alignment < 0.0
				if flip_island:
					for t in component:
						flip_flags[t] = 1 - flip_flags[t]
		for t in range(tri_count):
			var a: int = t * 3 if idx.size() == 0 else idx[t * 3]
			var b: int = t * 3 + 1 if idx.size() == 0 else idx[t * 3 + 1]
			var c: int = t * 3 + 2 if idx.size() == 0 else idx[t * 3 + 2]
			# Unnormalized cross = area-weighted accumulation, so big faces
			# dominate their vertices' normals — smooth shading. The DS meshes
			# wind some triangles backwards (why several materials are
			# double-sided); the consistency pass flips those faces first so
			# their normals don't point into the surface.
			var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			if flip_flags[t]:
				face = -face
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
		# Stash the baked COLOR_0 so the neutralize pass can re-blend from
		# the authored values any number of times.
		var orig_color = arrays[Mesh.ARRAY_COLOR]
		if orig_color is PackedColorArray:
			replacement.set_meta("orig_color_%d" % s, (orig_color as PackedColorArray).duplicate())
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


static func _edge_key(a: Vector3i, b: Vector3i) -> String:
	# Order-independent key for an edge between two positions.
	var lo := a if a < b else b
	var hi := b if a < b else a
	return "%d,%d,%d|%d,%d,%d" % [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]


static func _link(neighbors: Array, a: int, b: int) -> void:
	if a == b:
		return
	if neighbors[a] == null:
		neighbors[a] = []
	if not (neighbors[a] as Array).has(b):
		(neighbors[a] as Array).append(b)


## DS GLBs import unshaded (KHR_materials_unlit) — lights can't touch them.
## Duplicate each surface material into a per-pixel-shaded override so
## dynamic light reaches the mesh. Returns the number of meshes touched.
static func make_lit(root: Node) -> int:
	var touched := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var changed := false
		for i in range(_surface_count(mi)):
			var mat := _active_material(mi, i)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				if std.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
					continue
				var dup := std.duplicate() as StandardMaterial3D
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mi.set_surface_override_material(i, dup)
				changed = true
		if changed:
			touched += 1
	for child in root.get_children():
		touched += make_lit(child)
	return touched


## Room albedo = texture × COLOR_0, and the snowfield bake is mostly dark
## (median luminance 0.19 — authored for another time of day). Worse: Godot
## imports these unlit glTF materials as SHADING_MODE_UNSHADED, so the room
## never responds to light at all — the bake IS the entire look. For the
## dynamic-rig strategy (#646: no baked-in lighting), strip the vertex-color
## modulation AND force per-pixel shading, so albedo = texture and the rig
## owns everything. Returns the number of meshes touched.
static func strip_vertex_albedo(root: Node) -> int:
	var touched := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var changed := false
		for i in range(_surface_count(mi)):
			var mat := _active_material(mi, i)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				if std.vertex_color_use_as_albedo and std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					var dup := std.duplicate() as StandardMaterial3D
					dup.vertex_color_use_as_albedo = false
					dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mi.set_surface_override_material(i, dup)
					changed = true
			elif mat is ShaderMaterial:
				# Mirror-wrap surfaces (snow ground among them) run
				# texture_fix_shader, whose ALBEDO multiplies COLOR.rgb.
				# NB: get_shader_parameter returns null for unset defaults —
				# gate on the shader's declared uniforms, not the value.
				var shader_mat := mat as ShaderMaterial
				if shader_mat.shader == null or not shader_mat.shader.has_uniform("use_vertex_color"):
					continue
				var dup := shader_mat.duplicate() as ShaderMaterial
				dup.set_shader_parameter("use_vertex_color", false)
				mi.set_surface_override_material(i, dup)
				changed = true
		if changed:
			touched += 1
	for child in root.get_children():
		touched += strip_vertex_albedo(child)
	return touched

## Iterate MESH surface count, not the override array — overrides only
## exist for surfaces some pass has already touched, so the override count
## silently skips every untouched surface (the planks bug: strips and
## make_lit never visited surfaces past the texture-fix overrides).
static func _surface_count(mi: MeshInstance3D) -> int:
	if mi.mesh is ArrayMesh:
		return (mi.mesh as ArrayMesh).get_surface_count()
	return mi.get_surface_override_material_count()

## The material actually used by surface i — the override when set, else the
## mesh's own surface material. NB: get_active_material() bounds-checks
## against the OVERRIDE array, which only grows as overrides are set, so it
## silently skips untouched surfaces past its length (the one-surface
## strip bug).
static func _active_material(mi: MeshInstance3D, i: int) -> Material:
	var override_mat := mi.get_surface_override_material(i)
	if override_mat != null:
		return override_mat
	if mi.mesh is ArrayMesh:
		return (mi.mesh as ArrayMesh).surface_get_material(i)
	return null

static func _tri_indices(idx: PackedInt32Array, t: int) -> Array:
	if idx.size() == 0:
		return [t * 3, t * 3 + 1, t * 3 + 2]
	return [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]

## The LightingLab's neutralize slider, ported: rewrite COLOR_0 blended
## toward white by k (0 = full authored bake, 1 = fully white — the no-bake
## strategy #646). Works for StandardMaterial3D and texture_fix_shader
## surfaces alike (white vertex colors modulate nothing), so it replaces
## strip_vertex_albedo. Meshes rebuild from the stashed originals —
## idempotent at any k. Returns meshes touched.
static func neutralize_vertex_colors(root: Node, k: float) -> int:
	var touched := 0
	if root is MeshInstance3D and root.mesh is ArrayMesh:
		var mi := root as MeshInstance3D
		var am := root.mesh as ArrayMesh
		var rebuilt := false
		var replacement := ArrayMesh.new()
		for s in range(am.get_surface_count()):
			var arrays := am.surface_get_arrays(s)
			var stash = am.get_meta("orig_color_%d" % s, null)
			if stash is PackedColorArray:
				var blended := PackedColorArray()
				var orig: PackedColorArray = stash
				blended.resize(orig.size())
				for i in range(orig.size()):
					blended[i] = orig[i].lerp(Color.WHITE, k)
				arrays[Mesh.ARRAY_COLOR] = blended
				replacement.add_surface_from_arrays(am.surface_get_primitive_type(s), arrays)
				replacement.set_meta("orig_color_%d" % s, orig)
				rebuilt = true
			else:
				replacement.add_surface_from_arrays(am.surface_get_primitive_type(s), arrays)
		if rebuilt:
			for s in range(am.get_surface_count()):
				replacement.surface_set_material(s, am.surface_get_material(s))
				if am.surface_get_name(s) != "":
					replacement.surface_set_name(s, am.surface_get_name(s))
			mi.mesh = replacement
			touched += 1
	for child in root.get_children():
		touched += neutralize_vertex_colors(child, k)
	return touched
