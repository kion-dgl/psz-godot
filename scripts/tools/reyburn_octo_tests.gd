extends RefCounted
## Boundary cases use recovered constants, not a recording of the new selector.
static func run(t: Node) -> void:
	var r := ReyburnController.new(3300,1650)
	t.assert_eq(r.budgets.part_budget,660,"Reyburn part budget uses base row, not actual HP")
	t.assert_eq(r.budgets.modifier_budget,1320,"Reyburn modifier budget uses base row")
	r.hit(1321,0,0.0,false)
	t.assert_eq(r.priority(9.0,0.0).id,1,"budget exhaustion has first priority")
	t.assert_true(not r.enhanced,"damage alone cannot enable modifier")
	r.notify(0)
	t.assert_true(r.enhanced,"notification enables modifier")
	r.finish(1)
	t.assert_eq(r.reaction_damage,0,"reaction counter clears at completion")
	t.assert_eq(r.cumulative_damage,1321,"reaction does not clear cumulative gate")
	r.hit(1,1,TAU * 0x2aaa / 65536.0,true)
	t.assert_eq(r.off_angle_hits,1,"inclusive recovered bearing threshold")
	t.assert_eq(r.budgets.part_budget,659,"part context reaches budget")
	r.off_angle_damage = 331
	t.assert_eq(r.priority(9.0,0.0).id,14,"off-angle damage precedes count/cumulative/spatial")
	r.off_angle_damage = 0
	r.off_angle_hits = 10
	t.assert_eq(r.priority(9.0,0.0).id,4,"ten side hits request tail")
	r.finish(4)
	t.assert_eq(r.priority(9.0,0.0).id,2,"cumulative gate follows tail")
	r.finish(2)
	t.assert_eq(r.priority(15.0,0.0).advance,1,"advancing bite band")
	t.assert_eq(r.priority(9.0,0.0).normal,1,"normal bite band")
	r.bite_blocked = true
	t.assert_eq(r.fallback(1,0).id,-1,"blocked fallback bite has no reroll")
	r.breath_timer = 0
	t.assert_eq(r.priority(40.0,0.0).id,6,"distant breath requires expired cooldown")
	var paced := ReyburnController.new(3300,1650)
	t.assert_eq(paced.priority(9.0,0.0,false).id,-1,"bite cooldown gates spatial priority")
	t.assert_eq(paced.fallback(1,0,false).id,-1,"bite cooldown also gates fallback")
	paced.budgets.modifier_budget = 0
	t.assert_eq(paced.priority(9.0,0.0,false).id,1,"bite cooldown preserves modifier reaction")
	var flight := ReyburnController.new(3300,1650)
	t.assert_eq(flight.flight_request().id,11,"first original flight is center breath")
	flight.finish(11,3)
	t.assert_eq(flight.flight_timer,1500,"flight timer resets at completion")
	t.assert_eq(flight.flight_request().id,9,"normal follow-up is claw, without fireballs")
	flight.enhanced = true
	t.assert_eq(flight.flight_request().id,10,"enhanced follow-up is spin, without fireballs")
	flight.finish(10,3)
	t.assert_eq(flight.flight_request().id,11,"spin returns to center-breath alternation")
	var horn := ReyburnController.new(3300,1650)
	horn.budgets.part_budget = 1
	horn.hit(4,1,0.0,true)
	t.assert_true(horn.bite_blocked,"original seeded-budget trace: head hit immediately disables bites")
	t.assert_eq(horn.budgets.part_budget,-3,"original head budget preserves overshoot")
	t.assert_eq(horn.priority(9.0,0.0).id,-1,"broken horn excludes normal bite")
	var o := OctoController.new()
	t.assert_eq(o.clamp_hp(-999,5220),2610,"lethal mode-zero hit clamps before death")
	o.latch(2610,5220)
	t.assert_eq(o.transition_step,0,"half HP latches without interrupting action")
	t.assert_eq(o.boundary(false),2,"body completion starts limb wait")
	t.assert_eq(o.boundary(false),2,"active limbs hold transition")
	t.assert_eq(o.boundary(true),14,"idle limbs allow withdrawal")
	o.change_mode()
	t.assert_eq(o.clamp_hp(-1,5220),-1,"mode one allows lethal during latched transition")
	t.assert_true(o.transition_latch,"mode changes before latch clears")
	t.assert_eq(o.boundary(true),18,"mode-one emergence retains latch")
	t.assert_eq(o.boundary(true),0,"emergence completion clears latch")
	for row in 2:
		t.assert_eq(o.projectile_variant(row,89),row,"90 percent selects row variant")
		t.assert_eq(o.projectile_variant(row,90),2,"upper ten percent selects variant two")
	o.mode = 0
	o.timers = [1800,750,0,0]
	t.assert_eq(o.select_request(true,false,-1,false),4,"strict mode-zero timer edges")
	o.timers[0] += 1
	t.assert_eq(o.select_request(true,true,-1,false),5,"timer C4 precedes limb predicate")
	o.mode = 1
	o.timers = [0,0,1800,601]
	o.hit_count = 11
	t.assert_eq(o.select_request(true,false,-1,false),13,"eleven hits precede D0 timer")
	t.assert_eq(o.select_request(true,false,0,false),15,"limb request precedes all mode-one timers")
