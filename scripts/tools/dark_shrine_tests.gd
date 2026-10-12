extends RefCounted
## Seeded boundary tests plus original-game Trinity timeline, callable by runner.

static func run(t: Node) -> void:
	_falz(t)
	_pieces(t)
	_timeline(t)
	_catch_up(t)
	_piece_stats(t)
	_arena_contract(t)
	preload("res://scripts/tools/mother_board_tests.gd").run(t)

static func _falz(t: Node) -> void:
	var rules := BossPhaseRules.FalzDamage.new()
	t.assert_eq(rules.hit(4300,8600,-4300),0,"Falz exact half is not a phase edge")
	t.assert_eq(rules.hit(4294,8600,-6),2,"Falz captured half crossing requests 2")
	t.assert_eq(rules.hit(4293,8600,-1),0,"Falz half reaction is one-shot")
	t.assert_eq(rules.hit(2150,8600,-2143),0,"Falz exact quarter is not a phase edge")
	t.assert_eq(rules.hit(2142,8600,-8),3,"Falz captured quarter crossing requests 3")
	t.assert_eq(rules.flags,6,"Falz retains both crossed flags")
	var skip := BossPhaseRules.FalzDamage.new()
	t.assert_eq(skip.hit(1000,8600,-7600),3,"large hit goes straight to quarter request")
	t.assert_eq(skip.hit(999,8600,-1),0,"quarter branch blocks delayed half request")
	t.assert_eq(skip.flags,4,"skipped half flag is not invented")
	var budget := BossPhaseRules.FalzDamage.new()
	t.assert_eq(budget.hit(8000,8600,-600),0,"damage budget reset does not emit reaction 1")
	t.assert_eq(budget.budget,0,"budget clears when accumulated damage reaches max/16")

static func _pieces(t: Node) -> void:
	t.assert_eq(BossPhaseRules.trinity_piece_request(3,2,0),3,"first piece loss requests reaction")
	t.assert_eq(BossPhaseRules.trinity_piece_request(2,1,0),4,"second piece loss requests body transition")
	t.assert_eq(BossPhaseRules.trinity_piece_request(3,0,0),4,"simultaneous loss cannot strand body phase")
	t.assert_eq(BossPhaseRules.trinity_piece_request(1,0,1),3,"transition already requested cannot repeat")
	t.assert_eq(BossPhaseRules.trinity_piece_request(1,0,3),0,"body phase ignores further registry changes")
	t.assert_eq(BossPhaseRules.trinity_piece_request(2,2,0),0,"unchanged count sends no request")

static func _timeline(t: Node) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/boss_behavior_contract.json"))
	var capture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/dark_shrine_bosses.json"))
	var actions: Array = source.catalogs.boss_mother.actions
	var ticks: Array[int] = [0]
	var notifications: Array[int] = []
	var ends: Array[int] = []
	var clock := BossActionClock.new()
	clock.event_fired.connect(func(record: Dictionary):
		if record.kind == "point" and int(record.event.get("notification",-1)) == 0:
			notifications.append(ticks[0]))
	clock.finished.connect(func(): ends.append(ticks[0]))
	clock.begin(actions[3])
	for tick in range(1,250):
		ticks[0] = tick
		clock.advance(1.0/30.0)
	var live: Dictionary = capture.trinity_body_capture
	t.assert_eq(notifications, [int(live.notifications[0][0])-int(live.actions[0][0])], "body activation frame matches seeded emulator trace")
	t.assert_eq(ends, [int(live.actions[1][0])-int(live.actions[0][0])], "full transition duration matches seeded emulator trace")
	for pair in [[9,151],[10,101],[11,51],[8,201]]:
		ends.clear()
		clock.begin(actions[pair[0]])
		for tick in range(1,260):
			ticks[0] = tick
			clock.advance(1.0/30.0)
		t.assert_eq(ends,[pair[1]],"Trinity body action %d duration matches emulator" % pair[0])
	var cycles: Array[int] = []
	clock.cycle_finished.connect(func(stage: int, cycle: int):
		if stage == 1: cycles.append(cycle))
	clock.begin(source.catalogs.boss_darkfalz.actions[17], {1:4})
	for tick in 120: clock.advance(1.0/30.0)
	t.assert_eq(cycles,[1,2,3,4],"explicit Falz charge budget exits looping stage")
	t.assert_true(not clock.running,"finite loop budget cannot hang attack sequence")

static func _catch_up(t: Node) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/boss_behavior_contract.json"))
	var actions: Array = data.catalogs.boss_mother.actions
	var clock := BossActionClock.new()
	var on_finished := func(): clock.begin(actions[8])
	clock.finished.connect(on_finished)
	clock.begin(actions[2])
	clock.advance(5.0) # 150 updates: reaction 61, then 89 laser updates.
	t.assert_eq(clock.stage,2,"catch-up crosses both laser windup stages")
	t.assert_eq(clock.frame_q12,4 * 4096,"catch-up preserves elapsed time across action change")
	clock.finished.disconnect(on_finished)

static func _piece_stats(t: Node) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/boss_behavior_contract.json"))
	var source := EnemyData.new()
	source.id = "mother_piece"
	var tiers := ["normal", "hard", "super-hard"]
	for tier in 3:
		var scaled := preload("res://scripts/utils/enemy_progression.gd").scaled(
			source, 1 + tier * 30, tiers[tier], data.catalogs.boss_mother_piece.stats)
		t.assert_eq(scaled.hp_base, [1600,3850,5000][tier], "piece HP uses its own ROM difficulty row")
		t.assert_eq(scaled.attack_base, [450,950,1300][tier], "piece attack is independent of body stats")
		t.assert_true(scaled.original_attack_stats, "piece damage uses recovered-stat combat calculation")


static func _arena_contract(t: Node) -> void:
	var quest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/debug_boss_mother_trinity.json"))
	var cell: Dictionary = quest.sections[0].cells[0]
	t.assert_eq(quest.area_id, "dark", "Trinity uses Shrine progression and music")
	t.assert_eq(cell.stage_id, "s07z_na1", "Trinity arena is the broken-platform stage")
	t.assert_eq(cell.objects[0].position, [0.0,0.0,-10.0], "Trinity starts in the north cutout")
	var boss := MotherTrinityBoss.new()
	var player := Node3D.new()
	var root := Node3D.new()
	t.add_child(root)
	root.add_child(player)
	boss.enemy_data = EnemyRegistry.get_enemy("mother_trinity")
	root.add_child(boss)
	boss.set_physics_process(false)
	boss.position = MotherTrinityBoss.ARENA_ANCHOR
	boss.target = player
	for offset in [Vector3(7,0,4), Vector3(-7,0,4), Vector3(0,0,8)]:
		player.position = offset
		boss._aim_at_target()
		t.assert_true(boss.rotation.is_zero_approx(), "Trinity keeps fixed facing across player positions")
	boss.is_alive = false # Deferred piece spawn must not run for this geometry-only test.
	root.queue_free()
