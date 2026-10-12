extends SceneTree
## Run: godot --headless --path . --script scripts/tools/test_boss_action_events.gd
## Oracle is the retained original-game breakpoint trace, not a mock controller.

const Events = preload("res://scripts/3d/enemies/boss_action_events.gd")
const Damage = preload("res://scripts/3d/enemies/boss_damage_rules.gd")
const CONTRACT := "res://data/re_reference/boss_behavior_contract.json"
var _failures := 0


func _initialize() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	_check_bites(contract)
	_check_reaction(contract)
	_check_spouts(contract)
	_check_damage(contract)
	print("Boss action events: 49 anchored emulator bite windows, spout and modifier notifications checked; %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_bites(contract: Dictionary) -> void:
	var actions: Array = contract["catalogs"]["boss_dragon"]["actions"]
	var run: Dictionary = {}
	for candidate: Dictionary in contract["runs"]:
		if "reyburn_budget_crossing" in str(candidate["trace"]): run = candidate
	_expect(not run.is_empty(), "original-game long trace is present")
	if run.is_empty(): return
	var checked := 0
	var unanchored := 0
	for window: Dictionary in run["observed_combat_windows"]:
		var shape := int(window["shape_index"])
		if shape != 7 and shape != 8:
			continue
		var action := 16 if shape == 7 else 17
		var start_tick := -1
		for animation_call: Dictionary in run["animation_calls"]:
			if int(animation_call["channel"]) == 0 and int(animation_call["action"]) == action and int(animation_call["tick"]) <= int(window["start_tick"]):
				start_tick = int(animation_call["tick"])
		if start_tick < 0:
			# The savestate starts mid-bite: its window duration is checked in RE,
			# but the missing pre-trace action start cannot anchor a replay.
			unanchored += 1
			continue
		var track := Events.new()
		track.begin(actions[action])
		var edges: Array[int] = []
		for tick in range(start_tick, int(window["end_tick"]) + 1):
			for event: Dictionary in track.sample(0, (tick - start_tick) * Events.ONE):
				if event["kind"] in ["window_start", "window_end"]:
					edges.append(tick)
		_expect(edges == [int(window["start_tick"]), int(window["end_tick"])], "bite window matches emulator ticks %s" % str(window))
		checked += 1
	_expect(checked == 49 and unanchored == 1 and checked + unanchored == 50, "every retained complete bite window was compared")


func _check_reaction(contract: Dictionary) -> void:
	var actions: Array = contract["catalogs"]["boss_dragon"]["actions"]
	# Notification 0 is what enables Reyburn's modifier, after action 2's reaction.
	var reaction := Events.new()
	reaction.begin(actions[2])
	var notified: Array[int] = []
	for frame in 70:
		for event: Dictionary in reaction.sample(0, frame * Events.ONE):
			if event["kind"] == "point" and int(event["event"]["type_class"]) == 4:
				notified.append(frame)
	_expect(notified == [int(contract["observed_checks"]["reyburn_reaction_notification_delay"])], "modifier notification matches captured reaction delay")
	# Interruption must release a live record exactly once; otherwise a boss can
	# retain an invisible damaging hitbox after switching actions or dying.
	var interrupted := Events.new()
	interrupted.begin(actions[16])
	interrupted.sample(0, 10 * Events.ONE)
	var releases := interrupted.begin(actions[4])
	_expect(releases.size() == 1 and releases[0]["interrupted"], "action replacement releases active combat record")
	_expect(interrupted.cancel().is_empty(), "idle has no leftover combat record")


func _check_spouts(contract: Dictionary) -> void:
	var spouts := 0
	for octo_run: Dictionary in contract["runs"]:
		if "octo_natural_crossing" not in str(octo_run["trace"]):
			continue
		for animation_call: Dictionary in octo_run["animation_calls"]:
			if int(animation_call["channel"]) != 0 or int(animation_call["action"]) != 10:
				continue
			var spout := Events.new()
			spout.begin(contract["catalogs"]["boss_octopus"]["actions"][10])
			var predicted_tick := -1
			for frame in 6:
				for event: Dictionary in spout.sample(0, frame * Events.ONE):
					if event["kind"] == "point" and int(event["event"].get("notification", -1)) == 0:
						predicted_tick = int(animation_call["tick"]) + frame
			var found := false
			for observed: Dictionary in octo_run["observed_notifications"]:
				if int(observed["tick"]) == predicted_tick and int(observed["notification"]) == 0:
					found = true
			_expect(found, "Octo spout notification matches emulator tick %d" % predicted_tick)
			spouts += 1
	_expect(spouts > 0, "Octo's spout path was exercised")


func _check_damage(contract: Dictionary) -> void:
	var budget_hits := 0
	var clamp_samples := 0
	for run: Dictionary in contract["runs"]:
		if "reyburn_budget_crossing" in str(run["trace"]):
			var budgets := Damage.ReyburnBudgets.new(int(contract["observed_checks"]["reyburn_base_hp"]))
			for sample: Dictionary in run["damage_replay"]:
				for hit: Dictionary in sample["hits"]:
					budgets.hit(int(hit["delta"]), int(hit["part"]))
					budget_hits += 1
				_expect(budgets.part_budget == int(sample["budgets"][0]) and budgets.modifier_budget == int(sample["budgets"][1]), "Reyburn damage budgets at original tick %d" % int(sample["tick"]))
		elif "octo_natural_crossing" in str(run["trace"]):
			for sample: Dictionary in run["damage_replay"]:
				var last_hit: Dictionary = sample["hits"][-1]
				var hp := Damage.octo_hp_after_hook(int(last_hit["hp_before_hook"]), int(sample["max_hp"]), int(sample["mode"]))
				_expect(hp == int(sample["hp"]), "Octo post-hit HP at original tick %d" % int(sample["tick"]))
				clamp_samples += 1
	_expect(budget_hits > 0 and clamp_samples > 0, "live damage fixtures were exercised")
	# Boundary cases not covered by the captured small party hits.
	var part := Damage.ReyburnBudgets.new(3300)
	_expect(not part.hit(-660, 0) and part.part_budget == 660, "ordinary body damage leaves part budget intact")
	_expect(part.hit(-660, 1) and part.part_budget == 0, "exact part-budget exhaustion triggers callback")
	_expect(not part.hit(-5, 1) and part.part_budget == 0 and part.modifier_budget == 0, "exhausted budgets stop; callback is not repeated")
	_expect(Damage.octo_hp_after_hook(-100, 5220, 0) == 2610, "mode zero clamps even lethal hits")
	_expect(Damage.octo_hp_after_hook(-100, 5220, 1) == -100, "mode one permits lethal hits")
	print("Boss damage rules: %d original Reyburn hits and %d Octo post-hit samples checked" % [budget_hits, clamp_samples])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
