extends "res://scripts/tools/probe_checks.gd"
func _run() -> void:
	probe_label = "humilias"
	for attempt in 2:
		SessionManager.enter_quest("debug_boss_humilias","normal")
		await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn",{
			"current_cell_pos":"0,0","spawn_edge":"","keys_collected":{}})
		var boss: HumiliasBoss
		for frame in 600:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group("bosses"):
				if node is HumiliasBoss: boss = node
			if boss: break
		_check(boss != null,"Humilias dedicated controller in Arca")
		if not boss: break
		var player := get_tree().get_first_node_in_group("player") as Node3D
		boss.set_physics_process(false)
		player.set_physics_process(false)
		player.current_state = player.PlayerState.DODGING
		boss.target = player
		_check(boss.catalog.identity[0].rom_id == 65,"source65 catalog, not Mother Trinity")
		_check(boss.current_hp == boss.encounter_max_hp,"fresh HP on entry/retry")
		await _battle(boss,player)
		await _snapshot_boss("humilias",boss)
		await _defeat(boss,player)
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[humilias] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _battle(boss: HumiliasBoss, player: Node3D) -> void:
	var actions: Dictionary = {}
	var modes: Dictionary = {}
	var recombined := false
	var floor_active := false
	var shots := false
	boss.action_started.connect(func(id): actions[id] = true)
	for tick in 5400:
		player.global_position = boss.global_position+Vector3(sin(tick/100.0)*6,0,cos(tick/100.0)*6)
		if tick >= 2400 and tick%30 == 0 and boss.current_hp > boss.encounter_max_hp*70/100 and boss.mode == "combined":
			boss.hurtbox.take_hit(2000,Vector3.ZERO,9999,"",0,true,"physical",player)
		boss._physics_process(1.0/30.0)
		modes[boss.mode] = true
		if modes.has("split") and boss.mode == "combined": recombined = true
		shots = shots or not boss._owned_shots.is_empty()
		for cell in 9: floor_active = floor_active or boss.grid.damaging(cell)
		if tick%30 == 0: await get_tree().physics_frame
	_check(actions.has(22) and actions.has(25),"both original gun chains")
	_check(actions.has(28) and actions.has(32) and actions.has(37),"drill and sweep chains")
	_check(shots,"gun projectiles")
	_check(floor_active,"autonomous spatial floor hazards")
	_check(modes.has("split") and recombined,"damage-gated split and paired recombine")
	_check(boss.current_hp < boss.encounter_max_hp,"damage retained across forms")
	_check(boss.split_count == 1,"one threshold consumed")

func _defeat(boss: HumiliasBoss, player: Node3D) -> void:
	var defeats := [0]
	boss.died.connect(func(_boss): defeats[0] += 1)
	boss.hurtbox.take_hit(999999,Vector3.ZERO,9999,"",0,true,"physical",player)
	boss._die()
	_check(defeats[0] == 1,"one defeat across forms")
	_check(boss._owned_shots.is_empty() and boss.grid.counters.all(func(n): return n == -1),"death clears shots and floor hazards")
	for tick in 400:
		if not is_instance_valid(boss): break
		boss._physics_process(1.0/30.0)
		if tick%30 == 0: await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not is_instance_valid(boss),"paired death presentation completes")
