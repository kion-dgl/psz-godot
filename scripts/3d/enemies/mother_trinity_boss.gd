class_name MotherTrinityBoss extends DescriptorBoss
## Descriptor body chains plus an authored board encounter; see mother-trinity-reference.md.

## Authored fit to s07z_na1: root in the north cutout, facing the platform (+Z).
## Keep the full-size rig and rear cables aligned; never turn the body to aim.
const ARENA_ANCHOR := Vector3(0, 0, -10)

var board := MotherBoard.new()
var arena: MotherArena
var _wave_pending := false
var _skeleton: Skeleton3D
var phase_flags := 0
var pieces: Array[MotherPiece] = []
var piece_count := 3
var pending_request := 0
var _idle_left := 0.0
var _idle := false

func _ready() -> void:
	super._ready()
	_setup_arena.call_deferred()
	_spawn_pieces.call_deferred() # Field places the boss after add_child/_ready.
	_skeleton = NodeUtils.first_of_type(model, "Skeleton3D") as Skeleton3D
	_enter_idle()

func _setup_arena() -> void:
	arena = MotherArena.new()
	arena.body = model
	add_child(arena)

func _spawn_pieces() -> void:
	if not is_alive:
		return
	for index in 3:
		var piece := MotherPiece.new()
		piece.piece_index = index
		piece.board = board
		piece.board_root = self
		board.claim(index, Vector2i(index + 1, 1))
		var source := EnemyData.new()
		source.id = "mother_piece"
		source.name = "Mother Piece"
		source.collision_radius = 1.1
		source.collision_height = 2.5
		source.exp_reward = 0
		var difficulty := str(SessionManager.get_session().get("difficulty", "normal"))
		piece.enemy_level = enemy_level
		piece.enemy_data = preload("res://scripts/utils/enemy_progression.gd").scaled(
			source, enemy_level, difficulty, _catalogs.boss_mother_piece.stats)
		piece.position = MotherBoard.center(Vector2i(index + 1, 1))
		pieces.append(piece)
		piece.died.connect(_piece_died)
		add_child(piece)

func _piece_died(_piece: EnemyBase) -> void:
	if not is_alive:
		return
	var before := piece_count
	piece_count -= 1
	var request := BossPhaseRules.trinity_piece_request(before, piece_count, phase_flags)
	if request != 0:
		pending_request = maxi(pending_request, request)
	if _idle:
		_sequence_finished()

func _accepts_damage() -> bool:
	return bool(phase_flags & 2)

func _enter_idle() -> void:
	_idle = true
	_idle_left = float(40 if phase_flags & 2 else 300 + _rng.randi_range(0,60)) / 30.0
	play_action(1 if phase_flags & 2 else 0, {0:-1})

func _physics_process(delta: float) -> void:
	if is_instance_valid(arena):
		arena.advance(delta)
	super._physics_process(delta)
	if is_alive and _wave_pending:
		_try_release_wave()
	if not is_alive or not _idle:
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_idle = false
		if not phase_flags & 2:
			play_sequence([6])
		elif is_instance_valid(target) and global_position.distance_to(target.global_position) < 16.0:
			var actions: Array = [9]
			for repeat in _rng.randi_range(0,2):
				actions.append(10)
			actions.append_array([11,8])
			play_sequence(actions)
		else:
			play_sequence([7,8])

func _sequence_finished() -> void:
	if not is_alive:
		return
	_idle = false
	if pending_request == 4:
		pending_request = 0
		phase_flags |= 1
		_wave_pending = false
		for piece in pieces:
			if is_instance_valid(piece) and piece.is_alive:
				piece.hold_for_entry()
		if is_instance_valid(arena):
			arena.begin_entry()
		play_sequence([3])
	elif pending_request == 3:
		pending_request = 0
		play_sequence([2])
	else:
		_enter_idle()

func _boss_notification(id: int, kind: String) -> void:
	if kind != "point":
		return
	if action_id == 3 and id == 0:
		phase_flags |= 2
		if is_instance_valid(arena):
			arena.break_cover()
		for piece in pieces:
			if is_instance_valid(piece) and piece.is_alive:
				piece.resume_board()
		_set_exposure(true)
	elif action_id == 6 and id == 2:
		_wave_pending = true
		for piece in pieces:
			if is_instance_valid(piece) and piece.is_alive:
				piece.request_wave()
	elif action_id == 8 and id == 10:
		_shoot(0.0, "laser")

func _try_release_wave() -> void:
	var living := pieces.filter(func(piece): return is_instance_valid(piece) and piece.is_alive)
	if not living.all(func(piece): return piece.wave_ready()):
		return
	var budget: Dictionary = {}
	for piece in living:
		piece.release_wave(budget)
	_wave_pending = false

func _death_action() -> int:
	return 5

func _die() -> void:
	if not is_alive:
		return
	for piece in pieces:
		if is_instance_valid(piece):
			piece.clear_deliveries()
			piece.is_alive = false
			piece.queue_free()
	pieces.clear()
	super._die()


func _aim_at_target() -> void:
	pass # The body is anchored to the arena; individual attacks aim independently.

func _sync_pose() -> void:
	super._sync_pose()
	if is_instance_valid(_skeleton) and is_instance_valid(hurtbox):
		_skeleton.force_update_all_bone_transforms()
		# Follow the lowered head into the platform for the punish window instead
		# of leaving the damage receiver inside the broken edge at the body root.
		hurtbox.global_position = _joint_position("head")

func _setup_hurtbox() -> void:
	super._setup_hurtbox()
	var shape := hurtbox.get_child(0) as CollisionShape3D
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	shape.shape = sphere
	shape.position = Vector3.ZERO

func _joint_position(bone_name: String) -> Vector3:
	if is_instance_valid(_skeleton):
		var index := _skeleton.find_bone(bone_name)
		if index >= 0:
			return _skeleton.to_global(_skeleton.get_bone_global_pose(index).origin)
	return global_position + Vector3.UP

func _shot_origin() -> Vector3:
	# Aim independently of the rig/cables. Sample the notification's pose.
	_sync_pose()
	return _joint_position("head")

func _shot_target() -> Vector3:
	return target.global_position + Vector3.UP
