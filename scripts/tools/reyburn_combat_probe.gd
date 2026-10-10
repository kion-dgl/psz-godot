extends Node
## Actual arena/rig delivery probe. Uses isolated XDG_DATA_HOME, PSZ_PROBE_PACK.
var _ok := true

func _ready() -> void:
	var pack := OS.get_environment("PSZ_PROBE_PACK")
	if not pack.is_empty():
		if not ProjectSettings.load_resource_pack(pack, false):
			get_tree().quit(1)
			return
	_run.call_deferred()

func _run() -> void:
	# Keep the observer alive across the real field transition.
	get_tree().current_scene = null
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "BossProbe")
	CharacterManager.set_active_slot(0)
	SessionManager.enter_quest("debug_boss_reyburn", "normal")
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": "0,0", "spawn_edge": "", "keys_collected": {}})
	var boss: ReyburnBoss
	for frame in 600:
		await get_tree().physics_frame
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy is ReyburnBoss: boss = enemy
		if boss: break
	if not boss:
		_check(false, "arena boss spawned")
	else:
		await get_tree().create_timer(0.2).timeout
		await _exercise(boss)
	print("[reyburn-combat] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _exercise(boss: ReyburnBoss) -> void:
	var player = get_tree().get_first_node_in_group("player")
	boss.set_physics_process(false)
	player.set_physics_process(false)
	boss.target = player
	boss.rotation.y = 0
	player.global_position = boss.global_position + Vector3(0, 0, 3)
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.IDLE
	var hp := GameState.hp
	_check(boss._arc_hit(4, 60, 1) and GameState.hp == hp - 1, "real player in front receives bite")
	player.global_position = boss.global_position + Vector3(0, 0, -3)
	_check(not boss._arc_hit(4, 60, 1), "real player behind avoids bite")
	var wing: Dictionary = {}
	for attack in boss._ground_attacks:
		if attack.id == "wing_flap": wing = attack
	boss._begin_attack(wing)
	var prelude := boss._boss_clip_duration("wat2atkwg", 0.35)
	_check(not boss._find_animation("wat2atkwg").is_empty(), "imported wing prelude resolves")
	_check(absf(boss._t - prelude) < 0.001, "real prelude uses imported duration")
	hp = GameState.hp
	boss._tick_telegraph(prelude * 0.9)
	_check(boss._s == boss.S.TELEGRAPH and GameState.hp == hp, "windup remains harmless")
	boss._tick_telegraph(prelude * 0.11)
	_check(boss._s == boss.S.ATTACK, "wing starts after prelude")
	player.global_position = boss.global_position + Vector3(0, 0, 3)
	player.current_state = player.PlayerState.IDLE
	boss.rotation.y = 0
	var duration := boss._t
	boss._tick_attack(duration * 0.54)
	_check(GameState.hp == hp, "before strike threshold harmless")
	boss._tick_attack(duration * 0.02)
	_check(GameState.hp < hp, "strike threshold damages real player")
	hp = GameState.hp
	boss._tick_attack(duration * 0.1)
	_check(GameState.hp == hp, "same strike cannot repeat damage")
	player.global_position = boss.global_position + Vector3(0, 0, 10)
	boss._walk_toward(player.global_position, 0.1)
	await get_tree().create_timer(0.15).timeout
	boss._walk_toward(player.global_position, 0.1)
	_check(boss.animation_player.current_animation_position > 0.1, "real walking animation advances")
	boss._die()
	await get_tree().create_timer(0.2).timeout
	_check(not boss.is_alive, "encounter can be defeated after attack")

func _check(condition: bool, message: String) -> void:
	_ok = condition and _ok
	print("[reyburn-combat] %s: %s" % ["PASS" if condition else "FAIL", message])
