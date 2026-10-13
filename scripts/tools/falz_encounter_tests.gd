extends RefCounted
## Spatial contracts independent of rendering and the imported clips.
static func run(t: Node) -> void:
	for angle in [0.0, 0.7, 2.4]:
		var points: Array[Vector3] = []
		for index in 3:
			points.append(FalzOrbit.orbit_point(index, angle, 6.0, 1.0))
		for index in 3:
			t.assert_true(is_equal_approx(Vector2(points[index].x, points[index].z).length(), 6.0), "Falz balls share orbit radius")
			t.assert_true(is_equal_approx(points[index].distance_to(points[(index+1)%3]), sqrt(3.0)*6.0), "Falz balls remain equally spaced")
	t.assert_true(FalzOrbit.orbit_point(0, 0, 6, 0).is_equal_approx(Vector3(0,-0.5,0)), "retracted ball is below shadow center")
	t.assert_true(DarkFalzBoss.in_front(Vector3(0,0,5)), "Falz frontal attack reaches ahead")
	t.assert_true(not DarkFalzBoss.in_front(Vector3(0,0,-2)), "Falz frontal attack excludes rear")
	t.assert_true(not DarkFalzBoss.in_front(Vector3(8,0,1)), "Falz frontal attack excludes flanks")
	t.assert_true(not DarkFalzBoss.in_front(Vector3(0,0,12)), "Falz frontal attack has bounded reach")
	t.assert_true(DarkFalzBoss.SWIM_SPEED > DarkFalzBoss.WALK_SPEED, "low-health Falz moves faster")
