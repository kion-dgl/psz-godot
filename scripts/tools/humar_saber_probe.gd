extends "res://scripts/tools/probe_checks.gd"
## #790 fixture. Launch through run_humar_saber.py; scene changes preserve this observer.
const Rules := preload("res://scripts/3d/player/humar_saber_prototype.gd")

func _run() -> void:
	probe_label = "humar-saber"
	if ProjectSettings.get_setting("application/config/name") != "PSZ Saber Prototype":
		push_error("Use scripts/tools/run_humar_saber.py to isolate saves")
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	await _launch()

func _launch() -> void:
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "Saber Test")
	CharacterManager.set_active_slot(0)
	DebugConfig.invincible = false
	DebugConfig.show_combo_timing = true
	ColiseumRoster.selected_enemy_level = 1
	SessionManager.enter_quest("debug_coliseum", "normal")
	var sections := ColiseumRoster.make_sections("pso_booma")
	if OS.get_environment("PSZ_SABER_GROUP") == "1":
		sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"pso_booma", "position":[-3.0,0.0,5.0]})
		sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"pso_booma", "position":[3.0,0.0,5.0]})
	SessionManager.set_field_sections(sections)
	ColiseumRoster.apply_level_override()
	await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
	var player = get_tree().get_first_node_in_group("player")
	_check(player != null, "real Coliseum player spawned")
	if player == null:
		get_tree().quit(1)
		return
	_check(Rules.enabled(player), "prototype is scoped to HUmar saber in Coliseum")
	if not player.animation_player or not player.animation_player.has_animation("pso_sa_wait"):
		push_error("Import the baked saber library before launching")
		get_tree().quit(1)
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.enemy_data = enemy.enemy_data.duplicate(true)
			enemy.enemy_data.exp_reward = 0 # Fixed-stat fixture, never registry tuning.
	if OS.get_environment("PSZ_SABER_CHECK") == "1":
		for enemy in get_tree().get_nodes_in_group("enemies"): enemy.set_physics_process(false)
		for frame in range(30): await get_tree().physics_frame
		await _verify(player)
		print("[humar-saber] DONE " + ("ok" if _ok else "FAIL"))
		get_tree().quit(0 if _ok else 1)
	else:
		print("[humar-saber] Ready: standard movement/attack controls; automatic frontal guard while ready. Restart launcher to reset; --group selects three Boomas.")

func _verify(player) -> void:
	_check(player.is_on_floor() and absf(player.global_position.y) < 1.0, "player settles on actual Coliseum floor")
	player.set_physics_process(false)
	var enemies := get_tree().get_nodes_in_group("enemies")
	_check(not enemies.is_empty(), "real opponents spawned")
	if enemies.is_empty(): return
	for enemy in enemies: enemy.set_physics_process(false)
	var enemy = enemies[0]
	enemy.target = player
	_check(enemy.enemy_level == 1, "fixed enemy level")
	_check(player.get_node("PlayerModel/Model").has_meta("psz_avatar_format"), "current VRM loaded")
	_check(player.weapon_node != null, "saber attached")
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/retarget/pso_animation_map.json"))
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		add_child(camera)
		camera.global_position = player.global_position + Vector3(3, 2, 4)
		camera.look_at(player.global_position + Vector3.UP)
		camera.current = true
	var count := 0
	for clip in mapping.mappings.values():
		if not str(clip).begins_with("pso_sa_"): continue
		count += 1
		_check(player.animation_player.has_animation(clip), "clip " + clip)
		if player.animation_player.has_animation(clip):
			_verify_root(player.animation_player.get_animation(clip), clip)
			player.play_animation(clip, false)
			player.animation_player.seek(player.animation_player.get_animation(clip).length * 0.5, true)
			await _snapshot(clip)
	_check(count == 15, "complete saber inventory")
	_check(player.animation_player.has_animation("pmsa_esc_f"), "native dodge remains available")
	_check(player.animation_player.has_animation("pmsa_dam_d_lp"), "native defeated hold remains available")
	await _snapshot("humar_saber")
	_verify_movement(player, enemies)
	await _verify_exchange(player, enemy)

func _verify_exchange(player, enemy) -> void:
	player.player_rotation = 0.0
	enemy.global_position = player.global_position + Vector3(0,0,2)
	player.transition_to(player.PlayerState.IDLE)
	var hp := GameState.hp
	enemy._deal_damage_for({"kind":"melee_arc", "damage_mult":1.0})
	_check(GameState.hp == hp and player.animation_player.current_animation == "pso_sa_block", "real frontal melee is blocked")
	player._start_attack()
	_check(Rules.guarding(player), "block commits recovery and refuses attack cancel")
	player._hit_invulnerability_left = 0
	player.take_damage(1, Vector3.ZERO, false, true)
	_check(GameState.hp == hp - 1, "guard does not grant status-tick immunity")
	GameState.set_hp(hp)
	player._recovery_left = 0
	player.transition_to(player.PlayerState.IDLE)
	enemy.global_position = player.global_position - Vector3(0,0,2)
	_check(not player.try_prototype_guard(enemy), "rear attack cannot guard")
	enemy.global_position = player.global_position + Vector3(0,0,2)
	player._start_attack()
	_check(player.animation_player.current_animation == "pso_sa_atk1", "real attack uses PSO clip")
	_check(not player.try_prototype_guard(enemy), "guard cannot cancel attack")
	player._attack_anim_elapsed = player._attack_anim_length * 0.65
	player._try_queue_combo(false)
	_check(player._queued_combo != player.ComboQueue.NONE, "prototype chain window accepts deliberate input")
	player._attack_step_finished()
	_check(player.combo_state == 2 and player.animation_player.current_animation == "pso_sa_atk2", "queued second swing starts")
	player._hit_invulnerability_left = 0
	player.take_damage(5)
	_check(GameState.hp == hp - 5 and player.current_state == player.PlayerState.DAMAGED, "committed attack takes damage and interrupts")
	_check(player._queued_combo == player.ComboQueue.NONE, "interruption clears chain")
	await get_tree().create_timer(0.8).timeout
	_check(player.current_state == player.PlayerState.IDLE, "damage animation recovers")
	await _verify_player_swing(player, enemy)
	await _verify_enemy_swing(player, enemy)

func _verify_enemy_swing(player, enemy) -> void:
	player._recovery_left = 0
	player._hit_invulnerability_left = 0
	player.transition_to(player.PlayerState.IDLE)
	player.player_rotation = 0.0
	enemy.global_position = player.global_position + Vector3(0, 0, 1.5)
	enemy.target = player
	enemy._attack_def = {}
	enemy._start_attack()
	var before := GameState.hp
	var blocked := false
	for frame in range(180):
		enemy._process_attacking(1.0 / 60.0)
		await get_tree().physics_frame
		blocked = blocked or player.animation_player.current_animation == "pso_sa_block"
		if enemy._attack_hit_resolved: break
	_check(enemy._attack_hit_resolved and blocked and GameState.hp == before, "actual Booma animation/contact reaches guard")


func _verify_player_swing(player, enemy) -> void:
	seed(790)
	player._recovery_left = 0
	player.transition_to(player.PlayerState.IDLE)
	player.player_rotation = 0.0
	enemy.global_position = player.global_position + Vector3(0, 0, 1.2)
	var before: int = enemy.current_hp
	player._start_attack()
	for frame in range(90):
		if player.current_state != player.PlayerState.ATTACKING: break
		player._handle_attack_state(1.0 / 60.0)
		await get_tree().physics_frame
	_check(enemy.current_hp < before, "PSO swing delivers real saber damage")
	_check(player.current_state == player.PlayerState.IDLE, "unchained swing completes recovery")

func _verify_root(animation: Animation, clip: String) -> void:
	var aligned := true
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
		if not str(animation.track_get_path(track)).ends_with(":000_Root"): continue
		for key in animation.track_get_key_count(track):
			var position: Vector3 = animation.track_get_key_value(track, key)
			aligned = aligned and position.is_finite() and is_zero_approx(position.x) and is_zero_approx(position.z)
	_check(aligned, clip + " keeps root aligned with collision body")

func _verify_movement(player, enemies: Array) -> void:
	var positions: Array[Vector3] = []
	for enemy in enemies:
		positions.append(enemy.global_position)
		enemy.global_position = player.global_position + Vector3(0, 0, 2)
	player.transition_to(player.PlayerState.RUNNING)
	Input.action_press("move_forward")
	player._handle_movement(0.1)
	_check(player.current_state == player.PlayerState.WALKING and player._walk_anim == "pso_sa_walk_ready", "near enemies interrupt running with caution animation")
	for enemy in enemies: enemy.global_position += Vector3(0, 0, 30)
	player._handle_movement(1.3)
	Input.action_release("move_forward")
	_check(player.current_state == player.PlayerState.RUNNING and player._walk_anim == "pso_sa_walk", "leaving threats restores normal locomotion")
	for i in enemies.size(): enemies[i].global_position = positions[i]
	player.transition_to(player.PlayerState.IDLE)
