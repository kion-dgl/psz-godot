extends "res://scripts/tools/probe_checks.gd"
## Runs real arena entry, independent attacks, shared damage, death and retry.
func _run() -> void:
	probe_label = "robot"
	for attempt in 2:
		SessionManager.enter_quest("debug_boss_chaos_mobius","normal")
		await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn",{
			"current_cell_pos":"0,0","spawn_edge":"","keys_collected":{}})
		var boss: ParuRobotBoss
		for frame in 600:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group("bosses"):
				if node is ParuRobotBoss: boss = node
			if boss: break
		_check(boss != null,"Paru dedicated controller spawned")
		if not boss: break
		var player := get_tree().get_first_node_in_group("player") as Node3D
		boss.set_physics_process(false)
		player.set_physics_process(false)
		player.current_state = player.PlayerState.DODGING
		boss.target = player
		_check(boss.robots.size() == 2,"two separate original models")
		_check(boss.current_hp == boss.encounter_max_hp,"fresh encounter HP")
		var seen := [{},{}]
		var shots := false
		for tick in 1500:
			player.global_position = boss.global_position + Vector3(sin(tick/60.0)*6,0,cos(tick/60.0)*6)
			boss._physics_process(1.0/30.0)
			for i in 2: seen[i][boss.states[i]] = true
			shots = shots or not boss._owned_shots.is_empty()
			if tick%30 == 0: await get_tree().physics_frame
		_check(seen[0].has(12) and seen[1].has(8) and seen[1].has(11),"autonomous independent attack families")
		_check(shots,"paired projectile delivery exists")
		var hp := boss.current_hp
		boss._hurt_parts[0].take_hit(500,Vector3.ZERO,9999,"",0,true,"physical",player)
		_check(boss.current_hp < hp,"channel 0 hit reaches shared owner")
		hp = boss.current_hp
		boss._hurt_parts[1].take_hit(500,Vector3.ZERO,9999,"",0,true,"physical",player)
		_check(boss.current_hp < hp,"channel 1 hit reaches shared owner")
		await _snapshot_boss("paru",boss)
		var defeats := [0]
		boss.died.connect(func(_boss): defeats[0] += 1)
		boss._hurt_parts[0].take_hit(999999,Vector3.ZERO,9999,"",0,true,"physical",player)
		boss._hurt_parts[0].take_hit(999999,Vector3.ZERO,9999,"",0,true,"physical",player)
		_check(defeats[0] == 1,"one defeat for two parts")
		_check(boss._owned_shots.is_empty(),"death clears projectiles")
		for tick in 400:
			if not is_instance_valid(boss): break
			boss._physics_process(1.0/30.0)
			if tick%30 == 0: await get_tree().physics_frame
		await get_tree().physics_frame
		_check(not is_instance_valid(boss),"death animation completes")
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[robot] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
