extends "res://scripts/tools/probe_checks.gd"
## Real field spawn/HUD/hit/death/return/retry with optional distributed asset pack.
## PSZ_DARK_SHRINE_CHECK=1 godot --headless --path . scripts/tools/coliseum_probe.tscn

func _run() -> void:
	probe_label = "dark-shrine"
	for quest in ["debug_boss_mother_trinity","debug_boss_dark_falz","debug_boss_mother_trinity","debug_boss_dark_falz"]:
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
		if boss is MotherTrinityBoss:
			for piece in boss.pieces: piece.set_physics_process(false)
		player.set_physics_process(false)
		_check(boss.model != null and boss.animation_player != null,"imported boss rig and animations loaded")
		_check(field._field_hud._boss_bar != null and field._field_hud._boss_bar.visible,"boss HUD visible")
		_check(boss.current_hp == boss.encounter_max_hp,"retry starts with full independent HP")
		boss.target = player
		_contact_checks(boss, player)
		player.current_state = player.PlayerState.DODGING
		await _snapshot(quest + "_entry")
		if boss is MotherTrinityBoss:
			_check(str(field._current_cell.stage_id) == "s07z_na1", "Trinity uses her Dark Shrine arena")
			await _trinity(boss)
		else:
			await preload("res://scripts/tools/falz_encounter_probe.gd").run(self, boss)
		await _snapshot(quest + "_body")
		await _finish(boss,field)
		SessionManager.return_to_city()
		await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	print("[dark-shrine] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _trinity(boss: MotherTrinityBoss) -> void:
	_check(boss.position.is_equal_approx(MotherTrinityBoss.ARENA_ANCHOR), "body seated in north platform cutout")
	var anchor := boss.global_transform
	boss.target.global_position = boss.to_global(Vector3(7, 0, 14))
	boss._aim_at_target()
	_check(boss.global_transform.is_equal_approx(anchor), "off-axis target cannot rotate body away from cables")
	for piece in boss.pieces:
		var board_position: Vector3 = boss.get_parent().to_local(piece.global_position)
		_check(absf(board_position.x) <= 7.0 and absf(board_position.z) <= 7.0, "piece starts on the player platform")
	_check(boss.pieces.size() == 3,"three independently targetable pieces")
	var hp := boss.current_hp
	boss.hurtbox.take_hit(99999,Vector3.ZERO,9999)
	_check(boss.current_hp == hp and boss.is_alive,"body protected before piece transition")
	for piece in boss.pieces: piece.set_physics_process(false)
	_check(not boss.arena.broken and boss.arena.cover.visible, "intact floor cover before two piece losses")
	_wave_contact_checks(boss)
	await _board_checks(boss)
	boss._enter_idle()
	boss.pieces[0].hurtbox.take_hit(99999,Vector3.ZERO,9999)
	_check(not boss.arena.broken, "first piece loss leaves cover intact")
	_check(boss.piece_count == 2 and boss.action_id == 2,"first piece loss reacts without exposing body")
	boss.pieces[1].hurtbox.take_hit(99999,Vector3.ZERO,9999)
	for tick in 62: boss._physics_process(1.0/30.0)
	_check(boss.pieces[2].paused, "surviving piece pauses for body entry")
	_check(boss.action_id == 3 and not boss._accepts_damage(),"second loss enters protected transition")
	for tick in 126: boss._physics_process(1.0/30.0)
	_check(boss.arena.broken and not boss.arena.cover.visible, "second-loss exposure breaks floor cover")
	_check(boss.pieces[2].is_alive and not boss.pieces[2].paused, "surviving piece resumes during body phase")
	_check(boss.model.position.z == 0, "body finishes entering the cutout")
	_check(boss.phase_flags == 3 and boss._accepts_damage(),"descriptor event opens body vulnerability")
	boss.play_action(1, {0:-1})
	boss._sync_pose()
	_check(boss.hurtbox.global_position.distance_to(boss._joint_position("head")) < 0.01,
		"body damage receiver follows animated head onto platform")
	var action := boss.action_id
	boss.hurtbox.take_hit(1,Vector3.ZERO,9999)
	_check(boss.action_id == action and boss.current_state != EnemyBase.EnemyState.HURT,"damage preserves boss action")
	# Exercise a complete head chain and laser against a live player.
	boss.play_sequence([9,10,11,8])
	for tick in 505: boss._physics_process(1.0/30.0)
	_check(boss._owned_shots.size() > 0,"Trinity descriptor laser notification releases delivery")
	_check(boss.global_transform.is_equal_approx(anchor), "complete head and laser chain preserves arena anchor")
	if not boss._owned_shots.is_empty():
		var shot := boss._owned_shots.back() as EnemyProjectile
		_check(shot.global_position.distance_to(boss.global_position + Vector3.UP) > 1.0,
			"laser originates at animated head instead of body root")
		_check(shot.dir.y < 0.0, "laser aims down toward the player platform")
	boss._idle = false # Drive the recovery pose without the idle scheduler replacing it.
	boss.play_action(9)
	for tick in 120: boss._physics_process(1.0/30.0)
	var head := boss.hurtbox.global_position
	_check(head.y < 3.0, "head-bash recovery lowers the damage receiver to melee height")
	await get_tree().physics_frame
	var query := PhysicsShapeQueryParameters3D.new()
	var reach := SphereShape3D.new()
	reach.radius = 0.5
	query.shape = reach
	query.transform.origin = Vector3(head.x, 1.0, head.z + 2.0)
	query.collision_mask = 32
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var contacts := boss.get_world_3d().direct_space_state.intersect_shape(query)
	_check(contacts.any(func(hit: Dictionary): return hit.collider == boss.hurtbox),
		"platform-height melee volume overlaps lowered head hurtbox")
	_check(boss.is_in_group("enemies") and not boss.hurtbox_in_cone(head+Vector3(0,0,2),PI,{}).is_empty(),
		"shared multipart scanner retains exposed Trinity head receiver")

func _finish(boss: DescriptorBoss, field: Node) -> void:
	var falz_tail: Node3D = boss.tail if boss is DarkFalzBoss and is_instance_valid(boss.tail) else null
	var piece_deliveries: Array = []
	if boss is MotherTrinityBoss:
		for piece in boss.pieces:
			if is_instance_valid(piece) and piece.is_alive:
				piece.release_wave({})
				piece_deliveries.append_array(piece._shots)
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
	if boss is MotherTrinityBoss:
		_check(boss.board.owners.is_empty(), "boss death releases all board reservations")
		_check(piece_deliveries.all(func(n): return not is_instance_valid(n)), "boss death clears surviving piece deliveries")
	if boss is DarkFalzBoss:
		_check(not is_instance_valid(falz_tail) and not boss.orbit.visible, "Falz death clears tail and hides orbit hazards")
	_check(boss._owned_shots.is_empty() and shots.all(func(n): return not is_instance_valid(n)),"death clears owned projectiles")
	field._check_room_clear()
	field._check_room_clear()
	var exits: Array = field._map_root.get_children().filter(func(n): return n is Telepipe)
	_check(exits.size() == 1,"exactly one return warp after encounter clear")

func _contact_checks(boss: DescriptorBoss, player: Node3D) -> void:
	if boss is DarkFalzBoss:
		var receiver := boss.hurtbox.get_child(0) as CollisionShape3D
		_check(not boss.hurtbox_in_cone(receiver.global_position+Vector3(0,0,2),PI,{}).is_empty(),
			"shared multipart scanner retains Falz capsule receiver")
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


func _board_checks(boss: MotherTrinityBoss) -> void:
	# Manual catch-up drives ten seconds of decisions without real-time delivery
	# stepping. Guard the probe hero, then clear stale shots before the wave view.
	boss.target.current_state = boss.target.PlayerState.DODGING
	boss.target.dodge_timer = 0.0
	var aligned := true
	for piece in boss.pieces: piece._left = 0
	for tick in 300:
		for piece in boss.pieces:
			piece._physics_process(1.0 / 30.0)
			if piece.step != MotherPiece.Step.HOP:
				var center := boss.to_global(MotherBoard.center(boss.board.occupied[piece.piece_index]))
				aligned = aligned and piece.global_position.distance_to(center) < 0.01
	_check(aligned, "all landed piece positions remain at floor-square centers")
	_check(boss.pieces.all(func(piece): return piece.attack_count >= 2), "every piece completes hop-spin-attack cycles")
	_check(boss.pieces.all(func(piece): return piece._shots.any(func(shot): return shot is EnemyProjectile)), "piece cycles include technique projectiles")
	_check(boss.pieces.all(func(piece): return piece._shots.any(func(shot): return shot is MotherWave)), "piece cycles include short melee strikes")
	for piece in boss.pieces: piece.clear_deliveries()
	boss._idle = false
	boss.play_action(6)
	for tick in 45: boss._physics_process(1.0 / 30.0)
	_check(boss._wave_pending, "Trinity command notification requests a coordinated wave")
	var release_ticks: Array[int] = [-1,-1,-1]
	for tick in 100:
		for piece in boss.pieces: piece._physics_process(1.0 / 30.0)
		if boss._wave_pending:
			boss._try_release_wave()
		for index in 3:
			if boss.pieces[index].wave_count > 0 and release_ticks[index] < 0:
				release_ticks[index] = tick
	_check(release_ticks[0] >= 0 and release_ticks[0] == release_ticks[1] and release_ticks[1] == release_ticks[2],
		"all three pieces release the command wave on the same tick")
	if not OS.get_environment("PSZ_BOSS_SCREENSHOTS").is_empty() and DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.4).timeout
		await _snapshot("trinity_board_wave")
	for piece in boss.pieces: piece.clear_deliveries()
	await get_tree().physics_frame
	boss.target.current_state = boss.target.PlayerState.IDLE
	GameState.set_hp(GameState.max_hp)


func _wave_contact_checks(boss: MotherTrinityBoss) -> void:
	var player := boss.target
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	var budget: Dictionary = {}
	for index in 3:
		var wave := MotherWave.new()
		wave.target = player
		wave.damage = 10
		wave.hit_budget = budget
		boss.get_parent().add_child(wave)
		wave.global_position = player.global_position - Vector3.RIGHT
		wave._physics_process(0.2)
		wave.queue_free()
	_check(GameState.hp == GameState.max_hp, "synchronized waves respect dodge immunity")
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0.0
	budget = {}
	for index in 3:
		var wave := MotherWave.new()
		wave.target = player
		wave.damage = 10
		wave.hit_budget = budget
		boss.get_parent().add_child(wave)
		wave.global_position = player.global_position - Vector3.RIGHT
		wave._physics_process(0.2)
		wave.queue_free()
	_check(GameState.hp == GameState.max_hp - 10, "overlapping command waves share one damage resolution")
	GameState.set_hp(GameState.max_hp)
