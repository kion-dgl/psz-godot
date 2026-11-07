extends RefCounted
## Guard facing and scope regressions; live interaction lives in humar_saber_probe.
static func run(t: Node) -> void:
	var rules = preload("res://scripts/3d/player/humar_saber_prototype.gd")
	t.assert_true(rules.facing_guard(0, Vector3(0,0,2)), "saber guard accepts front")
	t.assert_true(not rules.facing_guard(0, Vector3(0,0,-2)), "saber guard rejects rear")
	t.assert_true(not rules.facing_guard(0, Vector3(2,0,0)), "saber guard rejects flank")
	t.assert_true(not rules.facing_guard(0, Vector3.ZERO), "saber guard requires a direction")
	t.assert_true(rules.facing_guard(PI, Vector3(0,0,-2)), "guard respects player facing")
	t.assert_true(rules.facing_guard(0, Vector3(1.7,0,1)), "guard accepts just inside cone")
	t.assert_true(not rules.facing_guard(0, Vector3(1.8,0,1)), "guard rejects just outside cone")
