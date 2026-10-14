class_name DescriptorBoss extends EnemyBase
## Shared descriptor timing, combat windows and encounter lifecycle.
## ROM timing/stages are data; attack selection and delivery remain partial ports.

signal action_started(action_id: int)

static var _catalogs: Dictionary = {}
static var _reyburn_sequences: Array = []
var catalog: Dictionary = {}
var clock := BossActionClock.new()
var action_id := -1
var encounter_max_hp := 1
var _sequence: Array = []
var _owned_shots: Array[Node3D] = []
var _window_hits: Dictionary = {}
var _pose := ""
var _dying := false
var _tick_fraction := 0.0
var _action_serial := 0
var hit_part := 0
var hit_source: Node3D
var _hurt_parts: Array[Hurtbox] = []

func _ready() -> void:
	super._ready()
	add_to_group("bosses")
	encounter_max_hp = current_hp
	if _catalogs.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/boss_behavior_contract.json"))
		_catalogs = data.catalogs
		_reyburn_sequences = data.reyburn_layout.sequences
	catalog = _catalogs.get(enemy_data.model_id, {})
	clock.stage_changed.connect(_stage_changed)
	clock.event_fired.connect(_descriptor_event)
	clock.cycle_finished.connect(_cycle_finished)
	clock.finished.connect(_action_finished)
	if animation_player:
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func _setup_sound_playback() -> void:
	# Descriptor sound events below are authoritative; no duplicate method tracks.
	pass

func _uses_generic_hurt_reaction() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if not is_alive and not _dying or dormant:
		return
	if is_alive:
		_process_status_effects(delta)
		if _is_immobilized:
			velocity = Vector3.ZERO
			return
	if not is_instance_valid(target): target = _find_player()
	_tick_fraction += delta * 30.0
	while _tick_fraction >= 1.0:
		_tick_fraction -= 1.0
		var serial := _action_serial
		if is_alive: _controller_tick()
		# A controller entry starts at frame zero, not frame one of this tick.
		if serial == _action_serial: clock.advance(1.0 / 30.0)
		_sync_pose()
		if is_alive: _after_action_tick()

func _controller_tick() -> void:
	pass

func _after_action_tick() -> void:
	pass

func _set_hit_context(part: int, source: Node3D) -> void:
	hit_part = part
	hit_source = source

func _register_part(parent: Node3D, radius: float, part: int, offset := Vector3.ZERO) -> Hurtbox:
	var hb := Hurtbox.new()
	hb.owner_node = self
	hb.part_id = part
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = offset
	hb.add_child(shape)
	parent.add_child(hb)
	_hurt_parts.append(hb)
	return hb

func play_action(id: int, limits: Dictionary = {}) -> void:
	_action_serial += 1
	action_id = id
	_set_exposure(_accepts_damage())
	_window_hits.clear()
	clock.begin(catalog.actions[id], limits)
	action_started.emit(id)

func play_sequence(actions: Array) -> void:
	_sequence = actions.duplicate(true)
	_next_action()

func _next_action() -> void:
	if _sequence.is_empty():
		_sequence_finished()
		return
	var entry: Variant = _sequence.pop_front()
	if entry is Dictionary:
		play_action(int(entry.id), entry.get("loops", {}))
	else:
		play_action(int(entry))

func _action_finished() -> void:
	if _dying:
		queue_free()
	elif is_alive:
		_next_action()

func _sequence_finished() -> void:
	pass # Per-boss scheduler.

func _cycle_finished(_stage: int, _cycle: int) -> void:
	pass # Controller callbacks, separate from animation event notifications.

func _stage_changed(descriptor: Dictionary) -> void:
	if not animation_player:
		return
	var clip := str(descriptor.member).get_basename()
	_pose = _find_animation(clip)
	if _pose.is_empty():
		push_error("Missing boss clip: " + clip)
		return
	animation_player.play(_pose)
	_sync_pose()

func _sync_pose() -> void:
	if animation_player and not _pose.is_empty():
		animation_player.seek(float(clock.frame_q12) / 4096.0 / 60.0, true)

func _descriptor_event(record: Dictionary) -> void:
	var event: Dictionary = record.event
	if not is_alive and int(event.type_class) != 2:
		return
	var kind := str(record.kind)
	match int(event.type_class):
		0:
			_combat_event(record)
		2:
			if kind == "point":
				var sound: Dictionary = EnemySoundPlayback.catalogue().get("sounds", {}).get(event.get("sound", {}).get("symbol", ""), {})
				if not sound.is_empty() and int(sound.get("loop_begin", -1)) < 0:
					SfxManager.play_at(str(sound.path), global_position)
		4:
			_boss_notification(int(event.notification), kind)

func _boss_notification(_id: int, _kind: String) -> void:
	pass

func _combat_event(record: Dictionary) -> void:
	var key := int(record.index)
	if record.kind == "window_end":
		_window_hits.erase(key)
		return
	if _window_hits.has(key) or not is_instance_valid(target):
		return
	var event: Dictionary = record.event
	var shape: Dictionary = catalog.shapes[int(event.shape_index)]
	var offset: Array = event.get("offset_xz_raw", [0, 0])
	_sync_pose()
	var anchor := _event_anchor(event)
	var origin := anchor * Vector3(float(offset[0]) / 4096.0, 0, float(offset[1]) / 4096.0)
	var local := global_basis.inverse() * (target.global_position - origin)
	# Initial delivery: planar circles; kind 1 uses an explicitly approximate box.
	# Joint attachment and the original kind-1 transform still need a port.
	var inside := false
	if int(shape.kind_raw) == 0:
		inside = Vector2(local.x, local.z).length() <= float(shape.radius_raw) / 4096.0 + 0.5
	else:
		inside = absf(local.x) <= float(shape.distances_raw[1]) / 4096.0 and absf(local.z) <= float(shape.distances_raw[0]) / 4096.0
	if inside:
		_window_hits[key] = true # A dodge consumes contact; no repeated attempts.
		_damage_target()

func _damage_target() -> void:
	if is_alive and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(_attack_damage({}))

func _aim_at_target() -> void:
	if is_instance_valid(target):
		var direction := target.global_position - global_position
		direction.y = 0
		if direction.length_squared() > 0.01:
			rotation.y = atan2(direction.x, direction.z)

func _shoot(angle: float = 0.0, visual: String = "orb", tint := Color(0.65,0.12,0.85)) -> void:
	if not is_alive or not is_instance_valid(target):
		return
	var shot := EnemyProjectile.new()
	shot.target = target
	shot.damage = _attack_damage({})
	shot.max_range = 60.0
	shot.color = tint
	shot.visual = visual
	var origin := _shot_origin()
	var aim := _shot_target() - origin
	shot.dir = aim.normalized().rotated(Vector3.UP, angle)
	get_parent().add_child(shot)
	shot.global_position = origin
	_owned_shots = _owned_shots.filter(is_instance_valid)
	_owned_shots.append(shot)

func _shot_origin() -> Vector3:
	return global_position + Vector3.UP

func _shot_target() -> Vector3:
	return Vector3(target.global_position.x, global_position.y + 1.0, target.global_position.z)

func _clear_deliveries() -> void:
	clock.cancel()
	_window_hits.clear()
	for shot in _owned_shots:
		if is_instance_valid(shot):
			shot.set_physics_process(false)
			shot.queue_free()
	_owned_shots.clear()

func _death_action() -> int:
	return -1

func _die() -> void:
	if not is_alive:
		return
	_status_effects.clear()
	_update_immobilized()
	_update_status_visuals()
	_clear_deliveries()
	is_alive = false
	_dying = true
	current_state = EnemyState.DEAD
	is_attacking = false
	collision_layer = 0
	collision_mask = 0
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
	for part in _hurt_parts: part.set_deferred("monitorable", false)
	_sequence.clear()
	_emit_defeat()
	_notify_leader_loss()
	var id := _death_action()
	if id >= 0:
		play_action(id)
	else:
		queue_free()

func _exit_tree() -> void:
	_clear_deliveries()


func _set_exposure(exposed: bool) -> void:
	# Target scanners use the enemies group. Protected bodies must not steal
	# melee/projectile/companion targeting from the independent Mother Pieces.
	if exposed and is_alive:
		add_to_group("enemies")
	else:
		remove_from_group("enemies")
	if hurtbox:
		hurtbox.set_deferred("monitorable", exposed and is_alive)

func _event_anchor(event: Dictionary) -> Transform3D:
	# Shrine encounter adapters retain their entity-space combat origins.
	if _hurt_parts.is_empty(): return global_transform
	if int(event.get("coordinate_mode", 0)) == 2:
		var skeleton := NodeUtils.first_of_type(model, "Skeleton3D") as Skeleton3D if model else null
		var joint := int(event.get("joint_index", -1))
		if skeleton and joint >= 0 and joint < skeleton.get_bone_count():
			return skeleton.global_transform * skeleton.get_bone_global_pose(joint)
	return global_transform

func _bearing() -> float:
	if not is_instance_valid(target): return 0.0
	var direction := target.global_position - global_position
	return wrapf(atan2(direction.x,direction.z) - rotation.y,-PI,PI)

func _distance() -> float:
	if not is_instance_valid(target): return INF
	var direction := target.global_position - global_position
	return Vector2(direction.x,direction.z).length()

func _turn_step(raw: int = 0x222) -> bool:
	var bearing := _bearing()
	var step := TAU * raw / 65536.0
	rotation.y += clampf(bearing,-step,step)
	return absf(bearing) <= step

func _move_forward(speed: float) -> void:
	var motion := global_basis.z * speed / 30.0
	if not _can_move_to(motion.normalized()): return
	move_and_collide(motion)

func hurtbox_in_cone(origin: Vector3, yaw: float, config: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var parts: Array[Hurtbox] = _hurt_parts.duplicate()
	# Shrine bosses use the base capsule or their own receiver, rather than
	# the registered Reyburn/Octo parts. Keep them targetable after integration.
	if parts.is_empty() and is_instance_valid(hurtbox): parts.append(hurtbox)
	for part in parts:
		if not is_instance_valid(part) or not part.monitorable or not part.is_visible_in_tree(): continue
		var shape := part.get_child(0) as CollisionShape3D
		var radius := float(shape.shape.get("radius"))
		var distance := ConeTargeting.distance_in_cone(origin,yaw,
			float(config.get("hit_h_dist",2.4)),float(config.get("hit_v_dist",0.5)),
			float(config.get("hit_h_angle_deg",30.0)),float(config.get("hit_v_angle_deg",40.0)),
			shape.global_position,radius)
		if distance >= 0.0 and (best.is_empty() or distance < float(best.dist)):
			best = {"hurtbox":part,"dist":distance}
	return best

func _emit_defeat() -> void:
	died.emit(self)
