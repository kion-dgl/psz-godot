extends "res://scripts/tools/probe_checks.gd"
## Actual s01z arena, entry → dodge/recovery → death → exit → fresh retry.
## PSZ_BOSS_LIFECYCLE_CHECK=1 PSZ_PROBE_PACK=... coliseum_probe.tscn


func _run() -> void:
	probe_label = "boss-lifecycle"
	for attempt in 2:
		TrapBall.grant_vision()
		SessionManager.enter_quest("debug_boss_reyburn", "normal")
		_check(not TrapBall.vision_active(), "fresh arena session resets old Trap Vision")
		await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": "0,0", "spawn_edge": "", "keys_collected": {}})
		var boss: ReyburnBoss
		for frame in 600:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group("enemies"):
				if node is ReyburnBoss and node.is_alive: boss = node
			if boss: break
		if not boss:
			_check(false, "boss arena loaded")
			break
		# Field _ready finishes HUD/spawns after the enemy itself enters the tree.
		await get_tree().create_timer(0.1).timeout
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var field = get_tree().current_scene
		_check(field._map_root != null and boss.current_hp == boss.encounter_max_hp, "attempt %d starts fresh boss HP" % attempt)
		_check(field._field_hud._boss_bar != null and field._field_hud._boss_bar.visible, "boss HUD visible on entry/retry")
		boss.set_physics_process(false)
		player.set_physics_process(false)
		boss.target = player
		player.global_position = boss.global_position + Vector3(0, 0, -2)
		boss.rotation.y = 0.0
		await _damage_guards(player, boss)
		await _finish_encounter(player, boss, field)
		if not _ok: break
		# Explicit fresh session follows the same arena-entry path as the picker.
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[boss-lifecycle] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _damage_guards(player: Node3D, boss: ReyburnBoss) -> void:
	# Isolate immunity from facing; directional contact is covered by PR #750.
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	boss._damage_target()
	_check(GameState.hp == GameState.max_hp, "dodge rejects boss delivery")
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 1.0
	boss._damage_target()
	_check(GameState.hp == GameState.max_hp, "recovery rejects boss delivery")
	player._recovery_left = 0.0
	boss._damage_target()
	_check(GameState.hp < GameState.max_hp, "unprotected boss delivery damages player")
	await get_tree().physics_frame

func _finish_encounter(player: Node3D, boss: ReyburnBoss, field: Node) -> void:
	var deaths: Array[int] = []
	boss.died.connect(func(_enemy): deaths.append(1))
	boss._fire(0.0)
	var projectile_count := boss._owned_shots.size()
	var shots := boss._owned_shots.duplicate()
	boss._die()
	var experience: int = CharacterManager.get_active_character().experience
	boss._die()
	boss._damage_target()
	boss._fire(0.0)
	_check(deaths.size() == 1 and CharacterManager.get_active_character().experience == experience, "repeat death emits/rewards once")
	_check(field._field_hud._boss_bar != null and not field._field_hud._boss_bar.visible, "death hides boss HUD")
	await get_tree().process_frame
	_check(projectile_count == 1 and not is_instance_valid(shots[0]) and boss._owned_shots.is_empty(), "death clears projectiles and prevents new release")
	field._check_room_clear()
	field._check_room_clear()
	var exits: Array = field._map_root.get_children().filter(func(n): return n is Telepipe)
	_check(exits.size() == 1, "boss clear yields exactly one return warp")
	player.set_physics_process(true)
