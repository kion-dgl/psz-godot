extends RefCounted
## #554: imported clips, normal player physics, real enemy Hurtbox signals.
## Controlled target motion; no manual attack elapsed/length or hit-handler calls.

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	seed(554)
	var character: Dictionary = CharacterManager.get_active_character()
	var saved_weapon: String = character.equipment.get("weapon", "")
	var enemy_pos := enemy.global_position
	var player_pos := player.global_position
	var enemy_hp := enemy.current_hp
	var enemy_physics := enemy.is_physics_processing()
	enemy.set_physics_process(false)
	var ok := true
	for weapon in ["saber", "sword", "daggers"]:
		character.equipment.weapon = weapon
		player.transition_to(player.PlayerState.IDLE)
		player.refresh_weapon()
		for mode in ["early_only", "late_entry", "after_close", "interrupt", "combo"]:
			player.global_position = player_pos
			player.player_rotation = PI
			enemy.current_hp = maxi(enemy_hp, 100000)
			var result := await _case(player, enemy, weapon, mode)
			print("[melee-live] RESULT " + JSON.stringify(result))
			ok = ok and bool(result.passed)
	player.transition_to(player.PlayerState.IDLE)
	character.equipment.weapon = saved_weapon
	player.refresh_weapon()
	player.global_position = player_pos
	enemy.global_position = enemy_pos
	enemy.current_hp = enemy_hp
	enemy.set_physics_process(enemy_physics)
	print("[melee-live] DONE " + ("ok" if ok else "FAIL"))
	return ok


static func _case(player: Node3D, enemy: EnemyBase, weapon: String, mode: String) -> Dictionary:
	var contacts: Array[Dictionary] = []
	var clips: Dictionary = {}
	var capture := func(_damage: int, _kb: Vector3, _accuracy: int) -> void:
		contacts.append({"step": player.combo_state, "fraction": player._attack_frac(),
			"animation": player.animation_player.current_animation,
			"animation_position": player.animation_player.current_animation_position})
	enemy.hurtbox.hit_received.connect(capture)
	player.transition_to(player.PlayerState.IDLE)
	enemy.global_position = player.global_position + Vector3(0, 0, -20)
	player._start_attack() # Same entry point as the normal attack action.
	var finished := false
	var interrupted := false
	var valid_clips := true
	for tick in range(600):
		if player.current_state != player.PlayerState.ATTACKING:
			finished = true
			break
		var step: int = player.combo_state
		var clip: String = player._anim_prefix + "_atk" + str(step)
		if not player.animation_player.has_animation(clip):
			valid_clips = false
			break
		clips[str(step)] = {"name": clip, "length": player.animation_player.get_animation(clip).length}
		var frac: float = player._attack_frac()
		# Independently authored expectations: saber/sword .40/.40/.45;
		# daggers .35/.35/.40. Active duration .15 is explicitly Godot tuning.
		var opening := (0.35 if weapon == "daggers" else 0.40) + (0.05 if step == 3 else 0.0)
		var inside := _target_inside(mode, frac, opening)
		enemy.global_position = player.global_position + Vector3(0, 0, -1.5 if inside else -20.0)
		if mode == "interrupt" and frac >= opening - 0.10:
			player.transition_to(player.PlayerState.DAMAGED)
			interrupted = true
		if mode == "combo" and step < 3 and frac >= 0.75:
			player._start_attack() # Queues normally; no forced combo_state.
		await player.get_tree().physics_frame
	# Observe several further ticks to catch deferred/stored damage after an exit.
	for tick in range(4):
		await player.get_tree().physics_frame
	enemy.hurtbox.hit_received.disconnect(capture)
	return _verdict(weapon, mode, contacts, clips, finished, valid_clips, interrupted)


static func _verdict(weapon: String, mode: String, contacts: Array[Dictionary], clips: Dictionary, finished: bool, valid_clips: bool, interrupted: bool) -> Dictionary:
	var expected := [0, 0, 0]
	if mode in ["late_entry", "combo"]:
		expected = [2, 2, 3] if weapon == "daggers" else [1, 1, 1]
		if mode != "combo":
			expected = [expected[0], 0, 0]
	var actual := [0, 0, 0]
	var within_window := true
	for contact in contacts:
		var step: int = int(contact.step)
		if step < 1 or step > 3:
			within_window = false
			continue
		actual[step - 1] += 1
		var opening := (0.35 if weapon == "daggers" else 0.40) + (0.05 if step == 3 else 0.0)
		within_window = within_window and float(contact.fraction) >= opening and float(contact.fraction) < opening + 0.15
	return {"weapon": weapon, "mode": mode, "clips": clips, "contacts": contacts,
		"expected": expected, "actual": actual, "finished": finished,
		"passed": finished and valid_clips and within_window and actual == expected and (mode != "interrupt" or interrupted)}


static func _target_inside(mode: String, fraction: float, opening: float) -> bool:
	match mode:
		"early_only": return fraction < opening - 0.10
		"after_close": return fraction >= opening + 0.18
		"interrupt": return fraction >= opening - 0.10
		_: return fraction >= opening + 0.025
