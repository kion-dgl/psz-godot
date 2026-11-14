extends RefCounted
## Two-layer regression suite for #371 city walkable boundaries:
##   1. Synchronous schema, polygon clipping/triangulation, opening-gap, and
##      inside/outside point checks on CityBoundaryBuilder + Market's sidecar.
##   2. Live PhysicsServer3D capsule `move_and_slide()` probes proving Market's
##      extruded perimeter and cutout walls block void walk-offs and props.

const Builder := preload("res://scripts/3d/city/city_boundary_builder.gd")


static func run(runner: Node) -> void:
	print("── City Walkable Boundaries (#371) ──")
	_test_schema_and_meshes(runner)
	_test_opening_wall_gaps(runner)
	_test_walkable_and_blocked_points(runner)


static func _test_schema_and_meshes(runner: Node) -> void:
	var cfg := Builder.load_config("market")
	runner.assert_true(not cfg.is_empty(), "market: boundary JSON loads")
	runner.assert_eq(str(cfg.get("areaId", "")), "market", "market: areaId matches")
	runner.assert_true(float(cfg.get("wallHeight", 0.0)) >= 2.5, "market: wallHeight >= 2.5m")
	var wall_faces := Builder.build_wall_faces(cfg)
	runner.assert_true(wall_faces.size() >= 36, "market: extrudes perimeter wall faces")
	var floor_faces := Builder.build_floor_faces(cfg)
	runner.assert_true(floor_faces.size() >= 9, "market: triangulates walkable floor")
	_assert_floor_normals_up(runner, "market", floor_faces)
	var holder := Node3D.new()
	var body := Builder.build_into(holder, cfg)
	runner.assert_true(body != null and body.collision_layer == 1, "market: StaticBody3D on layer 1")
	holder.free()


static func _assert_floor_normals_up(runner: Node, area_id: String, faces: PackedVector3Array) -> void:
	var all_up := true
	var tri_count := faces.size() / 3
	for t in range(tri_count):
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		if (b - a).cross(c - a).y <= 0.0:
			all_up = false
			break
	runner.assert_true(all_up, area_id + ": all floor triangle normals point +Y")


static func _test_opening_wall_gaps(runner: Node) -> void:
	var closed_cfg := {
		"floorY": 0.0,
		"wallHeight": 3.0,
		"perimeter": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
		"openings": [{"id": "portal", "edge": 0, "tStart": 0.2, "tEnd": 0.8, "portalOnly": true}],
	}
	var open_cfg := {
		"floorY": 0.0,
		"wallHeight": 3.0,
		"perimeter": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
		"openings": [{"id": "gap", "edge": 0, "tStart": 0.2, "tEnd": 0.8, "portalOnly": false}],
	}
	# 4 solid edges = 4 * 12 = 48 verts; splitting edge 0 into [0..0.2] + [0.8..1] = 5 quads = 60 verts.
	runner.assert_eq(Builder.build_wall_faces(closed_cfg).size(), 48, "portalOnly keeps solid backstop wall")
	runner.assert_eq(Builder.build_wall_faces(open_cfg).size(), 60, "non-portal opening splits edge into two wall spans")


static func _test_walkable_and_blocked_points(runner: Node) -> void:
	var market := Builder.load_config("market")
	for pt in [Vector2(0.98, 62.79), Vector2(0.98, 18.84), Vector2(-13.44, 55.0), Vector2(0.38, 14.43), Vector2(-13.44, 57.44), Vector2(0.0, 42.5)]:
		runner.assert_true(Builder.is_point_walkable(market, pt, 0.5), "market walkable at %s" % str(pt))
	for bad in [Vector2(20.0, 15.0), Vector2(0.98, 67.5), Vector2(-6.5, 43.0), Vector2(-6.3, 37.9), Vector2(-7.2, 48.0)]:
		runner.assert_true(not Builder.is_point_walkable(market, bad, 0.5), "market blocks %s" % str(bad))


static func run_physics_probe(runner: Node) -> void:
	print("── City Walkable Boundaries Live Physics Probe (#371) ──")
	await _probe_market_physics(runner)


static func _make_probe_world(runner: Node) -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(64, 64)
	runner.add_child(vp)
	return vp


static func _make_capsule_actor(parent: Node, pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_max_angle = 1.0
	body.floor_snap_length = 1.0
	body.safe_margin = 0.08
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	body.add_child(col)
	body.position = pos
	parent.add_child(body)
	return body


static func _drive_capsule(tree: SceneTree, actor: CharacterBody3D, dir: Vector3, steps: int) -> Vector3:
	for _i in range(steps):
		var vy := actor.velocity.y
		if actor.is_on_floor():
			if vy < 0.0:
				vy = 0.0
		else:
			vy -= 20.0 / 60.0
		actor.velocity = Vector3(dir.x * 7.0, vy, dir.z * 7.0)
		actor.move_and_slide()
		await tree.physics_frame
	return actor.global_position


static func _teleport_capsule(tree: SceneTree, actor: CharacterBody3D, pos: Vector3) -> void:
	actor.velocity = Vector3.ZERO
	actor.global_position = pos
	await tree.physics_frame
	await tree.physics_frame


static func _probe_market_physics(runner: Node) -> void:
	var vp := _make_probe_world(runner)
	var stage := Node3D.new()
	vp.add_child(stage)
	Builder.build_into(stage, Builder.load_config("market"))
	var actor := _make_capsule_actor(stage, Vector3(0.98, 0.2, 62.79))
	await runner.get_tree().physics_frame
	await runner.get_tree().physics_frame
	var south_end := await _drive_capsule(runner.get_tree(), actor, Vector3(0, 0, 1), 35)
	runner.assert_true(south_end.z < 65.6 and south_end.y > -0.2, "market physics: south gate wall stops player")
	await _teleport_capsule(runner.get_tree(), actor, Vector3(3.2, 0.2, 42.5))
	var planter_end := await _drive_capsule(runner.get_tree(), actor, Vector3(1, 0, 0), 25)
	runner.assert_true(planter_end.x < 4.5, "market physics: central avenue planter wall blocks +X")
	await _teleport_capsule(runner.get_tree(), actor, Vector3(-5.5, 0.2, 48.0))
	var crate_end := await _drive_capsule(runner.get_tree(), actor, Vector3(-1, 0, 0), 25)
	runner.assert_true(crate_end.x > -6.3, "market physics: west crate cutout blocks capsule")
	vp.queue_free()
	await runner.get_tree().physics_frame
