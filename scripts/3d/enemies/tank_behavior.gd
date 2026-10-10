extends RefCounted
## User-directed Zaphobos kit. Timings are tuning, not recovered original AI.
var cooldowns: Dictionary = {}
var phase := ""
var phase_time := 0.0
var travel_cooldown := 0.0
var waves := 0

func enabled(enemy: EnemyBase) -> bool:
	return bool(enemy._fsm.get("tank_kit", false))

func tick(enemy: EnemyBase, delta: float) -> void:
	for key in cooldowns: cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	travel_cooldown = maxf(0.0, travel_cooldown - delta)
	if enemy.current_state != EnemyBase.EnemyState.CHASING: phase = ""

func available(definition: Dictionary) -> bool:
	return float(cooldowns.get(definition.get("id", ""), 0.0)) <= 0.0

func begin(enemy: EnemyBase) -> void:
	if not enabled(enemy): return
	cooldowns[enemy._attack_def.id] = float(enemy._attack_def.get("cooldown", 4.0))
	waves = 0

func chase(enemy: EnemyBase, delta: float, distance: float) -> void:
	if not phase.is_empty():
		_travel(enemy, delta, distance)
		return
	if enemy.attack_cooldown_timer <= 0.0 and not enemy._stun_no_attack and enemy._has_attack_in_band(distance, 0.0):
		enemy.current_state = EnemyBase.EnemyState.ATTACKING
		enemy._begin_telegraph()
		return
	if travel_cooldown <= 0.0 and (distance > 10.0 or not enemy._has_attack_in_band(distance, 0.0)):
		phase = "st"
		phase_time = 0.0
		travel_cooldown = 7.0
		enemy._play_animation("run_st", true)
		_travel(enemy, 0.0, distance)
		return
	var radial := enemy._radial_to_target()
	var direction := radial if distance > 8.0 else -radial if distance < 3.0 else Vector3.ZERO
	enemy._apply_move(direction, 0.9, radial, "wat")

func _travel(enemy: EnemyBase, delta: float, distance: float) -> void:
	phase_time += delta
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if phase == "lp":
		var radial := enemy._radial_to_target()
		var direction := radial if distance > 8.0 else -radial if distance < 5.0 else Vector3(-radial.z, 0, radial.x) * enemy._arc_side
		if phase_time < 1.6 and enemy._can_move_to(direction) and not enemy.test_move(enemy.global_transform, direction * maxf(0.5, 5.5 * delta)):
			enemy._apply_move(direction, 5.5, direction, "run_lp")
			return
		phase = "ed"
		phase_time = 0.0
		enemy._play_animation("run_ed", true)
	elif phase_time >= maxf(enemy._clip_duration("run_" + phase), 0.1):
		phase = "lp" if phase == "st" else ""
		phase_time = 0.0
		enemy._play_animation("run_lp" if phase == "lp" else "wat", true)

func fire_waves(enemy: EnemyBase) -> void:
	if not enemy._attack_def.get("missile_waves", false) or not enemy.is_attacking or not is_instance_valid(enemy.target): return
	while waves < 3 and enemy._attack_pos >= (0.32 + waves * 0.18) * enemy._attack_clip_len:
		for side in [-1.0, 1.0]: _missile(enemy, side)
		waves += 1

func _missile(enemy: EnemyBase, side: float) -> void:
	var missile := preload("res://scripts/3d/enemies/tank_missile.gd").new()
	missile.target = enemy.target
	missile.damage = enemy._attack_damage(enemy._attack_def)
	missile.blast_radius = 0.65
	missile.flight_time = 1.5
	missile.rare = enemy.enemy_data.model_id == "tank_rare"
	var lateral := Vector3(-enemy._attack_facing.z, 0, enemy._attack_facing.x) * side
	missile.from = enemy.global_position + Vector3.UP * 1.5
	missile.to = enemy.target.global_position
	missile.bend = lateral * 2.0
	enemy.get_parent().add_child(missile)
	missile.global_position = missile.from
	var offset := lateral * 0.7
	if ProjectileSweep.environment_fraction(enemy.get_world_3d().direct_space_state, missile.from, offset, 0.22) >= 0.0:
		missile.queue_free()
	else:
		missile.from += offset
		missile.global_position = missile.from

func reset_animation(enemy: EnemyBase) -> void:
	if enemy.animation_player and enabled(enemy): enemy.animation_player.speed_scale = 1.0
