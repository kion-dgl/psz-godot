extends RefCounted
const Check := preload("res://scripts/tools/gameplay_recovery_check.gd")
const Floor := preload("res://scripts/tools/floor_trap_check.gd")

class Rescuer extends Node3D:
	enum PlayerState { IDLE, CUTSCENE }
	var current_state := PlayerState.IDLE

static func run(player: Node3D, origin: Vector3) -> bool:
	Floor._reset(player)
	player.global_position = origin + Vector3(8, 0, 0)
	await Floor._settle(player)
	var trap := BearTrap.new()
	player.get_parent().add_child(trap)
	trap.global_position = origin
	trap.set_process(false) # Advance phase boundaries deterministically after real overlaps.
	await Floor._settle(player)
	var vision := TrapBall.vision_until_msec
	TrapBall.vision_until_msec = 0
	trap._update_visibility()
	var ok := Check._check(trap.model.visible == Inventory.can_use_traps() and not trap.is_alive, "dormant bear follows racial detection and cannot be targeted")
	TrapBall.grant_vision()
	trap._update_visibility()
	ok = Check._check(trap.model.visible and not trap.is_alive and not trap.hurtbox.monitorable, "Trap Vision reveals dormant bear without targeting or hurtbox") and ok
	TrapBall.vision_until_msec = vision
	player.global_position = origin
	await Floor._settle(player)
	ok = Check._check(trap.element_state == "warning" and not trap._is_holding and trap.is_alive, "stepping on bear activates a targetable escape window") and ok
	player.global_position = origin + Vector3(8, 0, 0)
	await Floor._settle(player)
	trap._update_animation(BearTrap.ESCAPE_DURATION)
	trap._update_animation(BearTrap.HOLD_DURATION)
	ok = Check._check(trap.element_state == "spent" and GameState.hp == GameState.max_hp, "escaping before closure avoids capture and explosion damage") and ok
	ok = await _capture_and_rescue(player, origin, trap) and ok
	ok = await _explosion(player, origin, trap) and ok
	await _arm_under_player(player, origin, trap)
	trap.queue_free()
	await Floor._settle(player)
	ok = Check._check(player.current_state == player.PlayerState.IDLE, "removing bear safely releases held player") and ok
	Floor._reset(player)
	return ok

static func _arm_under_player(player: Node3D, origin: Vector3, trap: BearTrap) -> void:
	Floor._reset(player)
	player.global_position = origin + Vector3(8, 0, 0)
	trap.set_state("off")
	await Floor._settle(player)
	player.global_position = origin
	await Floor._settle(player)
	trap._update_animation(BearTrap.ESCAPE_DURATION)

static func _capture_and_rescue(player: Node3D, origin: Vector3, trap: BearTrap) -> bool:
	await _arm_under_player(player, origin, trap)
	var ok := Check._check(trap._is_holding and player.current_state == player.PlayerState.CUTSCENE, "remaining on bear after warning captures player")
	var held_at := player.global_position
	player.set_physics_process(true)
	Input.action_press("move_right")
	await player.get_tree().create_timer(0.2).timeout
	Input.action_release("move_right")
	player.set_physics_process(false)
	ok = Check._check(player.global_position.distance_to(held_at) < 0.1, "captured player cannot move") and ok
	trap.hurtbox.take_hit(1, Vector3.ZERO, 100, "", 0, false, "physical", player)
	ok = Check._check(trap._is_holding, "captured player's earlier projectile cannot disarm their trap") and ok
	var rescuer := Rescuer.new()
	player.get_parent().add_child(rescuer)
	rescuer.add_to_group("player")
	trap.hurtbox.take_hit(1, Vector3.ZERO, 100, "", 0, false, "physical", rescuer)
	ok = Check._check(trap.element_state == "spent" and player.current_state == player.PlayerState.IDLE and GameState.hp == GameState.max_hp, "one hit from free player destroys bear and releases victim without damage") and ok
	rescuer.queue_free()
	return ok

static func _explosion(player: Node3D, origin: Vector3, trap: BearTrap) -> bool:
	await _arm_under_player(player, origin, trap)
	trap._update_animation(BearTrap.HOLD_DURATION - 0.1)
	var ok := Check._check(trap._is_holding and GameState.hp == GameState.max_hp, "bear holds without damage before fuse expires")
	trap._update_animation(0.11)
	ok = Check._check(trap.element_state == "spent" and not trap._is_holding and GameState.hp == GameState.max_hp - BearTrap.DAMAGE_AMOUNT and player.current_state == player.PlayerState.DAMAGED, "bear explodes once, damages victim and preserves stagger") and ok
	trap._update_animation(5.0)
	ok = Check._check(GameState.hp == GameState.max_hp - BearTrap.DAMAGE_AMOUNT, "spent bear cannot explode twice") and ok
	return ok
