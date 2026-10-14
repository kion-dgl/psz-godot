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
	for kind in ["needle_trap"]:
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
	_reset(player)
	await player.get_tree().create_timer(NeedleTrap.EXTENDED_TIME + 0.15).timeout
	ok = Check._check(not trap.spikes_extended and GameState.hp == hp, "needle retracts and cannot hit twice in one extension") and ok
	player.global_position = origin + Vector3(8, 0, 0)
	await _settle(player)
	player.global_position = origin
	await _settle(player)
	ok = Check._check(GameState.hp == hp, "entering retracted needles is safe") and ok
	await player.get_tree().create_timer(NeedleTrap.RETRACTED_TIME).timeout
	ok = Check._check(trap.spikes_extended and GameState.hp == hp - trap.damage, "next extension hits player still on plate") and ok
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
	return await preload("res://scripts/tools/bear_trap_check.gd").run(player, origin)

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
		if node is BearTrap or node is NeedleTrap or node is FieldHazard: node.queue_free()
	await _settle(player)
	# Use the real restore dispatcher with only these fixture records.
	spawner._restore_cell_objects({"objects": records, "drops": []})
	await _settle(player)
	var restored: Array = spawner._placed_trap_states()
	ok = Check._check(restored.size() == 7, "room revisit restores all floor traps") and ok
	for record in records:
		ok = Check._check(restored.has(record), "room revisit preserves " + record.type + " position and " + record.state + " state") and ok
	for node in field._map_root.get_children():
		if node is BearTrap or node is NeedleTrap or node is FieldHazard: node.queue_free()
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
