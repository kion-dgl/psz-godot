extends "res://scripts/tools/probe_checks.gd"
## Actual packaged arena/rig/hurtbox/HUD/death/retry, plus controlled timelines.
func _run() -> void:
	probe_label = "reyburn-octo"
	for attempt in 4:
		var id: String = ["reyburn","octo_diablo"][attempt%2]
		SessionManager.enter_quest("debug_boss_"+id,"normal")
		await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn",{
			"current_cell_pos":"0,0","spawn_edge":"","keys_collected":{}})
		var boss: DescriptorBoss
		for frame in 600:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group("bosses"):
				if node is DescriptorBoss and node.is_alive: boss = node
			if boss: break
		if not boss:
			_check(false,"dedicated boss spawned: "+id)
			break
		await get_tree().create_timer(0.1).timeout
		var field := get_tree().current_scene
		var player := get_tree().get_first_node_in_group("player") as Node3D
		boss.set_physics_process(false)
		player.set_physics_process(false)
		boss.target = player
		player.current_state = player.PlayerState.DODGING
		player.dodge_timer = 0.0
		_check(boss.model != null and boss.animation_player != null,"original body and animation player: "+id)
		_check(boss.current_hp == boss.encounter_max_hp,"fresh encounter HP: "+id)
		_check(field._field_hud._boss_bar != null and field._field_hud._boss_bar.visible,"HUD on entry: "+id)
		if attempt >= 2: await _autonomous(boss,player)
		elif boss is ReyburnBoss: await _reyburn(boss,player)
		else: await _octo(boss,player)
		await _snapshot_boss(id,boss)
		await _finish(boss,field,player)
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[reyburn-octo] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _reyburn(boss: ReyburnBoss, player: Node3D) -> void:
	boss.rng.seed = 20261012
	var hp := boss.current_hp
	var budget := boss.controller.budgets.part_budget
	player.global_position = boss.global_position + Vector3(12,0,0)
	boss.rotation.y = 0
	boss._hurt_parts[1].take_hit(20,Vector3.ZERO,9999,"",0,true,"physical",player)
	_check(boss.current_hp < hp and boss.controller.budgets.part_budget < budget,"head hurtbox feeds shared HP and part budget")
	_check(boss.controller.off_angle_hits == 1,"source-bearing damage reaches side-hit counter")
	_check(boss.current_state != EnemyBase.EnemyState.HURT,"hits preserve boss action")
	# Real melee cone selects the head's hurt part, deduplicating the HP owner.
	var head := boss._hurt_parts[1].get_child(0) as CollisionShape3D
	var forward := boss.global_basis.z
	player.global_position = head.global_position + forward*6.0 - Vector3.UP
	player.player_rotation = atan2(-forward.x,-forward.z)
	player._attack_damage_snapshot = {"damage":20,"accuracy":9999,"weapon_type":0,"max_targets":1,"hits":1}
	player._attack_hit_targets.clear()
	var head_budget := boss.controller.budgets.part_budget
	player._execute_attack_hit()
	_check(boss.controller.budgets.part_budget < head_budget,"player melee selects animated head part")
	var hp_after := boss.current_hp
	player._execute_attack_hit()
	_check(boss.current_hp == hp_after,"same swing cannot hit a second part of shared owner")
	boss.controller.budgets.modifier_budget = 0
	boss.start_request({"id":1})
	for tick in 66: boss._physics_process(1.0/30.0)
	_check(not boss.controller.enhanced,"modifier remains off before frame 67")
	boss._physics_process(1.0/30.0)
	_check(boss.controller.enhanced,"frame 67 notification enables modifier")
	var actions: Array[int] = []
	var ticks: Array[int] = [0]
	var bite_calls: Array = []
	boss.action_started.connect(func(id):
		actions.append(id)
		if id in [16,17,4]: bite_calls.append([ticks[0],id]))
	boss.start_request({"id":5,"normal":2,"advance":1})
	for tick in 220:
		ticks[0] = tick+1
		boss._physics_process(1.0/30.0)
	if bite_calls.size() >= 4:
		_check(bite_calls[1][0]-bite_calls[0][0] == 27 and bite_calls[2][0]-bite_calls[1][0] == 27 and bite_calls[3][0]-bite_calls[2][0] == 52,"bite restart intervals match emulator 331/358/385/437")
	_check(_contains_chain(actions,[16,16,17,4]),"normal/advancing bite counts execute in order")
	boss._clear_deliveries()
	boss.start_request({"id":6,"types":[0],"counts":[1]})
	for tick in 160:
		boss._physics_process(1.0/30.0)
		if boss._owned_shots.size() == 3: break
	_check(boss._owned_shots.size() == 3,"notification releases three-shot heading fan")
	if boss._owned_shots.size() == 3:
		var a: Vector3 = boss._owned_shots[0].dir
		var b: Vector3 = boss._owned_shots[1].dir
		_check(absf(a.angle_to(b)-TAU*0x0e38/65536.0) < 0.001,"fan spacing uses recovered turn units")
	boss._clear_deliveries()
	# Every recovered sequence must terminate; no animation/loop deadlocks.
	for id in 16:
		boss.start_request({"id":id,"duration":150,"types":[0,1],"counts":[1,1]})
		var completed := false
		for tick in 1800:
			boss._physics_process(1.0/30.0)
			if boss.sequence_id == -1:
				completed = true
				break
		_check(completed,"Reyburn sequence %d completes" % id)
		boss._clear_deliveries()
		await get_tree().physics_frame
	boss.start_request({"id":5,"normal":1,"advance":0})
	for tick in 15: boss._physics_process(1.0/30.0)

func _octo(boss: OctoDiabloBoss, player: Node3D) -> void:
	boss.rng.seed = 20261012
	_check(boss.limbs.size() == 6,"six independent original tentacle rigs")
	for limb in boss.limbs:
		var first := 22 if limb.channel < 5 else 43
		var last := 43 if limb.channel < 5 else 57
		for id in range(first,last):
			var clip: String = str(boss.catalog.actions[id].stages[0].member).get_basename()
			_check(limb.player.has_animation(clip),"channel %d resolves %s" % [limb.channel,clip])
	boss._execute_request(4)
	for tick in 80:
		boss._physics_process(1.0/30.0)
		if not boss._owned_shots.is_empty(): break
	_check(not boss._owned_shots.is_empty(),"body spout emits at original notification")
	boss.limbs[0].play([28,{"id":30,"ticks":62},29,33,27])
	boss.hurtbox.take_hit(999999,Vector3.ZERO,9999,"",0,true,"physical",player)
	_check(boss.is_alive and boss.current_hp == boss.encounter_max_hp/2,"lethal hit clamps at half without death")
	_check(boss.controller.transition_latch and boss.controller.transition_step == 0,"half crossing waits for active body boundary")
	var steps: Array[int] = [0]
	var mode_while_latched := false
	for tick in 900:
		boss._physics_process(1.0/30.0)
		var step := boss.controller.transition_step
		if step != steps.back(): steps.append(step)
		if boss.controller.mode == 1 and boss.controller.transition_latch: mode_while_latched = true
		if boss.controller.mode == 1 and not boss.controller.transition_latch: break
	_check(steps == [0,2,14,18,0],"transition follows body/limb completion boundaries")
	_check(mode_while_latched,"mode switches before latch clears")
	_check(boss.limbs[4].model.visible and boss.limbs[5].model.visible,"long tentacles emerge in mode one")
	boss._execute_request(13)
	boss._physics_process(1.0/30.0)
	_check(boss.limbs[4].action_id == 55 and boss.limbs[5].action_id == 55 and boss.action_id == 1,"two screw channels run independently of body idle")
	for tick in 30: boss._physics_process(1.0/30.0)
	await get_tree().physics_frame

func _finish(boss: DescriptorBoss, field: Node, player: Node3D) -> void:
	var deaths: Array[int] = []
	boss.died.connect(func(_enemy): deaths.append(1))
	boss._shoot()
	var shots := boss._owned_shots.duplicate()
	boss.hurtbox.take_hit(999999,Vector3.ZERO,9999,"",0,true,"physical",player)
	var experience: int = CharacterManager.get_active_character().experience
	boss._die()
	boss._shoot()
	_check(deaths.size() == 1 and experience == CharacterManager.get_active_character().experience,"death and rewards exactly once")
	_check(not field._field_hud._boss_bar.visible,"death hides HUD")
	await get_tree().process_frame
	_check(boss._owned_shots.is_empty() and shots.all(func(n): return not is_instance_valid(n)),"death clears all projectiles")
	if boss is OctoDiabloBoss:
		_check(boss.limbs.all(func(limb): return not limb.clock.running),"death stops every limb channel")
	field._check_room_clear()
	field._check_room_clear()
	var exits: Array = field._map_root.get_children().filter(func(n): return n is Telepipe)
	_check(exits.size() == 1,"one return warp after repeated clear")

func _contains_chain(actions: Array[int], expected: Array) -> bool:
	for start in actions.size():
		if actions.slice(start,start+expected.size()) == expected: return true
	return false



func _autonomous(boss: DescriptorBoss, player: Node3D) -> void:
	# No action/state/phase injection: scheduler runs from fresh arena entry.
	# Scripted orbit and real damage calls isolate AI progress from player skill.
	var seen: Dictionary = {}
	boss.action_started.connect(func(id): seen[id] = true)
	var progressed := false
	for tick in 12000:
		var angle := float(tick/180) * PI/2.0
		player.global_position = boss.global_position + Vector3(sin(angle)*15,0,cos(angle)*15)
		if tick > 1600 and tick%45 == 0 and boss.current_hp > boss.encounter_max_hp/10:
			boss.hurtbox.take_hit(150,Vector3.ZERO,9999,"",0,true,"physical",player)
		boss._physics_process(1.0/30.0)
		var phase: bool = boss.controller.enhanced if boss is ReyburnBoss else boss.controller.mode == 1 and not boss.controller.transition_latch
		if phase and boss.current_hp <= boss.encounter_max_hp/10:
			progressed = true
			break
		if tick%30 == 0: await get_tree().physics_frame
	_check(progressed and boss.is_alive,"autonomous scheduler reaches late phase through actual damage")
	_check(seen.size() >= 5,"autonomous scheduler executes multiple body actions")
