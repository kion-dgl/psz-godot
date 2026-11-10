extends RefCounted
const Aim := preload("res://scripts/3d/player/combat_aim.gd")

static func run(r: Node) -> void:
	var aim := Aim.new()
	aim.update_hold(true, true)
	r.assert_true(aim.active, "aim admits a held input while allowed")
	aim.update_hold(true, false)
	r.assert_true(not aim.active, "overlay/death clears aim immediately")
	aim.update_hold(true, true)
	r.assert_true(not aim.active, "closing overlay with trigger held cannot re-enter aim")
	aim.update_hold(false, true)
	aim.update_hold(true, true)
	r.assert_true(aim.active, "release then press re-arms aim")
	var rng := RandomNumberGenerator.new()
	rng.seed = 775
	for i in range(24):
		var yaw := rng.randf_range(-PI, PI)
		var forward := Aim.travel(Vector2.UP, yaw)
		var right := Aim.travel(Vector2.RIGHT, yaw)
		r.assert_true(absf(forward.dot(right)) < 0.0001, "strafe remains perpendicular to aim")
		r.assert_true(Aim.travel(Vector2(1, 1), yaw).length() <= 1.0001, "diagonal aim travel cannot accelerate")
	r.assert_true(is_equal_approx(Aim.travel(Vector2(0.25, 0), 1.0).length(), 0.25), "analog aim travel preserves small steps")
