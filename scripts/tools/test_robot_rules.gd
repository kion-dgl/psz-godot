extends RefCounted
static func run(t: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var shots: Array[int] = []
	for tick in 151:
		if RobotAttackRules.orbit_shoot(tick): shots.append(tick)
	t.assert_eq(shots,[0,22,44,66,88,110,132],"ov22 orbit cadence excludes terminal tick")
	for n in 100:
		var tick := rng.randi_range(0,220)
		t.assert_eq(RobotAttackRules.contact(11,tick),tick >= 7 and tick < 24,"split dive contact bounds")
		t.assert_eq(RobotAttackRules.contact(13,tick),tick >= 120 and tick < 149,"split drill contact bounds")
	t.assert_eq(RobotAttackRules.duration(8),150,"orbit returns at counter 150")
	t.assert_eq(RobotAttackRules.duration(11),54,"dive returns at counter 54")
	t.assert_eq(RobotAttackRules.duration(13),149,"drill closes and returns at 149")

	t.assert_eq(RobotAttackRules.parameters(5400,5400,0),[90,75,60,75,60,60],"normal full-HP ROM tuning")
	t.assert_eq(RobotAttackRules.parameters(0,5400,0),[60,60,45,60,45,52],"normal zero-HP endpoints")
	t.assert_eq(RobotAttackRules.parameters(2700,5400,0),[75,67,52,67,52,56],"Q12 truncation at half HP")
