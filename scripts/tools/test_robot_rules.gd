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

	var growth = preload("res://scripts/utils/enemy_progression.gd")
	var resource = load("res://data/enemies/chaos_mobius.tres")
	for level in [1,15,100]:
		for tier in ["normal","hard","super-hard"]:
			var expected: int = {"normal":5400,"hard":10200,"super-hard":12000}[tier]
			t.assert_eq(growth.scaled(resource,level,tier).hp_base,expected,"Paru tier HP is independent of remake level")

	var motion = preload("res://scripts/3d/enemies/paru_robot_motion.gd")
	var start := Vector3(-6,0,0)
	var goal := Vector3(4,0,3)
	t.assert_eq(motion.burrow_position(start,goal,0),start,"burrow begins at robot location")
	t.assert_eq(motion.burrow_position(start,goal,210),goal,"emergence arrives at locked target")
	t.assert_true(motion.burrow_position(start,goal,120).y < -4,"burrow travels underground")
	for tick in [60,100,179]:
		t.assert_true(motion.submerged(tick),"burrow travel hides robot")
	for tick in [0,59,180,210,298]:
		t.assert_true(not motion.submerged(tick),"robot visible outside buried travel")
	t.assert_eq(motion.drill_mode(1),"hover","first drill attack hovers")
	t.assert_eq(motion.drill_mode(2),"burrow","second drill attack burrows")
	t.assert_eq(motion.drill_mode(3),"hover","third drill attack hovers before linking")
	t.assert_true(not motion.followup_shot(1,30,0),"most dashes do not shoot")
	t.assert_true(motion.followup_shot(3,30,0),"occasional dash followup fires")
	t.assert_true(motion.followup_shot(3,34,0),"normal followup second shot")
	t.assert_true(not motion.followup_shot(3,38,0),"normal followup capped at two")

	var drill_clips = load("res://data/boss_animations/paru_z_003u.tres")
	var idle: Animation = drill_clips.get_animation("z003_ve_wat_u")
	var drill_track := idle.find_track(NodePath("z_003u/Skeleton3D:put02"),Animation.TYPE_ROTATION_3D)
	t.assert_true(drill_track >= 0,"original put02 drill rotation survives export")
	if drill_track >= 0:
		t.assert_true(idle.track_get_key_count(drill_track) > 1,"drill has animated rotation keys")
