class_name DarkFalzBoss extends DescriptorBoss
## Moving encounter informed by Kion's observations; timings/spatial rules authored.
## Imported descriptor clips remain authoritative for animation event timing.
const WALK_SPEED := 3.0
const SWIM_SPEED := 6.0
const VOLLEY_INTERVAL := 14.0
enum Mode { INTRO, HUNT, STRIKE, BURST, RETURN, REACTION, SINK }
var mode := Mode.INTRO
var damage_rules := BossPhaseRules.FalzDamage.new()
var pending_reaction := 0
var submerged := false
var orbit: FalzOrbit
var tail: FalzTail
var _hunt_left := 3.0
var _volley_left := VOLLEY_INTERVAL
var _tail_left := 6.0
var _burst_released := false
var _burst_animation_done := false
var _front_hit := false
var _strike_elapsed := 0.0
var _turn_sign := 1.0
var _body_height := 0.0

func _setup_model() -> void:
	super._setup_model()
	if not model:
		return
	# This arena has no useful model lighting. Preserve the DS unlit palette
	# instead of inheriting the field-enemy relighting pass's black silhouette.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(surface, material)

func _ready() -> void:
	super._ready()
	orbit = FalzOrbit.new()
	add_child(orbit)
	orbit.global_position = global_position
	_body_height = model.position.y if model else 0.0
	_turn_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	play_sequence([0, 1])

func _after_damage_applied(amount: int) -> void:
	var request := damage_rules.hit(current_hp, encounter_max_hp, -amount)
	if current_hp > 0 and request != 0:
		pending_reaction = request

func _accepts_damage() -> bool:
	return true # The persistent low-health swim must remain finishable.

func _sequence_finished() -> void:
	if not is_alive:
		return
	if mode == Mode.BURST:
		_burst_animation_done = true
		return # Keep the balls hidden until the last volley delivery expires.
	if pending_reaction != 0:
		var reaction := pending_reaction
		pending_reaction = 0
		mode = Mode.REACTION
		play_sequence([10 if reaction == 2 else 11])
		return
	if damage_rules.flags & 4 and not submerged:
		submerged = true
		mode = Mode.SINK
		play_sequence([3])
		return
	_begin_hunt()

func _action_finished() -> void:
	if is_alive and mode == Mode.HUNT:
		# The swim descriptor is finite; repeat it without resetting hunt timers.
		play_action(4 if submerged else 2, {0:-1})
	else:
		super._action_finished()

func _begin_hunt() -> void:
	mode = Mode.HUNT
	_hunt_left = 1.8 if submerged else 3.0
	_front_hit = false
	orbit.retracted = false
	play_action(4 if submerged else 2, {0:-1})

func _begin_burst() -> void:
	mode = Mode.BURST
	velocity = Vector3.ZERO
	orbit.retracted = true
	_burst_released = false
	_burst_animation_done = false
	play_sequence([{"id":17,"loops":{1:2}},18])

func _physics_process(delta: float) -> void:
	if is_alive and not dormant:
		if not is_instance_valid(target): target = _find_player()
		_step_encounter(delta)
		orbit.advance(delta, self)
		if model:
			model.position.y = move_toward(model.position.y, _body_height - (2.5 if submerged else 0.0), delta * 2.5)
	super._physics_process(delta)

func _step_encounter(delta: float) -> void:
	_owned_shots = _owned_shots.filter(func(shot): return is_instance_valid(shot) and not shot.is_queued_for_deletion())
	if mode == Mode.BURST:
		if _burst_released and _burst_animation_done and _owned_shots.is_empty():
			mode = Mode.RETURN
			orbit.retracted = false
			_volley_left = VOLLEY_INTERVAL
			play_sequence([16])
		return
	if mode == Mode.STRIKE and submerged:
		_strike_elapsed += delta
		if _strike_elapsed >= 0.45: _front_strike()
	if mode != Mode.HUNT:
		return
	_volley_left -= delta
	_tail_left -= delta
	_hunt_left -= delta
	if _tail_left <= 0.0 and not is_instance_valid(tail):
		_spawn_tail()
		_tail_left = 5.0 if submerged else 8.0
	if pending_reaction != 0:
		_sequence_finished()
	elif _volley_left <= 0.0:
		_begin_burst()
	elif _hunt_left <= 0.0 and is_instance_valid(target):
		_aim_at_target()
		mode = Mode.STRIKE
		velocity = Vector3.ZERO
		_front_hit = false
		_strike_elapsed = 0.0
		play_sequence([4 if submerged else 14])
	else:
		_walk(delta)

func _walk(delta: float) -> void:
	if not is_instance_valid(target): return
	var offset := target.global_position - global_position
	offset.y = 0
	if offset.length_squared() < 0.01: return
	var toward := offset.normalized()
	# Circle at close range instead of stopping or pinning the player in place.
	var direction := toward if offset.length() > 6.0 else toward.rotated(Vector3.UP, _turn_sign * PI * 0.5)
	rotation.y = lerp_angle(rotation.y, atan2(toward.x, toward.z), minf(delta * 3.0, 1.0))
	if not _can_move_to(direction):
		_turn_sign *= -1.0
		direction = toward.rotated(Vector3.UP, _turn_sign * PI * 0.5)
	if _can_move_to(direction):
		velocity = direction * (SWIM_SPEED if submerged else WALK_SPEED)
		move_and_slide()
	else:
		velocity = Vector3.ZERO

static func in_front(local: Vector3) -> bool:
	return absf(local.y) < 3.0 and local.z >= 0.0 and local.z <= 9.0 and absf(local.x) <= 3.5

func _front_strike() -> void:
	if not _front_hit and is_instance_valid(target) and in_front(to_local(target.global_position)):
		_front_hit = true
		_damage_target()

func _combat_event(_record: Dictionary) -> void:
	# Authored frontal delivery replaces provisional centered descriptor boxes.
	# Swim action 4 must not deal continuous untimed body contact damage.
	pass

func _boss_notification(id: int, kind: String) -> void:
	if kind != "point": return
	if mode == Mode.STRIKE and ((action_id == 14 and id == 13) or (action_id == 8 and id == 9)):
		_front_strike()
	elif mode == Mode.BURST and action_id == 18 and id == 2 and not _burst_released:
		_burst_released = true
		var budget := {}
		for index in 12:
			_shoot(TAU * float(index) / 12.0)
			var shot := _owned_shots.back() as EnemyProjectile
			shot.max_range = 32.0
			shot.speed = 8.0
			shot.hit_budget = budget

func _spawn_tail() -> void:
	if not is_instance_valid(target) or not _has_floor_at(target.global_position): return
	tail = FalzTail.new()
	tail.target = target
	tail.damage = _attack_damage({})
	get_parent().add_child(tail)
	tail.global_position = Vector3(target.global_position.x, global_position.y, target.global_position.z)

func _clear_deliveries() -> void:
	super._clear_deliveries()
	if is_instance_valid(tail):
		tail.set_physics_process(false)
		tail.queue_free()
	if is_instance_valid(orbit):
		orbit.hide()

func _death_action() -> int:
	return 22
