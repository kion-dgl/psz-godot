extends RefCounted
## Real Area3D overlap checks, not direct calls to body-entered handlers.
const Check := preload("res://scripts/tools/gameplay_recovery_check.gd")
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var tree := player.get_tree()
	await tree.create_timer(2.0).timeout
	enemy.set_physics_process(false)
	enemy.global_position += Vector3(0, 0, 100)
	player.set_physics_process(false)
	Inventory._items.erase("scape_doll")
	var origin := player.global_position
	var ok := true
	for kind in ["needle_trap", "needler_trap", "burn_trap", "gun_trap", "poison_trap"]:
		ok = await _needle(player, origin, kind) and ok
	ok = await _bear(player, origin) and ok
	ok = await _persistence(player, origin) and ok
	await _visuals(player)
	player.global_position = origin
	_reset(player)
	return ok

static func _reset(player: Node3D) -> void:
	player._is_defeated = false
	player._recovery_left = 0.0
	player.clear_status_effects()
	player.transition_to(player.PlayerState.IDLE)
	GameState.set_hp(GameState.max_hp)

static func _settle(player: Node3D) -> void:
	for i in 4: await player.get_tree().physics_frame
	await player.get_tree().process_frame

static func _needle(player: Node3D, origin: Vector3, kind: String) -> bool:
	_reset(player)
	player.global_position = origin + Vector3(8, 0, 0)
	var trap := NeedleTrap.new()
	trap.trap_kind = kind
	trap.damage = int(CellObjectSpawner.CONTACT_TRAP_DAMAGE.get(kind, NeedleTrap.DAMAGE_AMOUNT))
	player.get_parent().add_child(trap)
	trap.global_position = origin
	await _settle(player)
	player.global_position = origin
	await _settle(player)
	var hp := GameState.hp
	var ok := Check._check(GameState.hp == GameState.max_hp, kind + " off is safe during real overlap")
	trap.set_state("on")
	await _settle(player)
	ok = Check._check(GameState.hp == hp - trap.damage, kind + " activation under player deals configured damage") and ok
	# Heal without leaving the area, avoiding a lethal repeat on the 50-damage stand-in.
	_reset(player)
	await player.get_tree().create_timer(NeedleTrap.INVULN_TIME + 0.15).timeout
	ok = Check._check(GameState.hp == hp - trap.damage, kind + " remaining on spikes takes another hit after cooldown") and ok
	trap.set_state("off")
	_reset(player)
	await _settle(player)
	player._recovery_left = 1.0
	trap.set_state("on")
	await _settle(player)
	ok = Check._check(GameState.hp == hp, kind + " respects recovery immunity") and ok
	player._recovery_left = 0.0
	await _settle(player)
	ok = Check._check(GameState.hp == hp - trap.damage, kind + " immunity ending inside trap does not require re-entry") and ok
	_reset(player)
	player.global_position = origin + Vector3(8, 0, 0)
	await _settle(player)
	player.global_position = origin
	await _settle(player)
	ok = Check._check(GameState.hp == hp, kind + " rapid re-entry respects cooldown") and ok
	trap.set_state("off")
	await player.get_tree().create_timer(0.1).timeout
	ok = Check._check(GameState.hp == hp, kind + " disabled spikes stop damage") and ok
	trap.queue_free()
	await _settle(player)
	return ok

static func _bear(player: Node3D, origin: Vector3) -> bool:
	_reset(player)
	player.global_position = origin + Vector3(8, 0, 0)
	var bear := BearTrap.new()
	player.get_parent().add_child(bear)
	bear.global_position = origin
	await _settle(player)
	player.global_position = origin
	await _settle(player)
	var hp := GameState.hp
	var ok := Check._check(bear._is_holding and player.current_state == player.PlayerState.CUTSCENE, "bear physical overlap captures player")
	var held_at := player.global_position
	player.set_physics_process(true)
	Input.action_press("move_right")
	await player.get_tree().create_timer(0.3).timeout
	Input.action_release("move_right")
	player.set_physics_process(false)
	ok = Check._check(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(held_at.x, held_at.z)) < 0.05, "bear capture blocks actual movement input") and ok
	await player.get_tree().create_timer(0.7).timeout
	ok = Check._check(bear._is_holding and GameState.hp == hp, "bear holds before dealing damage") and ok
	await player.get_tree().create_timer(1.6).timeout
	ok = Check._check(not bear._is_holding and bear.element_state == "off" and GameState.hp == hp - BearTrap.DAMAGE_AMOUNT, "bear releases once after 2.5 seconds and deals 20 damage") and ok
	ok = Check._check(player.current_state == player.PlayerState.DAMAGED, "bear release preserves damage reaction") and ok
	_reset(player)
	bear.set_state("on")
	await _settle(player)
	bear.set_state("off")
	ok = Check._check(not bear._is_holding and player.current_state == player.PlayerState.IDLE, "disabling bear releases capture immediately without damage") and ok
	_reset(player)
	player._recovery_left = 1.0
	bear.set_state("on")
	await _settle(player)
	ok = Check._check(not bear._is_holding, "bear cannot capture immune player") and ok
	player._recovery_left = 0.0
	await _settle(player)
	ok = Check._check(bear._is_holding, "bear captures when immunity ends without re-entry") and ok
	player.take_damage(1)
	await _settle(player)
	ok = Check._check(not bear._is_holding and bear.element_state == "off" and player.current_state == player.PlayerState.DAMAGED, "external hit cancels bear hold without overwriting stagger") and ok
	_reset(player)
	bear.set_state("on")
	await _settle(player)
	bear.queue_free()
	await _settle(player)
	ok = Check._check(player.current_state == player.PlayerState.IDLE, "removing bear releases capture") and ok
	return ok

static func _persistence(player: Node3D, origin: Vector3) -> bool:
	var field := player.get_tree().current_scene
	var spawner: CellObjectSpawner = field._cell_spawner
	_reset(player)
	player.global_position = origin + Vector3(50, 0, 0)
	await _settle(player)
	for kind in ["bear_trap", "capture_trap", "needle_trap", "needler_trap", "burn_trap", "gun_trap", "poison_trap"]:
		spawner._spawn_placed_trap(origin, kind, "off" if kind.ends_with("capture_trap") or kind == "bear_trap" else "on")
	await _settle(player)
	spawner._save_cell_state()
	var key: String = str(field._current_cell.pos)
	var saved: Dictionary = field._cell_states[key].duplicate(true)
	var records: Array = saved.objects.filter(func(o): return o.type in ["bear_trap", "capture_trap", "needle_trap", "needler_trap", "burn_trap", "gun_trap", "poison_trap"])
	var ok := Check._check(records.size() == 7, "room snapshot retains all seven floor-trap identifiers")
	ok = Check._check(GameState.hp == GameState.max_hp, "floor traps do not damage a player outside their areas") and ok
	for node in field._map_root.get_children():
		if node is BearTrap or node is NeedleTrap: node.queue_free()
	await _settle(player)
	# Use the real restore dispatcher with only these fixture records.
	spawner._restore_cell_objects({"objects": records, "drops": []})
	await _settle(player)
	var restored: Array = spawner._placed_trap_states()
	ok = Check._check(restored.size() == 7, "room revisit restores all floor traps") and ok
	for record in records:
		ok = Check._check(restored.has(record), "room revisit preserves " + record.type + " position and " + record.state + " state") and ok
	for node in field._map_root.get_children():
		if node is BearTrap or node is NeedleTrap: node.queue_free()
	await _settle(player)
	return ok

static func _visuals(player: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	var bear := BearTrap.new()
	var needle := NeedleTrap.new()
	player.get_parent().add_child(bear)
	player.get_parent().add_child(needle)
	await Check._capture_materials(player, bear, needle)
	bear.queue_free()
	needle.queue_free()
