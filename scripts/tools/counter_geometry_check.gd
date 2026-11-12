extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var stage = load("res://assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb").instantiate()
	root.add_child(stage)
	var repair = load("res://scripts/3d/city/counter_geometry.gd")
	assert(repair.apply(stage) == 92)
	assert(repair.apply(stage) == 0)
	# Rays through both sides of the former overlap must hit exactly one
	# water triangle, with no gap or change in waterline across the seam.
	var water_checks := 0
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s)
			if material.resource_name != "mizu_COLOR_0":
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for x in [-10.3, 10.3]:
				for z in [89.0, 90.4, 90.7, 92.0, 93.5, 95.0]:
					var hits := 0
					for i in range(0, ids.size(), 3):
						var hit = Geometry3D.ray_intersects_triangle(Vector3(x, 0, z), Vector3.DOWN,
							mi.global_transform * positions[ids[i]], mi.global_transform * positions[ids[i+1]],
							mi.global_transform * positions[ids[i+2]])
						if hit != null:
							hits += 1
							assert(absf(hit.y + 11.9163) < 0.001, "Waterline steps at the join")
					assert(hits == 1, "Water gap or overlap at %s: %d hits" % [Vector2(x,z), hits])
					water_checks += 1
	assert(water_checks == 12)
	var triangles = []
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		var mi = node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var a = mi.mesh.surface_get_arrays(s)
			var vs = a[Mesh.ARRAY_VERTEX]
			var indices = a[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				triangles.append([mi.global_transform * vs[indices[i]],mi.global_transform * vs[indices[i+1]],mi.global_transform * vs[indices[i+2]]])
	_check_lantern_roofs(triangles)
	var checks = 0
	for z in [109.252,149.479,161.252,173.029]:
		for sign_x in [-1,1]:
			var x = sign_x * (2.516 if z < 110 else 3.066)
			for sign_z in [-1,1]:
				var origin = Vector3(x,-10,z + sign_z*2)
				var direction = Vector3(0,0,-sign_z)
				var nearest = INF
				for tri in triangles:
					var hit = Geometry3D.ray_intersects_triangle(origin,direction,tri[0],tri[1],tri[2])
					if hit != null:
						nearest = min(nearest, origin.distance_to(hit))
				assert(nearest < 2.0, "Pillar has an open side at %s: %f" % [origin,nearest])
				checks += 1
	# Probe the new submerged foundation and the previously open bridge edge.
	# The close hit must be a local support face, not the distant room wall.
	for probe in [
		[Vector3(-6, -11.3, 105), Vector3(-1, 0, 1).normalized(), 5.0],
		[Vector3(-6, -11.3, 115), Vector3(-1, 0, -1).normalized(), 3.0],
		[Vector3(8, -11.3, 106), Vector3(1, 0, 1).normalized(), 4.0],
		[Vector3(14, -11.3, 114), Vector3(-1, 0, -1).normalized(), 4.0],
	]:
		var nearest := INF
		for tri in triangles:
			var hit = Geometry3D.ray_intersects_triangle(probe[0], probe[1], tri[0], tri[1], tri[2])
			if hit != null:
				nearest = min(nearest, probe[0].distance_to(hit))
		assert(nearest < probe[2], "Missing foundation/bridge face at %s" % probe[0])
	print("PASS: %d pillar-side, 4 foundation/bridge and %d water ray checks; 92 added faces; 4 lantern roof rays; repeated application is a no-op" % [checks, water_checks])
	quit()

func _check_lantern_roofs(triangles: Array) -> void:
	for center in [Vector2(10.7421875, 105.5098495), Vector2(16.25, 111.0215683)]:
		for side in [-1, 1]:
			var origin := Vector3(center.x + 0.1, -6.5, center.y + side * 0.3)
			var nearest := INF
			for tri in triangles:
				var hit = Geometry3D.ray_intersects_triangle(origin, Vector3.DOWN, tri[0], tri[1], tri[2])
				if hit != null: nearest = minf(nearest, origin.distance_to(hit))
			assert(nearest < 1.3, "Lantern roof missing at %s" % origin)
