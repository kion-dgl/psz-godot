class_name MapCollisionBuilder
## Pure floor/map collision-building helpers, extracted from
## ValleyFieldController. These operate purely on passed-in nodes and hold no
## instance state, so they live here as static utilities (same shape as
## StageRotation).
##
## Two collision strategies:
##   - setup_map_collision(): the floor GLB already has StaticBody3D collision —
##     filter its trimesh to top faces only and tag layers.
##   - create_collision_from_meshes(): the floor GLB has no collision — build
##     StaticBody3D + trimesh shapes from its MeshInstance3D nodes.


static func setup_map_collision(root: Node) -> void:
	filter_floor_collision(root)
	configure_collision_nodes(root)


static func filter_floor_collision(node: Node) -> void:
	## Strip downward/sideways-facing triangles from ConcavePolygonShape3D so the
	## player doesn't get trapped between top and bottom faces of the floor slab.
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D:
			var trimesh := cs.shape as ConcavePolygonShape3D
			var faces := trimesh.get_faces()
			var filtered := PackedVector3Array()
			var kept := 0
			var dropped := 0
			for i in range(0, faces.size(), 3):
				var a := faces[i]
				var b := faces[i + 1]
				var c := faces[i + 2]
				var normal := (b - a).cross(c - a).normalized()
				if normal.y < -0.3:  # Keep top-surface triangles (GLTF winding convention)
					filtered.append(a)
					filtered.append(b)
					filtered.append(c)
					kept += 1
				else:
					dropped += 1
			if dropped > 0:
				var new_shape := ConcavePolygonShape3D.new()
				new_shape.set_faces(filtered)
				cs.shape = new_shape
				print("[ValleyField] Floor collision filtered: kept %d, dropped %d triangles" % [kept, dropped])
	for child in node.get_children():
		filter_floor_collision(child)


static func collect_collision_faces(node: Node, out: PackedVector3Array) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D:
			var trimesh := cs.shape as ConcavePolygonShape3D
			var local_faces := trimesh.get_faces()
			# Transform faces to global space
			var xform := cs.global_transform
			for i in range(local_faces.size()):
				out.append(xform * local_faces[i])
	for child in node.get_children():
		collect_collision_faces(child, out)


static func has_static_body(node: Node) -> bool:
	if node is StaticBody3D:
		return true
	for child in node.get_children():
		if has_static_body(child):
			return true
	return false


static func create_collision_from_meshes(root: Node) -> void:
	## Find MeshInstance3D nodes under `root` and build StaticBody3D + trimesh
	## collision. Used for both the floor GLB and obstacle GLBs.
	var meshes: Array[MeshInstance3D] = []
	collect_mesh_instances(root, meshes)
	print("[ValleyField] Found %d mesh instances for manual collision" % meshes.size())
	for mi in meshes:
		var mesh := mi.mesh
		if not mesh:
			continue
		var shape := mesh.create_trimesh_shape()
		if not shape:
			continue
		var static_body := StaticBody3D.new()
		static_body.name = "collision_floor"
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		var col_shape := CollisionShape3D.new()
		col_shape.shape = shape
		static_body.add_child(col_shape)
		# Preserve the mesh's global transform
		static_body.global_transform = mi.global_transform
		root.add_child(static_body)
		# Hide the visual mesh (collision only)
		mi.visible = false
		print("[ValleyField] Created trimesh collision from mesh '%s' (%d faces)" % [
			mi.name, mesh.get_faces().size() / 3])


static func collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		collect_mesh_instances(child, out)


static func configure_collision_nodes(node: Node) -> bool:
	var found_floor := false
	if node is StaticBody3D:
		if node.name == "collision_floor":
			found_floor = true
		# Skip trigger boxes and gate markers — not walls
		if str(node.name).begins_with("trigger_") or str(node.name).begins_with("gate_"):
			node.collision_layer = 0
			node.collision_mask = 0
		else:
			node.collision_layer = 1
			node.collision_mask = 0
	for child in node.get_children():
		if configure_collision_nodes(child):
			found_floor = true
	return found_floor
