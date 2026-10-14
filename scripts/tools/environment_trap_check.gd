extends RefCounted
## Rendered/physics checks for each distinct environmental delivery.
const Check := preload("res://scripts/tools/gameplay_recovery_check.gd")
const Floor := preload("res://scripts/tools/floor_trap_check.gd")
const ORIGIN := Vector3(0, 30, 0) # Controlled fixture above room walls; explicit walls below.

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	await player.get_tree().create_timer(2.0).timeout
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position = ORIGIN + Vector3(40, 0, 0)
	DebugConfig.invincible = false
	Inventory._items.erase("scape_doll")
	var ok := true
	for variant in ["o0c_gun01", "o0c_gun02"]:
		ok = await _gun(player, variant) and ok
	ok = await _gun_wall(player) and ok
	ok = await _gun_dodge(player) and ok
	ok = await _bomb(player, enemy) and ok
	ok = await _needler(player) and ok
	ok = await _poison(player) and ok
	ok = await _edges(player) and ok
	ok = await _persistence(player) and ok
	await _visuals(player)
	ok = await preload("res://scripts/tools/trap_layout_check.gd").run(player.get_tree()) and ok
	return ok

static func _spawn(player: Node3D, kind: String, state: String = "on", record: Dictionary = {}) -> GameElement:
	var trap := PlacedTraps.build(kind, state, record)
	trap.position = ORIGIN
	player.get_tree().current_scene.add_child(trap)
	return trap

static func _wait(player: Node3D, seconds: float) -> void:
	await player.get_tree().create_timer(seconds).timeout
	await player.get_tree().process_frame
	await player.get_tree().process_frame
	await player.get_tree().physics_frame

static func _remove(player: Node3D, node: Node) -> void:
	node.queue_free()
	await _wait(player, 0.05)

static func _gun(player: Node3D, variant: String) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(6, 0, 0)
	var gun := _spawn(player, "gun_trap", "on", {"model": variant, "rotation": 90.0}) as GunTrap
	await _wait(player, 0.2)
	var ok := Check._check(gun.model != null and gun.element_state == "warning" and gun.shots_fired == 0, variant + " source mesh warns before firing along authored rotation")
	await _wait(player, 0.5)
	var bullets := gun.get_children().filter(func(n): return n is EnemyProjectile)
	ok = Check._check(bullets.size() == 1 and bullets[0].get_child_count() > 0 and bullets[0].model_path.ends_with("o0c_bullet01.glb"), variant + " releases the dedicated bullet mesh") and ok
	await _wait(player, 0.7)
	ok = Check._check(GameState.hp == GameState.max_hp - 8 and gun.shots_fired == 1, variant + " projectile travels and hits once, without rapid refire") and ok
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(-6, 0, 0)
	await _wait(player, 2.7)
	ok = Check._check(gun.shots_fired == 1 and GameState.hp == GameState.max_hp, variant + " does not acquire targets behind its authored facing") and ok
	gun.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 0.1)
	ok = Check._check(gun.element_state == "spent" and not gun.hurtbox.monitorable and not gun.model.visible, variant + " real hurtbox disables firing and targeting") and ok
	await _remove(player, gun)
	return ok

static func _wall(player: Node3D) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = ORIGIN + Vector3(0, 1, 3)
	player.get_tree().current_scene.add_child(wall)
	return wall

static func _gun_wall(player: Node3D) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(0, 0, 6)
	var wall := _wall(player)
	await _wait(player, 0.1)
	var gun := _spawn(player, "gun_trap") as GunTrap
	await _wait(player, 0.9)
	var ok := Check._check(gun.shots_fired == 0, "gun cannot acquire through a real wall")
	await _remove(player, wall)
	await _wait(player, 0.15)
	wall = _wall(player) # It aimed before the wall appeared: test actual shot blocking.
	await _wait(player, 1.0)
	ok = Check._check(gun.shots_fired == 1 and GameState.hp == GameState.max_hp and gun.get_children().filter(func(n): return n is EnemyProjectile).is_empty(), "released gun shot hits wall, expires, and cannot damage through it") and ok
	await _remove(player, wall)
	await _remove(player, gun)
	return ok

static func _gun_dodge(player: Node3D) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(0, 0, 6)
	var gun := _spawn(player, "gun_trap") as GunTrap
	await _wait(player, 0.7)
	player.transition_to(player.PlayerState.DODGING)
	player.dodge_timer = 0.0
	await _wait(player, 0.7)
	var ok := Check._check(gun.shots_fired == 1 and GameState.hp == GameState.max_hp, "dodge rejects an actual incoming turret shot")
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(5, 0, 6)
	await _wait(player, 1.3)
	player.global_position = ORIGIN + Vector3(-5, 0, 6)
	await _wait(player, 1.8)
	ok = Check._check(GameState.hp == GameState.max_hp, "turret aim stays locked when the player moves after warning") and ok
	await _remove(player, gun)
	return ok

static func _bomb(player: Node3D, enemy: EnemyBase) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(0, 0, -6)
	enemy.global_position = ORIGIN + Vector3(2, 0, 0)
	if enemy.dormant: enemy.reveal()
	var before := enemy.current_hp
	var bomb := _spawn(player, "burn_trap") as BombTrap
	await _wait(player, 0.1)
	player.player_rotation = 0.0
	player._fire_projectile({"weapon_type": 9, "hits": 1, "damage": 10, "accuracy": 100, "knockback": 0.0, "max_targets": 1})
	await _wait(player, 0.45)
	var ok := Check._check(bomb.element_state == "warning" and bomb.detonations == 0, "real player projectile starts bomb warning")
	bomb.hurtbox.take_hit(10, Vector3.ZERO)
	await _wait(player, 0.8)
	ok = Check._check(bomb.detonations == 1 and enemy.current_hp < before and GameState.hp == GameState.max_hp, "bomb blasts nearby enemy once; distant player is safe") and ok
	await _remove(player, bomb)
	enemy.global_position = ORIGIN + Vector3(40, 0, 0)
	player.global_position = ORIGIN + Vector3(0, 0, 2)
	bomb = _spawn(player, "burn_trap") as BombTrap
	await _wait(player, 0.3)
	ok = Check._check(GameState.hp == GameState.max_hp and bomb.element_state == "on", "bomb contact alone is harmless") and ok
	bomb.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 0.8)
	ok = Check._check(GameState.hp == GameState.max_hp - BombTrap.DAMAGE and bomb.detonations == 1, "bomb applies one nearby-player blast") and ok
	await _remove(player, bomb)
	Floor._reset(player)
	bomb = _spawn(player, "burn_trap") as BombTrap
	bomb.hurtbox.take_hit(1, Vector3.ZERO)
	player.transition_to(player.PlayerState.DODGING)
	player.dodge_timer = 0.0
	await _wait(player, 0.8)
	ok = Check._check(GameState.hp == GameState.max_hp and bomb.detonations == 1, "bomb blast respects dodge") and ok
	await _remove(player, bomb)
	return ok

static func _needler(player: Node3D) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(0, 0, -2)
	var trap := _spawn(player, "needler_trap") as NeedlerTrap
	await _wait(player, 0.2)
	var size := AreaObjects.model_extents(trap.model).size
	var ok := Check._check(size.x > 20.0 and trap.model.scale == Vector3.ONE and trap.element_state == "on", "clay keeps original full-size geometry; player behind it does not trigger")
	player.global_position = ORIGIN + Vector3(0, 0, 2)
	await _wait(player, 0.2)
	ok = Check._check(trap.element_state == "warning" and GameState.hp == GameState.max_hp, "Needler warns before directional sweep") and ok
	await _wait(player, 1.3)
	ok = Check._check(GameState.hp == GameState.max_hp - NeedlerTrap.DAMAGE and trap.sweeps == 1 and trap.element_state == "cooldown", "Needler hits once per expanding sweep and enters cooldown") and ok
	Floor._reset(player)
	await _wait(player, 1.0)
	ok = Check._check(GameState.hp == GameState.max_hp, "Needler cooldown causes no repeated contact damage") and ok
	trap.timer = 0.1 # Boundary test, rather than twelve seconds of idle waiting.
	player.global_position = ORIGIN + Vector3(4, 0, 0)
	await _wait(player, 0.2)
	trap.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 1.5)
	ok = Check._check(trap.sweeps == 2 and GameState.hp == GameState.max_hp, "Needler rearms; targets outside its cone are safe during an attack-triggered sweep") and ok
	trap.set_state("off")
	player.global_position = ORIGIN + Vector3(0, 0, 2)
	await _wait(player, 0.2)
	ok = Check._check(GameState.hp == GameState.max_hp and trap.element_state == "off", "disabled Needler is safe") and ok
	await _remove(player, trap)
	return ok

static func _poison(player: Node3D) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN
	var trap := _spawn(player, "poison_trap", "off") as PoisonTrap
	await _wait(player, 0.2)
	var ok := Check._check(not player.has_status_effects() and trap._spike_materials.size() > 0, "off poison machine has its own materials and no exposure")
	player._recovery_left = 1.0
	trap.set_state("on")
	await _wait(player, 0.2)
	ok = Check._check(not player.has_status_effects(), "gas exposure respects recovery immunity") and ok
	player._recovery_left = 0.0
	await _wait(player, 0.2)
	ok = Check._check(player._ailments.effects.has("poison") and GameState.hp == GameState.max_hp - NeedleTrap.DAMAGE_AMOUNT and is_instance_valid(player._ailments._poison_effect), "poison needles deal normal contact damage and show poison effect") and ok
	await _wait(player, NeedleTrap.EXTENDED_TIME)
	player.clear_status_effects()
	await _wait(player, 0.2)
	ok = Check._check(not trap.spikes_extended and not player.has_status_effects(), "retracted poison needles cannot apply poison") and ok
	await _wait(player, NeedleTrap.RETRACTED_TIME)
	ok = Check._check(trap.spikes_extended and player._ailments.effects.has("poison"), "next needle extension applies poison to overlapping player") and ok
	trap.set_state("off")
	player.set_physics_process(true)
	await _wait(player, 5.2)
	player.set_physics_process(false)
	ok = Check._check(GameState.hp == GameState.max_hp - 2 * NeedleTrap.DAMAGE_AMOUNT - maxi(1, int(GameState.max_hp * 0.05)), "poison ticks after five real gameplay seconds and persists after leaving gas") and ok
	Inventory.add_item("sol_atomizer", 1)
	Inventory.use_item("sol_atomizer")
	ok = Check._check(not player._ailments.effects.has("poison") and not is_instance_valid(player._ailments._poison_effect), "real Sol Atomizer cures poison and removes effect") and ok
	player.global_position = ORIGIN
	trap.set_state("on")
	await _wait(player, 0.2)
	trap.set_state("off")
	player._ailments.tick(player, 20.0)
	ok = Check._check(not player._ailments.effects.has("poison"), "poison expires at its twenty-second boundary") and ok
	await _remove(player, trap)
	Floor._reset(player)
	return ok

static func _edges(player: Node3D) -> bool:
	Floor._reset(player)
	player.global_position = ORIGIN + Vector3(0, 0, 10)
	var gun := _spawn(player, "gun_trap") as GunTrap
	await _wait(player, 0.8)
	var ok := Check._check(gun.shots_fired == 1, "gun has released a shot before mid-flight disable")
	gun.set_state("off")
	await _wait(player, 1.0)
	ok = Check._check(GameState.hp == GameState.max_hp and gun.get_children().filter(func(n): return n is EnemyProjectile).is_empty(), "off gun removes in-flight shots without damage") and ok
	await _remove(player, gun)
	player.global_position = ORIGIN + Vector3(0, 0, 3.8)
	var wall := _wall(player)
	await _wait(player, 0.1)
	var bomb := _spawn(player, "burn_trap") as BombTrap
	bomb.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 0.8)
	ok = Check._check(bomb.detonations == 1 and GameState.hp == GameState.max_hp, "bomb blast cannot cross a wall") and ok
	await _remove(player, bomb)
	var needler := _spawn(player, "needler_trap") as NeedlerTrap
	needler.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 1.5)
	ok = Check._check(needler.sweeps == 1 and GameState.hp == GameState.max_hp, "Needler attack sweep cannot cross a wall") and ok
	await _remove(player, needler)
	await _remove(player, wall)
	player.global_position = ORIGIN + Vector3(0, 0, 12.1)
	needler = _spawn(player, "needler_trap") as NeedlerTrap
	needler.hurtbox.take_hit(1, Vector3.ZERO)
	await _wait(player, 1.5)
	ok = Check._check(needler.sweeps == 1 and GameState.hp == GameState.max_hp, "Needler does not reach beyond its source radius") and ok
	await _remove(player, needler)
	player.global_position = ORIGIN + Vector3(0, 0, 2)
	needler = _spawn(player, "needler_trap") as NeedlerTrap
	await _wait(player, 0.75) # Start the dodge at impact, after the warning.
	player.transition_to(player.PlayerState.DODGING)
	player.dodge_timer = 0.0
	await _wait(player, 0.75)
	ok = Check._check(needler.sweeps == 1 and GameState.hp == GameState.max_hp, "dodge rejects a complete Needler sweep") and ok
	await _remove(player, needler)
	Floor._reset(player)
	return ok

static func _pending_snapshot(field: Node) -> Array:
	var spawner: CellObjectSpawner = field._cell_spawner
	spawner._spawn_placed_trap(ORIGIN, "gun_trap", "on", {"model": "o0c_gun02", "rotation": 90.0, "timer": 10.0})
	spawner._spawn_placed_trap(ORIGIN + Vector3(3, 0, 0), "burn_trap", "warning", {"timer": 0.6})
	spawner._spawn_placed_trap(ORIGIN + Vector3(6, 0, 0), "needler_trap", "active", {"timer": 0.3})
	spawner._spawn_placed_trap(ORIGIN + Vector3(9, 0, 0), "burn_trap", "spent")
	for node in field._map_root.get_children():
		if node is FieldHazard: node.set_process(false)
	spawner._save_cell_state()
	var saved: Dictionary = field._cell_states[str(field._current_cell.pos)].duplicate(true)
	var records: Array = saved.objects.filter(func(o): return o.type in ["gun_trap", "burn_trap", "needler_trap"])
	for node in field._map_root.get_children():
		if node is FieldHazard: node.queue_free()
	return records

static func _persistence(player: Node3D) -> bool:
	# The shared floor regression exercises the real save/restore dispatcher.
	var ok := await Floor._persistence(player, ORIGIN)
	var field := player.get_tree().current_scene
	var spawner: CellObjectSpawner = field._cell_spawner
	var records := _pending_snapshot(field)
	await _wait(player, 0.05)
	spawner._restore_cell_objects({"objects": records, "drops": []})
	var restored_gun: GunTrap
	var restored_bomb: BombTrap
	var restored_needler: NeedlerTrap
	var spent_bomb: BombTrap
	for node in field._map_root.get_children():
		if node is GunTrap: restored_gun = node
		elif node is NeedlerTrap: restored_needler = node
		elif node is BombTrap:
			if node.element_state == "spent": spent_bomb = node
			else: restored_bomb = node
	ok = _restored_state_checks(restored_gun, restored_needler, restored_bomb, spent_bomb) and ok
	await _wait(player, 0.8)
	ok = Check._check(restored_bomb != null and restored_bomb.detonations == 1 and spent_bomb != null and spent_bomb.detonations == 0, "pending bomb detonates once after restore; spent bomb stays inert") and ok
	for node in field._map_root.get_children():
		if node is FieldHazard: node.queue_free()
	await _wait(player, 0.05)
	return ok

static func _restored_state_checks(restored_gun: GunTrap, restored_needler: NeedlerTrap, restored_bomb: BombTrap, spent_bomb: BombTrap) -> bool:
	var ok := Check._check(restored_gun != null and restored_gun.model_path.ends_with("gun02.glb") and is_equal_approx(restored_gun.rotation.y, PI/2) and is_equal_approx(restored_gun.timer, 10.0), "real room restore retains gun variant, authored yaw and cooldown")
	ok = Check._check(restored_needler != null and restored_needler.element_state == "cooldown" and restored_needler.timer == NeedlerTrap.COOLDOWN, "room restore converts an active Needler wave to cooldown") and ok
	ok = Check._check(restored_bomb != null and restored_bomb.element_state == "warning" and spent_bomb != null and not spent_bomb.model.visible, "room restore retains pending and spent bombs separately") and ok
	return ok

static func _visuals(player: Node3D) -> void:
	var destination := OS.get_environment("PSZ_GAMEPLAY_CAPTURE_DIR")
	if destination.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(destination)
	player.global_position = ORIGIN + Vector3(0, 0, -20)
	var camera := Camera3D.new()
	player.get_tree().current_scene.add_child(camera)
	camera.global_position = ORIGIN + Vector3(0, 8, 10)
	camera.look_at(ORIGIN)
	camera.make_current()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color = Color(0.12, 0.14, 0.18)
	floor_mesh.material_override = floor_material
	player.get_tree().current_scene.add_child(floor_mesh)
	floor_mesh.global_position = ORIGIN - Vector3.UP * 0.05
	for kind in ["gun_trap", "burn_trap", "needler_trap", "poison_trap"]:
		var trap := _spawn(player, kind)
		trap.set_process(false)
		if trap is NeedlerTrap:
			trap.set_state("active")
			trap._show_sweep(1.0)
			print("[trap-art] Needler surfaces=%d radius=%s" % [trap._sweep_materials.size(), str(trap._sweep_materials.map(func(m): return m.get_shader_parameter("reveal_radius")))])
			camera.global_position = ORIGIN + Vector3(0, 16, 22)
			camera.look_at(ORIGIN + Vector3(0, 0, 4))
		else:
			camera.global_position = ORIGIN + (Vector3(0, 8, 10) if kind == "poison_trap" else Vector3(2, 3, 4))
			camera.look_at(ORIGIN + Vector3.UP * 0.4)
		await _wait(player, 0.1)
		await RenderingServer.frame_post_draw
		player.get_viewport().get_texture().get_image().save_png(destination.path_join(kind + ".png"))
		await player.get_tree().process_frame
		await _remove(player, trap)
	floor_mesh.queue_free()
	camera.queue_free()
