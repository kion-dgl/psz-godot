extends RefCounted
## Actual field, imported animations, movement/collisions and delivery lifecycle.
static func run(probe: Node, boss: DarkFalzBoss) -> void:
	var player := boss.target
	probe._check(not boss.submerged and boss.orbit.extension == 1.0, "Falz retry restores normal phase and extended balls")
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	player.global_position = boss.global_position + Vector3(0,0,12)
	boss._begin_hunt()
	var start := boss.global_position
	for tick in 60:
		boss._physics_process(1.0/30.0)
		await probe.get_tree().physics_frame
	probe._check(boss.global_position.distance_to(start) > 1.0, "Falz walks across the real arena floor")
	probe._check(boss._has_floor_at(boss.global_position), "walking Falz stays on arena floor")
	probe._check(boss.orbit.balls.size() == 3, "Falz carries three visible orbiting balls")
	var radius := boss.orbit.radius
	boss.orbit.advance(0.5, boss)
	probe._check(not is_equal_approx(radius, boss.orbit.radius), "orbit reach varies over time")
	await probe._snapshot("falz_walking_orbit")
	_orbit_checks(probe, boss)
	_front_checks(probe, boss)
	_tail_checks(probe, boss)
	await probe._snapshot("falz_tail_warning")
	boss.tail.queue_free()
	await probe.get_tree().process_frame
	boss._begin_hunt()
	boss._volley_left = 0.0
	boss._physics_process(1.0/30.0)
	probe._check(boss.mode == DarkFalzBoss.Mode.BURST, "hunt scheduler enters shadow volley at its interval")
	for tick in 100: boss._physics_process(1.0/30.0)
	probe._check(boss.orbit.extension == 0.0 and boss.orbit.retracted, "balls fully retract before radial release")
	probe._check(boss._owned_shots.size() == 12, "shadow burst releases all-direction twelve-shot volley")
	var shots := boss._owned_shots.duplicate()
	for shot in shots: shot.set_physics_process(false)
	for tick in 180: boss._physics_process(1.0/30.0)
	probe._check(boss.mode == DarkFalzBoss.Mode.BURST and boss.orbit.retracted, "living projectiles hold balls inside shadow after animation ends")
	await probe._snapshot("falz_shadow_volley")
	for shot in shots:
		shot.set_physics_process(true)
		shot._physics_process(5.0)
	await probe.get_tree().process_frame
	boss._physics_process(1.0/30.0)
	probe._check(boss._owned_shots.is_empty() and not boss.orbit.retracted, "balls return only after volley projectiles expire")
	boss.current_hp = boss.encounter_max_hp / 2 - 1
	boss._after_damage_applied(1)
	probe._check(boss.pending_reaction == 2, "Falz half HP reaction queued")
	boss.current_hp = boss.encounter_max_hp / 4 - 1
	boss._after_damage_applied(1)
	probe._check(boss.pending_reaction == 3 and boss.damage_rules.flags == 6, "quarter HP reaction takes priority")
	for tick in 190: boss._physics_process(1.0/30.0)
	probe._check(boss.submerged and boss._accepts_damage(), "low-health Falz submerges and remains damageable")
	probe._check(boss.model.position.y < -2.0, "low-health body visually sinks into shadow")
	boss.global_position = Vector3.ZERO
	boss._begin_hunt()
	player.global_position = Vector3(0,0,10)
	boss._physics_process(1.0/30.0)
	probe._check(boss.velocity.length() > DarkFalzBoss.WALK_SPEED, "submerged Falz moves faster than walking speed")
	for tick in 60: boss._physics_process(1.0/30.0)
	probe._check(boss.mode == DarkFalzBoss.Mode.STRIKE, "finite swim clip cannot starve faster phase frontal attacks")
	await probe._snapshot("falz_submerged")
	player.global_position = Vector3(0,0,4)
	boss._spawn_tail() # Leave a live warning for the shared death-cleanup probe.
	probe._check(is_instance_valid(boss.tail), "live tail remains for death cleanup check")

static func _front_checks(probe: Node, boss: DarkFalzBoss) -> void:
	var old_attack: int = boss.enemy_data.attack_base
	var old_stats: bool = boss.enemy_data.original_attack_stats
	boss.enemy_data.attack_base = 10
	boss.enemy_data.original_attack_stats = false
	var player := boss.target
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0
	GameState.set_hp(GameState.max_hp)
	player.global_position = boss.to_global(Vector3(0,0,-3))
	boss._front_hit = false
	boss._front_strike()
	probe._check(GameState.hp == GameState.max_hp, "Falz frontal strike cannot hit behind him")
	player.global_position = boss.to_global(Vector3(0,0,5))
	boss._front_strike()
	boss._front_strike()
	probe._check(GameState.hp == GameState.max_hp - 10, "Falz frontal strike resolves once inside forward reach")
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.DODGING
	boss._front_hit = false
	boss._front_strike()
	probe._check(GameState.hp == GameState.max_hp, "Falz frontal strike respects dodge")
	boss.enemy_data.attack_base = old_attack
	boss.enemy_data.original_attack_stats = old_stats

static func _tail_checks(probe: Node, boss: DarkFalzBoss) -> void:
	boss._spawn_tail()
	probe._check(is_instance_valid(boss.tail), "tail warning spawns on actual arena floor")
	if not is_instance_valid(boss.tail): return
	boss.tail.set_physics_process(false)
	var point := boss.tail.global_position
	boss.target.global_position += Vector3(4,0,0)
	boss.tail.damage = 10
	boss.tail._physics_process(0.5)
	probe._check(boss.tail.global_position == point and not boss.tail.struck, "tail warning locks location and does not damage early")
	boss.tail._physics_process(0.55)
	probe._check(not boss.tail.struck, "moving out of tail warning avoids strike")
	boss.target.global_position = point
	boss.tail._physics_process(0.05)
	probe._check(boss.tail.struck and GameState.hp == GameState.max_hp, "tail emergence respects dodge immunity")

static func _orbit_checks(probe: Node, boss: DarkFalzBoss) -> void:
	var player := boss.target
	var old_attack: int = boss.enemy_data.attack_base
	var old_stats: bool = boss.enemy_data.original_attack_stats
	boss.enemy_data.attack_base = 10
	boss.enemy_data.original_attack_stats = false
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0.0
	GameState.set_hp(GameState.max_hp)
	boss.orbit.contact_left = 0.0
	player.global_position = boss.orbit.balls[0].global_position - Vector3.UP * 1.2
	boss.orbit.advance(0.001, boss)
	boss.orbit.advance(0.001, boss)
	probe._check(GameState.hp == GameState.max_hp - 10, "orbit contact damages once during shared cooldown")
	GameState.set_hp(GameState.max_hp)
	boss.orbit.contact_left = 0.0
	boss.orbit.retracted = true
	boss.orbit.advance(0.001, boss)
	probe._check(GameState.hp == GameState.max_hp, "retracting balls cannot damage player")
	boss.orbit.retracted = false
	boss.orbit.contact_left = 0.0
	player.current_state = player.PlayerState.DODGING
	boss.orbit.advance(0.001, boss)
	probe._check(GameState.hp == GameState.max_hp, "orbit contact respects dodge immunity")
	boss.enemy_data.attack_base = old_attack
	boss.enemy_data.original_attack_stats = old_stats
