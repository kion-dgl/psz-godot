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
		if boss is ReyburnBoss:
			await _entrance(boss, player)
		boss.set_physics_process(false)
		player.set_physics_process(false)
		# Controlled stepping owns the player's processing state for this probe.
		if boss is OctoDiabloBoss: boss.presentation._player_processing = false
		boss.target = player
		player.current_state = player.PlayerState.DODGING
		player.dodge_timer = 0.0
		_check(boss.model != null and boss.animation_player != null,"original body and animation player: "+id)
		_check(boss.current_hp == boss.encounter_max_hp,"fresh encounter HP: "+id)
		_check(field._field_hud._boss_bar != null and field._field_hud._boss_bar.visible,"HUD on entry: "+id)
		if boss is OctoDiabloBoss:
			_check(field._slot.weather == "rain" and field._weather_node.emitting,"fresh Octo encounter restores storm")
		if attempt >= 2: await _autonomous(boss,player)
		elif boss is ReyburnBoss: await _reyburn(boss,player)
		else: await _octo(boss,player)
		await _snapshot_boss(id,boss)
		await _finish(boss,field,player)
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[reyburn-octo] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _entrance(boss: ReyburnBoss, player: Node3D) -> void:
	_check(boss.entrance != null, "Reyburn starts with a brief entrance")
	_check(player.current_state == player.PlayerState.CUTSCENE, "entrance holds player input")
	var camera := boss.get_viewport().get_camera_3d()
	_check(camera.global_position.distance_to(player.global_position) < 5.5, "intro camera stays close behind player")
	var hp := boss.current_hp
	boss.hurtbox.take_hit(999999, Vector3.ZERO, 9999)
	_check(boss.current_hp == hp, "entrance blocks damage before combat")
	var start := Time.get_ticks_msec()
	while boss.entrance != null and Time.get_ticks_msec() - start < 6000:
		await get_tree().physics_frame
	_check(boss.entrance == null, "entrance returns control within five seconds")
	_check(player.current_state == player.PlayerState.IDLE, "entrance releases player")
	_check(absf(boss._bearing()) < 0.01, "Reyburn lands facing the player")
	_check(boss._distance() >= 25.0, "landing leaves room outside advancing bite range")
	_check(boss.state_field == "track", "roar hands directly to combat scheduling")
	_check(boss.get_viewport().get_camera_3d().get_parent().get("target") == player, "entrance restores player camera")

func _reyburn(boss: ReyburnBoss, player: Node3D) -> void:
	_check(is_instance_valid(boss._horn) and boss._horn.visible,"separate original horn attached before break")
	await _snapshot_boss("reyburn-intact",boss,Vector3(12,7,16))
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
	player.global_position = boss.global_position + boss.global_basis.z*24.0
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
	await _pacing(boss,player)
	await preload("res://scripts/tools/reyburn_movement_probe.gd").run(self,boss,player)
	boss.controller.budgets.part_budget = 1
	boss._hurt_parts[1].take_hit(20,Vector3.ZERO,9999,"",0,true,"physical",player)
	_check(boss.controller.bite_blocked and not boss._horn.visible,"head damage breaks separate horn and suppresses bite")

func _pacing(boss: ReyburnBoss, player: Node3D) -> void:
	# Preserve checks for the optional reviewed pacing adapter.
	boss.original_ground_pacing = false
	boss.rotation.y = 0
	player.global_position = boss.global_position + Vector3(0,0,9)
	boss.controller.fallback_timer = 375
	boss.controller.flight_timer = 1500
	boss.start_request({"id":5,"normal":1,"advance":0})
	for tick in 150:
		boss._physics_process(1.0/30.0)
		if boss.sequence_id == -1: break
	_check(boss.pacing.rest_ticks == 75, "completed bite gives a 2.5-second rest")
	var position_before := boss.global_position
	for tick in 74: boss._physics_process(1.0/30.0)
	_check(boss.sequence_id == -1 and boss.global_position == position_before, "rest does not attack or close distance")
	for tick in 60: boss._physics_process(1.0/30.0)
	_check(boss.sequence_id != 5, "unchanged range cannot immediately repeat bite")
	boss.start_request({"id":5,"normal":2,"advance":1})
	boss._shoot()
	player._is_defeated = true
	boss._physics_process(1.0/30.0)
	_check(boss.state_field == "loaf" and boss.action_id == 4, "defeated player interrupts bite with idle")
	_check(boss._owned_shots.is_empty() and boss._sequence.is_empty(), "defeat clears outstanding shots and attacks")
	for tick in 240: boss._physics_process(1.0/30.0)
	_check(boss.state_field == "loaf" and boss.action_id == 4, "full HP cannot override the player defeat latch")
	player._is_defeated = false
	boss._physics_process(1.0/30.0)
	_check(boss.state_field == "track" and boss.pacing.rest_ticks > 0, "revived player gets a fresh pause")
	boss.original_ground_pacing = true
	await get_tree().physics_frame

func _octo(boss: OctoDiabloBoss, player: Node3D) -> void:
	boss.rng.seed = 20261012
	_check(boss.limbs.size() == 6,"six independent original tentacle rigs")
	for limb in boss.limbs:
		var first := 22 if limb.channel < 5 else 43
		var last := 43 if limb.channel < 5 else 57
		for id in range(first,last):
			var clip: String = str(boss.catalog.actions[id].stages[0].member).get_basename()
			_check(limb.player.has_animation(clip),"channel %d resolves %s" % [limb.channel,clip])
	await _octo_intro(boss)
	await get_tree().physics_frame # Flush deferred hurtbox exposure and bone attachments.
	_octo_joint_hit(boss,player)
	_octo_suction(boss,player,0)
	boss._execute_request(17)
	var heading := boss.rotation.y
	for tick in 60: boss._physics_process(1.0/30.0)
	_check(boss.limbs.slice(0,4).all(func(limb): return limb.model.visible),"spin keeps all four tentacles visible")
	_check(boss.body_state == "spin" and not is_equal_approx(heading,boss.rotation.y),"request 17 rotates body instead of shooting")
	for tick in 104: boss._physics_process(1.0/30.0)
	_check(boss.body_state == "idle","spin terminates at captured 164-update boundary")
	boss.rotation.y = 0
	await _octo_transition(boss,player)

func _octo_intro(boss: OctoDiabloBoss) -> void:
	_check(boss.position.length() < 0.01,"water boss stays at authored center instead of snapping to plank floor")
	# Fresh encounter: finish the real intro before attacking it.
	while boss.body_state == "intro":
		boss._physics_process(1.0/30.0)
		if boss.body_ticks == 25: _check(boss.limbs[1].model.visible and not boss.model.visible,"first intro rise precedes body")
		if boss.body_ticks == 90: _check(boss.limbs[0].model.visible and not boss.model.visible,"second intro rise precedes body")
		if boss.body_ticks == 180:
			_check(boss.model.visible,"body rises at intro update 180")
			_check(absf(boss._bearing()) < 0.01,"intro body faces player")
	_check(boss.body_state == "idle" and boss.model.visible,"intro completes and reveals body")
	_check(boss.limbs.slice(0,4).all(func(limb): return limb.model.visible),"intro reveals four short tentacles")
	_check(not is_instance_valid(boss.presentation._camera),"intro releases encounter camera")
	for index in 6:
		var part := boss._hurt_parts[index+1]
		_check(part.get_parent() is BoneAttachment3D,"limb hurt part follows animated joint %d" % index)
	for tick in 30: boss._physics_process(1.0/30.0)
	await _snapshot_boss("octo-center",boss)

func _octo_transition(boss: OctoDiabloBoss, player: Node3D) -> void:
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
	for limb in [boss.limbs[4],boss.limbs[5]]:
		_check(absf(limb.model.position.z) < 0.01 and absf(limb.model.position.x) > 4.0,"edge tentacle root flanks body")
	for sector in 8:
		var point := boss._edge_position(sector*PI/4.0)
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*12,point-Vector3.UP*12,1,[boss.get_rid()])
		_check(boss.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"edge body stays outside plank collision on side %d" % sector)
	await _snapshot_boss("octo-edge",boss)
	await _octo_edge(boss,player)

func _octo_edge(boss: OctoDiabloBoss, player: Node3D) -> void:
	_octo_suction(boss,player,1)
	boss._execute_request(12)
	boss._physics_process(1.0/30.0)
	_check(boss.limbs[4].action_id == 55 and boss.limbs[5].action_id == 55,"request 12 runs the two screw channels")
	var old_position := boss.global_position
	boss._execute_request(13)
	for tick in 120: boss._physics_process(1.0/30.0)
	_check(boss.global_position.distance_to(old_position) > 5.0 and boss.body_state == "idle","request 13 relocates to a different arena side")
	boss._execute_request(15)
	_check(boss.limbs[2].model.visible and boss.limbs[3].model.visible,"request 15 temporarily reveals short turning tentacles")
	for tick in 120: boss._physics_process(1.0/30.0)
	_check(not boss.limbs[2].model.visible and not boss.limbs[3].model.visible,"turn ends with only two long tentacles")
	player.current_state = player.PlayerState.IDLE
	GameState.set_hp(GameState.max_hp)
	player.apply_octo_poison(0)
	_check(player._ailments.effects.has("poison"),"ink poison installs on player")
	var hp_before: int = GameState.hp
	player._ailments.tick(player,4.99)
	_check(GameState.hp == hp_before,"poison waits the recovered 150-update interval")
	player._ailments.tick(player,0.02)
	_check(GameState.hp < hp_before,"poison damages after five seconds")
	player.clear_status_effects()
	_check(not player.has_status_effects(),"normal status cleanup clears ink poison")
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	player.apply_octo_poison(2)
	_check(not player.has_status_effects(),"dodge suppresses poison")
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
		_check(boss.action_id == 21,"death uses original abscnc descriptor")
		for tick in 110: boss._physics_process(1.0/30.0)
		_check(not boss.model.visible and not boss.is_queued_for_deletion(),"death sinks and hides before cleanup")
		for tick in 71: boss._physics_process(1.0/30.0)
		_check(boss.is_queued_for_deletion(),"death completes after 181 updates")
		_check(field._weather_node.emitting and field._slot.weather == "","defeat starts gradual rain clearing")
		_check(not is_instance_valid(boss.presentation._camera),"defeat releases encounter camera")
		await _snapshot_boss("octo-cleared",boss)
		await get_tree().create_timer(2.0).timeout
		_check(field._weather_node.amount_ratio > 0.0 and field._weather_node.amount_ratio < 1.0,"rain fades through intermediate intensity after boss cleanup")
		await get_tree().create_timer(2.2).timeout
		_check(not field._weather_node.emitting,"rain stops after fade completes")
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


func _octo_suction(boss: OctoDiabloBoss, player: Node3D, mode: int) -> void:
	# Independent oracle: measured action starts in the retained original trace.
	var expected: Array = [[12,0],[13,61],[15,152],[16,173],[17,189],[18,224],[2,265],[4,446],[1,467]] if mode == 0 else [[12,0],[13,61],[14,215],[3,246],[4,397],[1,420]]
	var observed: Array = []
	var counter := [0]
	var callback := func(id: int): observed.append([id,counter[0]])
	boss.action_started.connect(callback)
	boss._execute_request(5 if mode == 0 else 6)
	var start := boss.global_position
	player.global_position = start+boss.global_basis.z*(20.0 if mode == 0 else 6.0)
	player.current_state = player.PlayerState.IDLE
	GameState.set_hp(GameState.max_hp)
	var distance_before := player.global_position.distance_to(start)
	for tick in (492 if mode == 0 else 420):
		counter[0] = tick+1
		boss._physics_process(1.0/30.0)
		if counter[0] == 140:
			boss.presentation._update_wind(1.0/30.0)
			_check(boss.presentation._wind.visible and boss.presentation._wind_mesh.get_surface_count() == 1,"suction displays mouth wind during pull")
			_check(player.global_position.distance_to(start) < distance_before,"suction pulls player toward mouth")
		if counter[0] == 270:
			_check(absf(boss.global_position.distance_to(start)-(9.0 if mode == 0 else 0.0)) < 0.01,"only center suction recoils nine units")
	boss.presentation._update_wind(1.0/30.0)
	_check(not boss.presentation._wind.visible,"mouth wind stops after suction")
	boss.action_started.disconnect(callback)
	_check(observed.slice(0,expected.size()) == expected,"phase %d suction matches retained emulator action starts: %s" % [mode,str(observed)])
	_check(boss.global_position.distance_to(start) < 0.01,"suction returns to phase anchor")
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0


func _octo_joint_hit(boss: OctoDiabloBoss, player: Node3D) -> void:
	var joint := boss._hurt_parts[2].get_child(0) as CollisionShape3D
	var outward := joint.global_position-boss.global_position
	outward.y = 0
	outward = outward.normalized()
	player.global_position = joint.global_position+outward*2.0
	player.global_position.y = 0
	player.player_rotation = atan2(-outward.x,-outward.z)
	player._attack_damage_snapshot = {"damage":20,"accuracy":9999,"weapon_type":0,"max_targets":1,"hits":1}
	player._attack_hit_targets.clear()
	var before := boss.current_hp
	player._execute_attack_hit()
	_check(boss.current_hp < before,"actual melee reaches animated Octo joint and shared HP")
	var after := boss.current_hp
	player._execute_attack_hit()
	_check(boss.current_hp == after,"one melee swing cannot double-hit shared Octo parts")
