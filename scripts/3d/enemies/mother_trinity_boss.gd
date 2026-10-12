class_name MotherTrinityBoss extends DescriptorBoss
## ov31 request/action chains and body exposure event; placeholder piece tactics.

var phase_flags := 0
var pieces: Array[MotherPiece] = []
var piece_count := 3
var pending_request := 0
var _idle_left := 0.0
var _idle := false

func _ready() -> void:
	super._ready()
	_spawn_pieces.call_deferred() # Field places the boss after add_child/_ready.
	_enter_idle()

func _spawn_pieces() -> void:
	if not is_alive:
		return
	for index in 3:
		var piece := MotherPiece.new()
		piece.piece_index = index
		piece.enemy_data = enemy_data.duplicate()
		piece.enemy_data.model_id = ""
		piece.enemy_data.is_boss = false
		piece.enemy_data.id = "mother_piece"
		piece.enemy_data.name = "Mother Piece"
		piece.enemy_data.hp_base = maxi(1, roundi(float(encounter_max_hp) * 1600.0 / 3500.0))
		piece.enemy_data.attack_base = enemy_data.attack_base
		piece.enemy_data.collision_radius = 1.1
		piece.enemy_data.collision_height = 2.5
		piece.enemy_data.evasion_base = enemy_data.evasion_base
		piece.enemy_data.defense_base = enemy_data.defense_base
		piece.position = Vector3(float(index - 1) * 6.0, 0, 8.0)
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
	_idle_left = float(40 if phase_flags & 2 else 900 + _rng.randi_range(0,300)) / 30.0
	play_action(1 if phase_flags & 2 else 0, {0:-1})

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_alive or not _idle:
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_idle = false
		_aim_at_target()
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
		_set_exposure(true)
	elif action_id == 8 and id == 10:
		_shoot(0.0, "laser")

func _death_action() -> int:
	return 5

func _die() -> void:
	if not is_alive:
		return
	for piece in pieces:
		if is_instance_valid(piece):
			piece.is_alive = false
			piece.queue_free()
	pieces.clear()
	super._die()
