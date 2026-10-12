extends RefCounted
## Seeded boundary tests plus original-game Trinity timeline, callable by runner.

static func run(t: Node) -> void:
	_falz(t)
	_pieces(t)
	_timeline(t)

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
