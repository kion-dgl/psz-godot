extends "res://scripts/tools/probe_checks.gd"
## Real field spawn/HUD/hit/death/return/retry with optional distributed asset pack.
## PSZ_DARK_SHRINE_CHECK=1 godot --headless --path . scripts/tools/coliseum_probe.tscn

func _run() -> void:
	probe_label = "dark-shrine"
	for quest in ["debug_boss_mother_trinity","debug_boss_dark_falz","debug_boss_mother_trinity"]:
		SessionManager.enter_quest(quest,"normal")
		await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos":"0,0", "spawn_edge":"", "keys_collected":{}})
		var boss: DescriptorBoss
		for frame in 600:
			await get_tree().physics_frame
			for node in get_tree().get_nodes_in_group("bosses"):
				if node is DescriptorBoss and node.is_alive: boss = node
			if boss: break
		if not boss:
			_check(false,"dedicated boss spawned: " + quest)
			break
		await get_tree().create_timer(0.1).timeout
		var field := get_tree().current_scene
		var player := get_tree().get_first_node_in_group("player") as Node3D
		boss.set_physics_process(false)
		player.set_physics_process(false)
		_check(boss.model != null and boss.animation_player != null,"imported boss rig and animations loaded")
		_check(field._field_hud._boss_bar != null and field._field_hud._boss_bar.visible,"boss HUD visible")
		_check(boss.current_hp == boss.encounter_max_hp,"retry starts with full independent HP")
		boss.target = player
		_contact_checks(boss, player)
		await _snapshot(quest + "_entry")
		if boss is MotherTrinityBoss:
			await _trinity(boss)
		else:
			_falz(boss)
		await _snapshot(quest + "_body")
		await _finish(boss,field)
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[dark-shrine] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _trinity(boss: MotherTrinityBoss) -> void:
	_check(boss.pieces.size() == 3,"three independently targetable pieces")
	var hp := boss.current_hp
	boss.hurtbox.take_hit(99999,Vector3.ZERO,9999)
	_check(boss.current_hp == hp and boss.is_alive,"body protected before piece transition")
	for piece in boss.pieces: piece.set_physics_process(false)
	boss.pieces[0].hurtbox.take_hit(99999,Vector3.ZERO,9999)
	_check(boss.piece_count == 2 and boss.action_id == 2,"first piece loss reacts without exposing body")
	boss.pieces[1].hurtbox.take_hit(99999,Vector3.ZERO,9999)
	for tick in 62: boss._physics_process(1.0/30.0)
	_check(boss.action_id == 3 and not boss._accepts_damage(),"second loss enters protected transition")
	for tick in 126: boss._physics_process(1.0/30.0)
	_check(boss.phase_flags == 3 and boss._accepts_damage(),"descriptor event opens body vulnerability")
	var action := boss.action_id
	boss.hurtbox.take_hit(1,Vector3.ZERO,9999)
	_check(boss.action_id == action and boss.current_state != EnemyBase.EnemyState.HURT,"damage preserves boss action")
	# Exercise a complete head chain and laser against a live player.
	boss.play_sequence([9,10,11,8])
	for tick in 505: boss._physics_process(1.0/30.0)
	_check(boss._owned_shots.size() > 0,"Trinity descriptor laser notification releases delivery")
	await get_tree().physics_frame

func _falz(boss: DarkFalzBoss) -> void:
	boss.current_hp = boss.encounter_max_hp / 2 - 1
	boss._after_damage_applied(1)
	_check(boss.pending_reaction == 2,"Falz half HP reaction queued")
	boss.current_hp = boss.encounter_max_hp / 4 - 1
	boss._after_damage_applied(1)
	_check(boss.pending_reaction == 3 and boss.damage_rules.flags == 6,"quarter HP reaction takes priority")
	boss.play_sequence([17,18])
	for tick in 80: boss._physics_process(1.0/30.0)
	_check(boss._owned_shots.size() == 5,"diffusion releases five provisional projectiles at notification 2")

func _finish(boss: DescriptorBoss, field: Node) -> void:
	var deaths: Array[int] = []
	boss.died.connect(func(_enemy): deaths.append(1))
	boss._shoot()
	var shots := boss._owned_shots.duplicate()
	boss.hurtbox.take_hit(999999,Vector3.ZERO,9999)
	var experience: int = CharacterManager.get_active_character().experience
	boss._die()
	boss._shoot()
	_check(deaths.size() == 1 and experience == CharacterManager.get_active_character().experience,"lethal hit and repeat death reward exactly once")
	_check(not field._field_hud._boss_bar.visible,"death hides boss HUD")
	await get_tree().process_frame
	_check(boss._owned_shots.is_empty() and shots.all(func(n): return not is_instance_valid(n)),"death clears owned projectiles")
	field._check_room_clear()
	field._check_room_clear()
	var exits: Array = field._map_root.get_children().filter(func(n): return n is Telepipe)
	_check(exits.size() == 1,"exactly one return warp after encounter clear")

func _snapshot(label: String) -> void:
	var folder := OS.get_environment("PSZ_BOSS_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _contact_checks(boss: DescriptorBoss, player: Node3D) -> void:
	var old_attack: int = boss.enemy_data.attack_base
	var old_stats: bool = boss.enemy_data.original_attack_stats
	boss.enemy_data.attack_base = 10
	boss.enemy_data.original_attack_stats = false
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	boss._damage_target()
	_check(GameState.hp == GameState.max_hp, "boss delivery respects dodge immunity")
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0.0
	boss._damage_target()
	_check(GameState.hp == GameState.max_hp - 10, "unprotected boss delivery damages player")
	boss.enemy_data.attack_base = old_attack
	boss.enemy_data.original_attack_stats = old_stats
	GameState.set_hp(GameState.max_hp)
