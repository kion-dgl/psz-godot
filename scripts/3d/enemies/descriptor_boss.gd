class_name DescriptorBoss extends EnemyBase
## Shared action/event and encounter lifecycle for the Dark Shrine test encounters.
## ROM timing/stages are data; attack selection and delivery remain partial ports.

signal action_started(action_id: int)

static var _catalogs: Dictionary = {}
var catalog: Dictionary = {}
var clock := BossActionClock.new()
var action_id := -1
var encounter_max_hp := 1
var _sequence: Array = []
var _owned_shots: Array[Node3D] = []
var _window_hits: Dictionary = {}
var _pose := ""
var _dying := false

func _ready() -> void:
	super._ready()
	add_to_group("bosses")
	encounter_max_hp = current_hp
	if _catalogs.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/boss_behavior_contract.json"))
		_catalogs = data.catalogs
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
	if _dying:
		clock.advance(delta)
		_sync_pose()
		return
	if not is_alive or dormant:
		return
	if not is_instance_valid(target):
		target = _find_player()
	clock.advance(delta)
	_sync_pose()

func play_action(id: int, limits: Dictionary = {}) -> void:
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
	var origin := to_global(Vector3(float(offset[0]) / 4096.0, 0, float(offset[1]) / 4096.0))
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

func _shoot(angle: float = 0.0, visual: String = "orb") -> void:
	if not is_alive or not is_instance_valid(target):
		return
	var shot := EnemyProjectile.new()
	shot.target = target
	shot.damage = _attack_damage({})
	shot.max_range = 60.0
	shot.color = Color(0.65, 0.12, 0.85)
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
	_clear_deliveries()
	is_alive = false
	_dying = true
	current_state = EnemyState.DEAD
	is_attacking = false
	collision_layer = 0
	collision_mask = 0
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
	_sequence.clear()
	died.emit(self)
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
