extends "res://scripts/tools/probe_checks.gd"
## #790 fixture. Launch through run_humar_saber.py; scene changes preserve this observer.
const Rules := preload("res://scripts/3d/player/humar_saber_prototype.gd")

var _native_prefix := "pmsa"
var _pso_prefix := "pso_sa"

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
	var female := OS.get_environment("PSZ_SABER_GENDER") == "female"
	_native_prefix = "pwsa" if female else "pmsa"
	_pso_prefix = "pso_f_sa" if female else "pso_sa"
	CharacterManager.create_character(0, "humarl" if female else "humar", "Saber Test")
	if OS.get_environment("PSZ_MELEE_WEAPON") == "sword":
		_native_prefix = "pwsw" if female else "pmsw"
		_pso_prefix = "pso_f_sw" if female else "pso_sw"
		CharacterManager._characters[0].equipment.weapon = "sword"
	if OS.get_environment("PSZ_MELEE_WEAPON") == "daggers":
		_native_prefix = "pwda" if female else "pmda"
		_pso_prefix = "pso_f_da" if female else "pso_da"
		CharacterManager._characters[0].equipment.weapon = "dagger"
	CharacterManager.set_active_slot(0)
	DebugConfig.invincible = false
	DebugConfig.show_combo_timing = true
	ColiseumRoster.selected_enemy_level = 1
	SessionManager.enter_quest("debug_coliseum", "normal")
	var sections := ColiseumRoster.make_sections("pso_booma")
	if OS.get_environment("PSZ_SABER_GROUP") == "1":
		sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"pso_booma", "position":[-3.0,0.0,5.0]})
		sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"pso_booma", "position":[3.0,0.0,5.0]})
	if OS.get_environment("PSZ_MELEE_WEAPON") == "sword" and OS.get_environment("PSZ_SABER_GROUP") == "1":
		sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"pso_booma", "position":[0.0,0.0,7.0]})
	SessionManager.set_field_sections(sections)
	ColiseumRoster.apply_level_override()
	await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
	var player = get_tree().get_first_node_in_group("player")
	_check(player != null, "real Coliseum player spawned")
	if player == null:
		get_tree().quit(1)
		return
	_check(Rules.enabled(player), "prototype is scoped to selected saber profile in Coliseum")
	_check(player._is_female == female, "avatar gender matches selected profile")
	_check(Rules.profile(player).class_id == ("humarl" if female else "humar"), "explicit class profile selected")
	if not player.animation_player or not player.animation_player.has_animation((_pso_prefix + "_wait")):
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
		if _native_prefix in ["pmda", "pwda"]:
			var controls = preload("res://scripts/tools/dagger_grip_controls.gd").new()
			add_child(controls)
			controls.setup(player)
			await get_tree().process_frame
			await _snapshot("dagger_grip_controls")
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
	var wrong_prefix := "pmsa_" if player._is_female else "pwsa_"
	for clip in player.animation_player.get_animation_list():
		_check(not str(clip).begins_with(wrong_prefix), "no opposite-gender native clip: " + str(clip))
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/retarget/pso_animation_map.json"))
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		add_child(camera)
		camera.global_position = player.global_position + Vector3(3, 2, 4)
		camera.look_at(player.global_position + Vector3.UP)
		camera.current = true
	var count := 0
	for clip in mapping.mappings.values():
		if not str(clip).begins_with((_pso_prefix + "_")): continue
		count += 1
		_check(player.animation_player.has_animation(clip), "clip " + clip)
		if player.animation_player.has_animation(clip):
			_verify_root(player.animation_player.get_animation(clip), clip)
			player.animation_player.stop()
			player.play_animation(clip, false)
			player.animation_player.seek(player.animation_player.get_animation(clip).length * 0.5, true)
			if OS.get_environment("PSZ_SABER_FEEDBACK_ONLY") != "1" or clip in ["pso_f_sw_wait", "pso_f_sw_block", "pso_f_sw_walk", "pso_f_sw_dam_n", "pso_f_sw_pb"]: await _snapshot(clip)
	_check(count == int(Rules.profile(player).source_count), "complete saber inventory")
	_check(player.animation_player.has_animation((_native_prefix + "_esc_f")), "native dodge remains available")
	_check(player.animation_player.has_animation((_native_prefix + "_dam_d_lp")), "native defeated hold remains available")
	for step in range(1, 4):
		var clip := (_native_prefix + "_atk") + str(step)
		var animation: Animation = player.animation_player.get_animation(clip)
		player.animation_player.stop()
		player.play_animation(clip, false)
		player.animation_player.seek(animation.length * 0.35, true)
		if OS.get_environment("PSZ_GUARD_FEEDBACK_ONLY") != "1": await _snapshot(clip)
		var last_key := 0.0
		for track in animation.get_track_count():
			for key in animation.track_get_key_count(track):
				last_key = maxf(last_key, animation.track_get_key_time(track, key))
		_check(animation.length - last_key >= float(Rules.profile(player).get("recovery", Rules.RECOVERY)[step - 1]) - 0.002, "native swing holds recovery pose " + str(step))
	for evasion in [0, 50, 200]:
		for attempt in range(30):
			var result := CombatManager.apply_damage_to_enemy(30, 5, evasion, Rules.contact_accuracy(evasion))
			_check(result.hit, "fixture contact ignores accuracy RNG")
	if OS.get_environment("PSZ_SABER_FEEDBACK_ONLY") != "1": await _snapshot("humar_saber")
	if _native_prefix in ["pmsw", "pwsw"]: await _verify_sword_contacts(player, enemies)
	if _native_prefix in ["pmda", "pwda"] and OS.get_environment("PSZ_GUARD_FEEDBACK_ONLY") != "1": await _verify_dagger_contacts(player, enemies)
	_verify_lock_sound(player, enemies)
	_verify_movement(player, enemies)
	await _verify_mixed_combos(player)
	_verify_ready_recovery(player, enemy)
	await _verify_feedback(player, enemy)
	_verify_combo_outcomes(player, enemy)
	await _verify_exchange(player, enemy)
	var saved_evasion: int = enemy.current_evasion
	var saved_hp: int = enemy.current_hp
	enemy.current_evasion = 500
	var all_connected := true
	for attempt in range(20):
		enemy.current_hp = 10000
		enemy.hurtbox.take_attack(player._get_attack_damage(), Vector3.ZERO, player)
		all_connected = all_connected and enemy.current_hp < 10000
	_check(all_connected, "real hurtbox bypasses evasion for every fixture contact")
	enemy.current_evasion = saved_evasion
	enemy.current_hp = saved_hp

func _verify_exchange(player, enemy) -> void:
	player.player_rotation = 0.0
	enemy.global_position = player.global_position + Vector3(0,0,2)
	player.transition_to(player.PlayerState.IDLE)
	var hp := GameState.hp
	var block_bursts := get_tree().get_nodes_in_group("prototype_block_feedback").size()
	enemy._deal_damage_for({"kind":"melee_arc", "damage_mult":1.0})
	_check(GameState.hp == hp and player.animation_player.current_animation == (_pso_prefix + "_block"), "real frontal melee is blocked")
	_check(get_tree().get_nodes_in_group("prototype_block_feedback").size() == block_bursts + 1, "successful block emits guard spark")
	await get_tree().create_timer(0.08).timeout
	await _snapshot("successful_block")
	await get_tree().create_timer(0.3).timeout
	_check(get_tree().get_nodes_in_group("prototype_block_feedback").is_empty(), "guard sparks clean themselves up")
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
	_check(get_tree().get_nodes_in_group("prototype_block_feedback").is_empty(), "rejected block emits no guard spark")
	enemy.global_position = player.global_position + Vector3(0,0,2)
	player._start_attack()
	player._handle_attack_state(Rules.READY_PREP)
	_check(player.animation_player.current_animation == (_native_prefix + "_atk1"), "real attack uses native PSZ clip")
	_check(not player.try_prototype_guard(enemy), "guard cannot cancel attack")
	player._attack_anim_elapsed = player._attack_anim_length * 0.65
	player._try_queue_combo(false)
	_check(player._queued_combo != player.ComboQueue.NONE, "prototype chain window accepts deliberate input")
	player._attack_step_finished()
	_check(player.combo_state == 2 and player.animation_player.current_animation == (_native_prefix + "_atk2"), "queued second native swing starts")
	player._attack_anim_elapsed = player._attack_anim_length * 0.65
	player._try_queue_combo(false)
	player._attack_step_finished()
	_check(player.combo_state == 3 and player.animation_player.current_animation == (_native_prefix + "_atk3"), "queued third native swing starts")
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
		blocked = blocked or player.animation_player.current_animation == (_pso_prefix + "_block")
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
	_check(enemy.current_hp < before, "PSZ swing delivers real saber damage")
	_check(player.current_state == player.PlayerState.IDLE and player._saber_attack_cooldown > 0.0, "unchained swing releases movement before attack cooldown")
	player._tick_saber_attack_cooldown(Rules.STOPPED_ATTACK_COOLDOWN)

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
	for enemy in enemies: positions.append(enemy.global_position)
	player._saber_caution_active = false
	player._saber_retreat_elapsed = 0.0
	player._targeted_enemies.clear()
	player.transition_to(player.PlayerState.RUNNING)
	Input.action_press("move_forward")
	var movement_yaw: float = player._held_movement_yaw()
	var direction := Vector3(sin(movement_yaw), 0, cos(movement_yaw))
	player.player_rotation = movement_yaw
	for enemy in enemies: enemy.global_position = player.global_position + direction * 5.0
	player._update_combat_targets()
	_check(player._targeted_enemies.is_empty(), "enemy outside cursor reach has no target")
	player._handle_movement(0.1)
	_check(player.current_state == player.PlayerState.RUNNING and player._walk_anim == str(Rules.profile(player).walk), "proximity without cursor does not trigger caution")
	for enemy in enemies: enemy.global_position = player.global_position + direction * 1.2
	player._update_combat_targets()
	_check(not player._targeted_enemies.is_empty(), "close enemy acquires cursor")
	player._handle_movement(0.1)
	_check(player.current_state == player.PlayerState.WALKING and player._walk_anim == (_pso_prefix + "_walk_ready"), "cursor acquisition engages caution")
	for enemy in enemies: enemy.global_position = player.global_position - direction * 1.2
	player._update_combat_targets()
	_check(player._targeted_enemies.is_empty(), "retreat loses cursor")
	player._handle_movement(0.25)
	player._handle_movement(0.24)
	_check(player.current_state == player.PlayerState.WALKING and player._walk_anim == (_pso_prefix + "_walk_ready"), "retreat keeps caution for first 490 ms despite cursor loss")
	player._handle_movement(0.02)
	_check(player.current_state == player.PlayerState.RUNNING and player._walk_anim == str(Rules.profile(player).walk), "500 ms caution hold transitions directly to run")
	for enemy in enemies: enemy.global_position = player.global_position + direction * 1.2
	player._update_combat_targets()
	player._handle_movement(0.1)
	_check(player.current_state == player.PlayerState.WALKING, "reacquiring cursor restores caution")
	for enemy in enemies: enemy.global_position = player.global_position - direction * 1.2
	player._update_combat_targets()
	player._handle_movement(0.25)
	for enemy in enemies: enemy.global_position = player.global_position + direction * 1.2
	player._update_combat_targets()
	player._handle_movement(0.1)
	_check(is_zero_approx(player._saber_retreat_elapsed), "reacquiring target cancels pending retreat")
	Input.action_release("move_forward")
	player._handle_movement(0.1)
	_check(player.animation_player.current_animation == (_native_prefix + "_wait"), "stopping remains relaxed even with cursor")
	for i in enemies.size(): enemies[i].global_position = positions[i]
	player._targeted_enemies.clear()
	player._saber_caution_active = false
	player._saber_retreat_elapsed = 0.0
	player.transition_to(player.PlayerState.IDLE)

func _verify_mixed_combos(player) -> void:
	_check(ResourceLoader.exists(Rules.CHARGE_SOUND) and ResourceLoader.exists(Rules.LOCK_SOUND), "named charge and lock sounds imported")
	for pattern in range(8):
		player._recovery_left = 0
		player.transition_to(player.PlayerState.IDLE)
		if pattern & 1: player._start_strong_attack()
		else: player._start_attack()
		_check(player._saber_phase == "prepare" and player.animation_player.current_animation == (_pso_prefix + "_wait"), "fresh combo briefly readies weapon")
		player._handle_attack_state(Rules.READY_PREP)
		for step in range(1, 4):
			var clip := (_native_prefix + "_atk") + str(step)
			_check(player.combo_state == step and player.animation_player.current_animation == clip, "mixed combo %d starts native step %d without extra delay" % [pattern, step])
			_check(is_equal_approx(player._attack_anim_length, player.animation_player.get_animation(clip).length), "normal and strong use identical step duration")
			if step < 3:
				player._attack_anim_elapsed = player._attack_anim_length * 0.65
				if pattern & (1 << step): player._start_strong_attack()
				else: player._start_attack()
				_check(player._queued_combo != player.ComboQueue.NONE, "same timing accepts normal or strong continuation")
			player._attack_step_finished()
		_check(player._saber_phase == "guard_recovery" and player.animation_player.current_animation == (_pso_prefix + "_wait"), "completed combo enters ready recovery")
		player._handle_attack_state(Rules.FINISHER_GUARD)
		_check(player.current_state == player.PlayerState.IDLE and not player._charge_active, "mixed combo finishes cleanly")
	# Interrupt strong windup: no delayed callback may restart the swing.
	player._start_strong_attack()
	player._hit_invulnerability_left = 0
	player.take_damage(1)
	_check(not player._charge_active, "interruption clears strong charge feedback")
	await get_tree().create_timer(0.8).timeout
	_check(player.current_state == player.PlayerState.IDLE, "interrupted strong attack never restarts")

func _verify_lock_sound(player, enemies: Array) -> void:
	player._saber_lock_last_id = 0
	player._saber_lock_last_seen = 0
	var original := SfxManager._load(Rules.LOCK_SOUND) as AudioStreamWAV
	var soft := SfxManager._load_soft_edges(Rules.LOCK_SOUND) as AudioStreamWAV
	_check(original != soft and is_equal_approx(original.get_length(), soft.get_length()), "soft lock cue preserves original asset and duration")
	_check(soft.format == AudioStreamWAV.FORMAT_16_BITS and absi(soft.data.decode_s16(4)) < 1000 and soft.data.decode_s16(0) == 0, "lock cue start spike is softened")
	var positions: Array[Vector3] = []
	for enemy in enemies:
		positions.append(enemy.global_position)
		enemy.global_position = player.global_position + Vector3(0, 0, 50)
	player.player_rotation = 0.0
	player._update_combat_targets()
	var before: int = SfxManager._next_idx
	enemies[0].global_position = player.global_position + Vector3(0, 0, 1.2)
	player._update_combat_targets()
	_check(SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "acquiring enemy plays lock sound")
	before = SfxManager._next_idx
	player._update_combat_targets()
	_check(SfxManager._next_idx == before, "held cursor does not repeat lock sound")
	enemies[0].global_position += Vector3(0, 0, 50)
	player._update_combat_targets()
	enemies[0].global_position = player.global_position + Vector3(0, 0, 1.2)
	player._update_combat_targets()
	_check(SfxManager._next_idx == before, "brief same-target cursor flicker is silent")
	if enemies.size() > 1:
		enemies[0].global_position += Vector3(0, 0, 50)
		enemies[1].global_position = player.global_position + Vector3(0, 0, 1.2)
		player._update_combat_targets()
		_check(SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "switching enemy plays lock sound")
		before = SfxManager._next_idx
	for enemy in enemies: enemy.global_position = player.global_position + Vector3(0, 0, 50)
	player._update_combat_targets()
	_check(SfxManager._next_idx == before, "losing cursor is silent")
	for i in enemies.size(): enemies[i].global_position = positions[i]

func _verify_feedback(player, enemy) -> void:
	player._recovery_left = 0
	player.transition_to(player.PlayerState.IDLE)
	_check(Rules.palette_cue(player).is_empty(), "palette cue hidden while idle")
	player._start_strong_attack()
	player._handle_attack_state(Rules.READY_PREP)
	player._update_combo_ring(0.01)
	_check(player._combo_ring == null or not player._combo_ring.visible, "prototype has no ground combo ring")
	_check(player._charge_ring == null or not player._charge_ring.visible, "prototype has no ground charge ring")
	_check(player._charge_particles.amount == 8 and player._charge_particles.emitting, "strong windup emits small weapon sparks")
	player._attack_anim_elapsed = player._attack_anim_length * 0.2
	_check(not Rules.palette_cue(player).ready, "palette countdown precedes valid window")
	player._attack_anim_elapsed = player._attack_anim_length * 0.65
	_check(Rules.palette_cue(player).ready, "palette ready matches accepted chain window")
	player._start_attack()
	_check(Rules.palette_cue(player).queued, "palette confirms queued follow-up")
	player.animation_player.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	await _snapshot("palette_chain_cue")
	player.transition_to(player.PlayerState.IDLE)
	_check(Rules.palette_cue(player).is_empty() and not player._charge_active, "interruption clears palette and charge feedback")
	var saved_hp: int = enemy.current_hp
	enemy.current_hp = 10000
	var packet: Dictionary = player._get_attack_damage()
	packet["prototype_strong"] = true
	var before: int = SfxManager._next_3d_idx
	enemy.hurtbox.take_attack(packet, Vector3.ZERO, player)
	_check(enemy.current_state == enemy.EnemyState.HURT and enemy.hurt_timer >= 0.45, "strong contact produces extended flinch")
	_check(SfxManager._next_3d_idx != before, "strong contact plays impact sound")
	_check(not get_tree().get_nodes_in_group("saber_contact_feedback").is_empty(), "actual damage emits subtle contact spark")
	enemy.current_hp = saved_hp
	await get_tree().create_timer(0.4).timeout
	_check(get_tree().get_nodes_in_group("saber_contact_feedback").is_empty(), "contact sparks clean themselves up")

func _verify_ready_recovery(player, enemy) -> void:
	player._recovery_left = 0
	player._hit_invulnerability_left = 0
	player.transition_to(player.PlayerState.IDLE)
	player.player_rotation = 0.0
	enemy.global_position = player.global_position + Vector3(0, 0, 1.5)
	player._start_attack()
	_check(not player.try_prototype_guard(enemy), "first-attack preparation is vulnerable")
	player._handle_attack_state(0.05)
	_check(player._saber_phase == "prepare" and player.animation_player.current_animation == (_pso_prefix + "_wait"), "ready stance persists beyond 50 ms")
	_check(is_equal_approx(player.animation_player.get_blend_time((_native_prefix + "_wait"), (_pso_prefix + "_wait")), Rules.READY_BLEND), "idle blends into ready stance")
	_check(is_equal_approx(player.animation_player.get_blend_time((_pso_prefix + "_wait"), (_native_prefix + "_atk1")), Rules.READY_BLEND), "ready blends into first swing")
	player._handle_attack_state(Rules.READY_PREP)
	player._attack_anim_elapsed = player._attack_anim_length * 0.1
	player._try_queue_combo(false)
	player._attack_step_finished()
	_check(player._saber_phase == "open_recovery" and not player.try_prototype_guard(enemy), "fumbled combo recovery cannot block")
	player._start_attack()
	_check(player._saber_phase == "open_recovery", "attack cannot cancel failed-combo recovery")
	player._handle_attack_state(Rules.BROKEN_RECOVERY)
	_check(player.current_state == player.PlayerState.IDLE, "failed recovery expires")
	player._start_attack()
	player._handle_attack_state(Rules.READY_PREP)
	for step in range(2):
		player._attack_anim_elapsed = player._attack_anim_length * 0.65
		player._try_queue_combo(false)
		player._attack_step_finished()
	player._attack_step_finished()
	_check(player._saber_phase == "guard_recovery", "third swing earns guarded cooldown")
	enemy.global_position = player.global_position - Vector3(0, 0, 1.5)
	_check(not player.try_prototype_guard(enemy), "ready cooldown still exposes rear")
	enemy.global_position = player.global_position + Vector3(0, 0, 1.5)
	_check(player.try_prototype_guard(enemy), "ready cooldown blocks frontal retaliation")
	_check(player._saber_phase.is_empty(), "block consumes the ready phase")
	player.transition_to(player.PlayerState.IDLE)

func _verify_combo_outcomes(player, enemy) -> void:
	player._recovery_left = 0
	player._saber_attack_cooldown = 0
	player.transition_to(player.PlayerState.IDLE)
	player._start_attack()
	player._handle_attack_state(Rules.READY_PREP)
	player._attack_step_finished()
	_check(player.current_state == player.PlayerState.IDLE and player._saber_attack_cooldown > 0, "intentional stop frees movement but starts attack cooldown")
	Input.action_press("move_forward")
	player._handle_movement(0.1)
	Input.action_release("move_forward")
	_check(player.current_state in [player.PlayerState.WALKING, player.PlayerState.RUNNING], "stopped combo can move during attack cooldown")
	player._start_attack()
	player._start_strong_attack()
	_check(player.current_state != player.PlayerState.ATTACKING, "stopped cooldown rejects normal and strong attacks")
	_check(not player.try_prototype_guard(enemy), "stopped combo does not earn finisher guard")
	player._tick_saber_attack_cooldown(Rules.STOPPED_ATTACK_COOLDOWN)
	player._start_attack()
	_check(player._saber_phase == "prepare", "attack becomes available after stopped cooldown")
	player._handle_attack_state(Rules.READY_PREP)
	player._attack_anim_elapsed = player._attack_anim_length * 0.99
	player._try_queue_combo(true)
	player._attack_step_finished()
	_check(player._saber_phase == "open_recovery", "late press fails rather than counting as an intentional stop")
	player._start_dodge()
	_check(player._saber_phase == "open_recovery", "failed combo cannot dodge out of exposure")
	player._handle_attack_state(Rules.BROKEN_RECOVERY)
	_check(player.current_state == player.PlayerState.IDLE, "failed recovery releases player after its delay")

func _verify_sword_contacts(player, enemies: Array) -> void:
	var saved: Array = []
	for enemy in enemies:
		saved.append({"position": enemy.global_position, "hp": enemy.current_hp})
	_check(player._run_anim == _pso_prefix + "_run" and player.animation_player.has_animation(_pso_prefix + "_run"), "sword explicitly shares gender-matched PSO saber run")
	if player.animation_player.has_animation(_pso_prefix + "_run"):
		_verify_root(player.animation_player.get_animation(_pso_prefix + "_run"), "shared sword run")
	for role in ["run", "walk_ready", "wait"]:
		var clip: String = _pso_prefix + "_" + str(role)
		player.animation_player.stop()
		player.play_animation(clip, true)
		player.animation_player.seek(0.3, true)
		player.skeleton.force_update_all_bone_transforms()
		var bone: Transform3D = player.skeleton.global_transform * player.skeleton.get_bone_global_pose(player.skeleton.find_bone("070_RArm02"))
		player._weapon_grip_tween.custom_step(1.0)
		var blade_direction: Vector3 = (bone.basis * Basis(player.weapon_node.quaternion) * Vector3.BACK).normalized()
		_check(blade_direction.dot(Vector3.UP) > 0.99, clip + " carries sword tip vertically upward")
		player.animation_player.pause()
		await _snapshot(clip + "_grip")

	var config: Dictionary = CombatManager.get_weapon_type_config(WeaponData.WeaponType.SWORD)
	_check(config.max_targets == 3 and config.turn_limit_deg == [60, 60], "sword keeps three-target cap and 60 degree chain turns")
	for step in range(3):
		for i in enemies.size():
			enemies[i].global_position = player.global_position + Vector3(0, 0, 1.2 + i * 0.25)
			enemies[i].current_hp = 10000
		player._recovery_left = 0
		player._saber_attack_cooldown = 0
		player.transition_to(player.PlayerState.IDLE)
		player.player_rotation = 0
		player._start_attack()
		player._handle_attack_state(Rules.READY_PREP)
		player.combo_state = step + 1
		player._play_attack_animation(step + 1, true)
		player._weapon_grip_tween.custom_step(1.0)
		_check(player.weapon_node.quaternion.is_equal_approx(Quaternion(Vector3.UP, PI / 2.0)), "sword swing restores native grip")
		var contact: float = Rules.profile(player).contact[step] * (player._attack_anim_length - Rules.profile(player).recovery[step])
		player._attack_anim_elapsed = contact - 0.001
		player._update_attack_contact(0)
		_check(enemies[0].current_hp == 10000, "sword step %d has no early contact" % (step + 1))
		player._attack_anim_elapsed = contact + 0.001
		player._update_attack_contact(contact - 0.001)
		var hit_count := 0
		for enemy in enemies:
			if enemy.current_hp < 10000: hit_count += 1
		_check(hit_count == mini(3, enemies.size()), "sword step %d hits exactly its target budget" % (step + 1))
		var hp: int = enemies[0].current_hp
		player._update_attack_contact(contact)
		_check(enemies[0].current_hp == hp, "sword contact cannot repeat next frame")
	player.transition_to(player.PlayerState.IDLE)
	for i in enemies.size():
		enemies[i].global_position = saved[i].position
		enemies[i].current_hp = saved[i].hp

func _verify_dagger_contacts(player, enemies: Array) -> void:
	var saved: Array = []
	for enemy in enemies: saved.append({"position": enemy.global_position, "hp": enemy.current_hp})
	_check(player.skeleton.has_node("WeaponAttachment_R") and player.skeleton.has_node("WeaponAttachment_L"), "daggers attach to both hands")
	var expected_left := Basis(Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(1, 0, 0))
	_check(player.weapon_node_left.basis.orthonormalized().is_equal_approx(expected_left) and is_equal_approx(player.weapon_node.rotation_degrees.y, 90.0), "left dagger uses owner-saved grip; right grip unchanged")
	var native_model: String = WeaponRegistry.get_weapon("ein_dagger").glb_path
	_check(player.weapon_node.scene_file_path == native_model and player.weapon_node_left.scene_file_path == native_model, "both daggers use native PSZ Ein Dagger model")
	_check(player._get_equipped_weapon_data().id == "dagger", "visual swap preserves equipped dagger combat stats")
	_check(player._run_anim == _pso_prefix + "_run" and player.animation_player.has_animation(_pso_prefix + "_run"), "daggers use gender-matched PSO saber run donor")
	_verify_root(player.animation_player.get_animation(_pso_prefix + "_run"), "dagger run")
	for role in ["run", "walk_ready", "wait", "block", "dam_h", "dam_d_wa", "dam_n", "dam_d", "pb"]:
		var clip: String = _pso_prefix + "_" + str(role)
		player.animation_player.stop()
		player.play_animation(clip, true)
		player.animation_player.seek(0.3, true)
		player.animation_player.pause()
		await _snapshot(clip)

	var geometry: Dictionary = player._weapon_combat_config(WeaponData.WeaponType.DAGGERS)
	player.player_rotation = 0
	for enemy in enemies: enemy.global_position = player.global_position + Vector3(0, 0, 10)
	enemies[0].global_position = player.global_position + Vector3(0.8, 0, 2.2)
	_check(player._enemies_in_hit_cone(geometry).has(enemies[0]), "daggers reach an offset enemy at practical melee distance")
	player._update_combat_targets()
	_check(player._targeted_enemies.has(enemies[0]), "dagger cursor agrees with widened contact geometry")
	enemies[0].global_position = player.global_position + Vector3(0, 0, 4)
	_check(not player._enemies_in_hit_cone(geometry).has(enemies[0]), "daggers cannot hit distant enemies")
	enemies[0].global_position = player.global_position + Vector3(0, 0, -1.5)
	_check(not player._enemies_in_hit_cone(geometry).has(enemies[0]), "daggers cannot hit behind the player")
	player.combo_state = 3
	player._is_special_attack = false
	seed(791)
	var normal: Dictionary = player._get_attack_damage()
	player._is_special_attack = true
	seed(791)
	var strong: Dictionary = player._get_attack_damage()
	_check(is_equal_approx(float(strong.power_multiplier), float(normal.power_multiplier) * 1.5), "third dagger swing snapshots strong power for all three contacts")
	var config: Dictionary = CombatManager.get_weapon_type_config(WeaponData.WeaponType.DAGGERS)
	_check(config.max_targets == 1 and config.turn_limit_deg == [120, 120], "dagger target cap and turn limits preserved")
	for step in range(3):
		for i in enemies.size():
			enemies[i].global_position = player.global_position + Vector3(0, 0, 1.1 + i * 0.2)
			enemies[i].current_hp = 10000
		player._recovery_left = 0
		player._saber_attack_cooldown = 0
		player.transition_to(player.PlayerState.IDLE)
		player.player_rotation = 0
		player._start_strong_attack()
		player._handle_attack_state(Rules.READY_PREP)
		player.combo_state = step + 1
		player._play_attack_animation(step + 1, true)
		var hits: Array = Rules.profile(player).hit_fracs[step]
		var motion_length: float = player._attack_anim_length - Rules.profile(player).recovery[step]
		for fraction in hits:
			var contact: float = float(fraction) * motion_length
			enemies[0].remove_meta("dagger_feedback_ms")
			var hp: int = enemies[0].current_hp
			player._attack_anim_elapsed = contact - 0.001
			player._update_attack_contact(0)
			_check(enemies[0].current_hp == hp, "dagger contact never fires early")
			player._attack_anim_elapsed = contact + 0.001
			player._update_attack_contact(contact - 0.001)
			_check(enemies[0].current_hp < hp, "dagger authored contact lands on step %d" % (step + 1))
			_check(enemies[0].hurt_timer >= 0.45, "every strong dagger contact gets extended strong flinch")
			hp = enemies[0].current_hp
			player._update_attack_contact(contact)
			_check(enemies[0].current_hp == hp, "dagger contact never repeats next frame")
		_check(player._attack_hit_step == [2, 1, 3][step] and player._attack_hit_done, "dagger preserves decoded 2/1/3 contacts")
		for i in range(1, enemies.size()): _check(enemies[i].current_hp == 10000, "dagger respects single target per impact")
	player.transition_to(player.PlayerState.IDLE)
	for i in enemies.size():
		enemies[i].global_position = saved[i].position
		enemies[i].current_hp = saved[i].hp
