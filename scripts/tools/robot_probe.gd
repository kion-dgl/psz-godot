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
		await _check_intro(boss,player)
		boss.set_physics_process(false)
		player.set_physics_process(false)
		player.current_state = player.PlayerState.DODGING
		boss.target = player
		_check(boss.robots.size() == 2,"two separate original models")
		_check(boss.current_hp == boss.encounter_max_hp,"fresh encounter HP")
		_check_reticles(boss,player)
		await _snapshot_drill(boss)
		var seen := [{},{}]
		var shots := false
		var observed: Dictionary = {}
		for tick in 1500:
			player.global_position = boss.global_position + Vector3(sin(tick/60.0)*6,0,cos(tick/60.0)*6)
			boss._physics_process(1.0/30.0)
			for i in 2: seen[i][boss.states[i]] = true
			shots = shots or not boss._owned_shots.is_empty()
			_observe_tactics(boss,observed)
			if tick%30 == 0: await get_tree().physics_frame
		_check(seen[0].has(12) and seen[1].has(8) and seen[1].has(11),"autonomous independent attack families")
		_check(shots,"paired projectile delivery exists")
		for action in ["burrow","hover","strafe","followup","warning","dig_effect"]:
			_check(bool(observed.get(action,false)),"autonomous tactic: "+action)
		_check(boss.robots[0].skeleton.find_bone("put02") >= 0,"original drill joint is present")
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
		_check(defeats[0] == 0,"rewards wait for victory cutscene")
		_check(boss.presentation.active,"victory camera active")
		await _snapshot("paru-victory")
		_check(boss._owned_shots.is_empty(),"death clears projectiles")
		for tick in 400:
			if not is_instance_valid(boss): break
			boss._physics_process(1.0/30.0)
			if tick%30 == 0: await get_tree().physics_frame
		await get_tree().physics_frame
		_check(not is_instance_valid(boss),"death animation completes")
		_check(defeats[0] == 1,"one defeat after both animations")
		_check(player.process_mode != Node.PROCESS_MODE_DISABLED,"victory restores control")
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[robot] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _check_intro(boss: ParuRobotBoss, player: Node3D) -> void:
	_check(not boss.intro_complete,"intro starts before combat")
	for frame in 3: await get_tree().physics_frame
	_check(boss.presentation.active,"intro camera active")
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED,"intro locks player control")
	var intro_hp := boss.current_hp
	boss._hurt_parts[0].take_hit(999999,Vector3.ZERO,9999)
	_check(boss.current_hp == intro_hp,"intro rejects damage")
	var camera_position: Vector3 = boss.presentation.camera.global_position
	for frame in 60: await get_tree().physics_frame
	_check(boss.presentation.camera.global_position.is_equal_approx(camera_position),"entrance camera stays behind player")
	for robot in boss.robots:
		var clip := robot.player.get_animation(robot.player.current_animation)
		var expected: Vector3 = clip.position_track_interpolate(0,robot.clock.frame_q12/4096.0/60.0)
		_check(robot.skeleton.get_bone_pose_position(0).is_equal_approx(expected),"entrance preserves original root animation")
	boss.set_physics_process(false)
	print("[robot] intro snapshot tick ",boss.cinematic_ticks," complete ",boss.intro_complete)
	await _snapshot("paru-intro")
	boss.set_physics_process(true)
	for frame in 900:
		await get_tree().physics_frame
		if boss.intro_complete: break
	_check(boss.intro_complete,"intro completes")
	_check(not boss.presentation.active,"intro restores camera/control")
	_check(player.process_mode != Node.PROCESS_MODE_DISABLED,"player control restored")
	_check(boss.encounter_max_hp == 5400,"normal HP has no area multiplier")

func _check_reticles(boss: ParuRobotBoss, player: Node3D) -> void:
	var saved_position := player.global_position
	for index in 2:
		var center: Vector3 = boss._hurt_parts[index].get_child(0).global_position
		player.global_position = center + Vector3(0,-1,-2)
		player.player_rotation = 0.0
		boss.show_reticle()
		_check(boss.selected_part == boss._hurt_parts[index],"reticle selects robot %d" % index)
		_check(boss._reticle.global_position.is_equal_approx(center),"reticle follows moving receiver")
		boss.hide_reticle()
	player.global_position = saved_position

func _observe_tactics(boss: ParuRobotBoss, seen: Dictionary) -> void:
	if not get_tree().get_nodes_in_group("robot_dig_effects").is_empty(): seen.dig_effect = true
	if boss.drill_buried and not seen.has("burrow"):
		seen.burrow = true
		_check(not boss.robots[0].model.visible,"submerged robot hidden")
		var hp := boss.current_hp
		boss._hurt_parts[0].take_hit(999,Vector3.ZERO,9999)
		_check(boss.current_hp == hp,"underground drill rejects damage")
		var scan := boss.hurtbox_in_cone(boss.robots[0].model.global_position,0.0,{"hit_h_dist":100,"hit_h_angle_deg":180,"hit_v_angle_deg":180})
		_check(scan.is_empty() or scan.hurtbox != boss._hurt_parts[0],"underground drill excluded from targeting")
	if boss.states[0] == 12 and boss.rounds == 1 and boss.robots[0].model.position.y > 1.0:
		seen.hover = true
	if boss.burrow_warning.visible: seen.warning = true
	if boss.states[1] == 9 and boss.lower_rounds % 3 == 2: seen.strafe = true
	if boss.states[1] == 11 and boss.lower_rounds % 3 == 0 and boss.counters[1] == 31:
		seen.followup = not boss._owned_shots.is_empty()

func _snapshot_drill(boss: ParuRobotBoss) -> void:
	if OS.get_environment("PSZ_BOSS_SCREENSHOTS").is_empty() or DisplayServer.get_name() == "headless": return
	var previous := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	get_tree().root.add_child(camera)
	var point := boss.robots[0].model.global_position
	camera.global_position = point+Vector3(4,3,7)
	camera.look_at(point+Vector3.UP)
	camera.make_current()
	await _snapshot("paru-drill")
	if is_instance_valid(previous): previous.make_current()
	camera.queue_free()
