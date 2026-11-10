extends RefCounted
const Aim := preload("res://scripts/3d/player/combat_aim.gd")

static func run(r: Node) -> void:
	var aim := Aim.new()
	aim.change_mode("combat_aim")
	r.assert_true(aim.active and aim.mode == Aim.Mode.SHOULDER, "toggle enters shoulder mode")
	aim.change_mode("combat_aim")
	r.assert_true(not aim.active, "second toggle exits shoulder mode")
	aim.change_mode("combat_aim")
	aim.clear()
	r.assert_true(not aim.active, "blocked state clears mode")
	var rng := RandomNumberGenerator.new()
	rng.seed = 775
	for i in range(24):
		var yaw := rng.randf_range(-PI, PI)
		var forward := Aim.travel(Vector2.UP, yaw)
		var right := Aim.travel(Vector2.RIGHT, yaw)
		r.assert_true(absf(forward.dot(right)) < 0.0001, "strafe remains perpendicular to aim")
		r.assert_true(Aim.travel(Vector2(1, 1), yaw).length() <= 1.0001, "diagonal aim travel cannot accelerate")
	r.assert_true(is_equal_approx(Aim.travel(Vector2(0.25, 0), 1.0).length(), 0.25), "analog aim travel preserves small steps")

	var window: Array[float] = [0.4, 0.8]
	r.assert_eq(Aim.combo_prompt(1, 0.39, window, false, false), "WAIT", "aim cue does not invite an early fumble")
	for fraction in [0.4, 0.6, 0.8]:
		r.assert_eq(Aim.combo_prompt(2, fraction, window, false, false), "CLICK", "aim cue includes both real window boundaries")
	r.assert_eq(Aim.combo_prompt(1, 0.81, window, false, false), "MISSED", "closed aim combo window is not advertised")
	r.assert_eq(Aim.combo_prompt(1, 0.6, window, true, false), "MISSED", "early fumble remains visible inside timing window")
	r.assert_eq(Aim.combo_prompt(2, 0.9, window, false, true), "QUEUED", "accepted queue remains visible after window closes")
	r.assert_eq(Aim.combo_prompt(3, 0.6, window, false, false), "FINISHER", "finisher never offers a fourth hit")
	r.assert_eq(Aim.combo_prompt(0, 0.6, window, true, true), "FIRE", "interruption clears stale combo feedback")
