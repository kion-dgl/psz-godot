extends "res://scripts/tools/probe_checks.gd"
## Run: godot --headless --path . res://scripts/tools/systems_progression_probe.tscn
## Isolated live route for the combined five-issue PR; uses actual imported rigs.
const Growth := preload("res://scripts/utils/enemy_progression.gd")
var _failures: Array[String] = []

func _run() -> void:
	probe_label = "systems"
	get_tree().current_scene = null
	CharacterManager._characters.clear()
	CharacterManager._characters.resize(20)
	CharacterManager._active_slot = -1
	var ch := CharacterManager.create_character(0, "humar", "SystemsProbe")
	CharacterManager.set_active_slot(0)
	SessionManager.enter_quest("debug_coliseum", "normal")
	SessionManager.set_field_sections(ColiseumRoster.make_sections("ghowl"))
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
	var player: Node3D
	for frame in 600:
		await get_tree().physics_frame
		player = get_tree().get_first_node_in_group("player")
		if player and not get_tree().get_nodes_in_group("enemies").is_empty():
			break
	if player == null:
		_verify(false, "arena loads player")
	else:
		await get_tree().create_timer(0.3).timeout
		player.set_physics_process(false)
		var enemy = get_tree().get_first_node_in_group("enemies")
		enemy.set_physics_process(false)
		await _combat(player, enemy, ch)
	print("[systems] DONE %s failures=%s" % ["ok" if _failures.is_empty() else "FAIL", _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _combat(player: Node3D, enemy: EnemyBase, ch: Dictionary) -> void:
	_verify(enemy.enemy_level == 1 and enemy.current_hp == 95, "fresh arena uses original lizard HP at authored level one")
	player.global_position = enemy.global_position + Vector3(0, 0, 1.5)
	player.player_rotation = PI
	var before := enemy.current_hp
	seed(723)
	player.combo_state = 1
	player._execute_attack_hit()
	var damage := before - enemy.current_hp
	print("[systems] fresh HUmar Saber: hp=%d actual_first_hit=%d stats=%s" % [before, damage, CombatManager._get_player_stats(ch)])
	_verify(enemy.current_hp > 0, "fresh normal swing cannot one-shot ordinary enemy")
	# Damage delivery through the real melee cone; misses retain their consumed contact.
	var after_contact := enemy.current_hp
	player._execute_attack_hit()
	_verify(enemy.current_hp == after_contact, "one swing cannot repeatedly damage the same enemy")
	var exp_before: int = ch.experience
	var swings := 1
	while enemy.is_alive and swings < 40:
		player._deactivate_attack_hitbox()
		player.combo_state = 1
		player._execute_attack_hit()
		swings += 1
	_verify(not enemy.is_alive and ch.experience > exp_before, "actual weapon kill grants persistent EXP")
	var after_exp: int = ch.experience
	enemy._die()
	_verify(ch.experience == after_exp, "repeat death grants no duplicate EXP")
	print("[systems] first kill: swings_including_misses=%d exp=%d" % [swings, ch.experience])
	# Reach level two using actual spawned enemy deaths, not injected EXP.
	var old_max_hp: int = ch.max_hp
	var field = get_tree().current_scene
	for kill in 6:
		field._cell_spawner._spawn_enemy(Vector3(0, 0, 6), "ghowl")
		var live = get_tree().get_nodes_in_group("enemies").filter(func(n): return n is EnemyBase and n.is_alive)
		if live.is_empty():
			_verify(false, "progression enemy spawned")
			break
		var next: EnemyBase = live.back()
		next.set_physics_process(false)
		player.global_position = next.global_position + Vector3(0, 0, 1.5)
		for swing in 40:
			player._deactivate_attack_hitbox()
			player.combo_state = 1
			player._execute_attack_hit()
			if not next.is_alive:
				break
		await get_tree().process_frame
	_verify(ch.level == 2 and ch.max_hp > old_max_hp, "seven real kills reach level two and increase HP")
	_verify(int(SessionManager.get_session().total_exp) == int(ch.experience), "session report and persistent kill EXP agree")
	await _grinding(ch)
	await _blasts(player, ch)
	SaveManager.save_game()
	var saved_exp: int = ch.experience
	CharacterManager._characters.clear()
	CharacterManager._characters.resize(20)
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	SaveManager.load_game()
	CharacterManager.set_active_slot(0)
	var loaded = CharacterManager.get_active_character()
	_verify(loaded.experience == saved_exp and loaded.weapon_grinds.saber == 5, "earned EXP and grind survive hard disk reload")
	_verify(Inventory.get_item_count("monogrinder") == 0, "consumed grinders stay consumed")

func _blasts(player: Node3D, ch: Dictionary) -> void:
	_verify(not PhotonBlast.activate(player), "unevolved mag cannot blast")
	var mag: Dictionary = ch.mag_states.mag
	mag.stats.power = 50
	mag.form_id = "yul"
	player.current_state = player.PlayerState.IDLE
	PhotonBlast.gauge = 0
	PhotonBlast.gain_damage(0, 100, false)
	_verify(PhotonBlast.gauge == 0, "misses do not charge PB")
	PhotonBlast.gain_damage(20, 100, false)
	_verify(PhotonBlast.gauge > 0, "dealt damage charges evolved mag")
	var start := PhotonBlast.gauge
	GameState.set_hp(GameState.max_hp)
	player.take_damage(5)
	_verify(PhotonBlast.gauge > start, "actual player damage charges PB")
	for form in ["yul", "yth", "aio", "ingh"]:
		mag.form_id = form
		player.current_state = player.PlayerState.IDLE
		player._recovery_left = 0.0
		PhotonBlast.gauge = PhotonBlast.MAX_GAUGE
		var target := EnemyBase.new()
		target.enemy_data = Growth.scaled(EnemyRegistry.get_enemy("ghowl"), 1)
		get_tree().current_scene.add_child(target)
		target.global_position = player.global_position + Vector3(0, 0, -3)
		target.set_physics_process(false)
		var hp := target.current_hp
		var blast := PhotonBlast.equipped_blast()
		_verify(PhotonBlast.activate(player), "%s activates" % blast)
		_verify(not PhotonBlast.activate(player) and PhotonBlast.gauge == 0, "repeat activation cannot spend/fire again")
		var player_hp := GameState.hp
		player.take_technique_hit(10, "barta", 0.0)
		_verify(GameState.hp == player_hp and not player.has_status_effects(), "blast presentation blocks damage and technique ailments")
		await get_tree().create_timer(1.7).timeout
		if blast in ["Granir", "Pacifal"]:
			_verify(target.current_hp < hp and PhotonBlast.gauge == 0, "%s damages without self-charging" % blast)
		elif blast == "Midgul":
			_verify(target.attack_multiplier == 0.75 and target.current_defense < target.enemy_data.defense_base, "Midgul weakens ATP and DFP")
			var debuff = target.get_node("PhotonDebuff")
			debuff.refresh()
			debuff._physics_process(21.0)
			_verify(is_equal_approx(target.attack_multiplier, 1.0) and target.current_defense == target.enemy_data.defense_base, "refreshed Midgul restores original stats on expiry")
		else:
			_verify(PhotonBlast.flozir_left > 0.0, "Flozir starts timed PP benefit")
			ch.techniques["foie"] = 1
			GameState.set_mp(0)
			player._cast_technique("foie")
			_verify(player.current_state == player.PlayerState.ATTACKING and GameState.mp == 0, "Flozir permits a real cast at zero PP")
			player.transition_to(player.PlayerState.IDLE)
			PhotonBlast._process(21.0)
			player._cast_technique("foie")
			_verify(player.current_state == player.PlayerState.IDLE and PhotonBlast.flozir_left == 0.0, "expired Flozir restores PP requirement")
		_verify(player.current_state == player.PlayerState.IDLE, "blast returns control")
		target.queue_free()
		await get_tree().process_frame
	PhotonBlast.gauge = PhotonBlast.MAX_GAUGE
	_verify(PhotonBlast.activate(player), "blast can begin before a session reset")
	PhotonBlast.reset()
	await get_tree().create_timer(1.0).timeout
	_verify(player.current_state == player.PlayerState.IDLE and PhotonBlast.flozir_left == 0.0, "session reset cancels delayed blast release and restores control")
	PhotonBlast.gauge = PhotonBlast.MAX_GAUGE
	ch.equipment.mag = ""
	PhotonBlast._process(0.0)
	_verify(PhotonBlast.gauge == 0 and PhotonBlast.equipped_blast().is_empty(), "unequipping mag clears gauge and availability")
	ch.equipment.mag = "mag"
	PhotonBlast.reset()
	_verify(PhotonBlast.gauge == 0 and PhotonBlast.flozir_left == 0, "session reset clears gauge and temporary buff")

func _verify(condition: bool, label: String) -> void:
	print("[systems] %s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)

func _grinding(ch: Dictionary) -> void:
	# Real shop transaction, instance distinction and persistence.
	var other := Inventory.add_weapon("saber")
	Inventory.add_item("monogrinder", 5)
	GameState.meseta = 10000
	ch.meseta = 0
	var shop = load("res://scenes/2d/shops/tekker.tscn").instantiate()
	get_tree().root.add_child(shop)
	_verify(shop._get_meseta() == 10000, "shop displays carried wallet instead of stale save snapshot")
	seed(734)
	var unground := CombatManager.calculate_attack_damage(1)
	for i in 5:
		shop._selected_index = shop._grindable_weapons.find_custom(func(w): return w.id == "saber")
		shop._grind_selected()
		_verify(int(ch.weapon_grinds.get("saber", 0)) == i + 1, "Tekker accept action grinds once: %d" % i)
	seed(734)
	var ground := CombatManager.calculate_attack_damage(1)
	_verify(int(ground.damage) > int(unground.damage), "grind changes live attack inputs")
	_verify(int(ch.weapon_grinds.get(other, 0)) == 0, "second weapon instance remains unground")
	shop.queue_free()
	await get_tree().process_frame
