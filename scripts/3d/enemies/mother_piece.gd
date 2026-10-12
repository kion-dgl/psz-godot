class_name MotherPiece extends EnemyBase
## Board-bound piece: reserve, hop, spin, strike/cast, recover. Timing is authored.
enum Step { RECOVER, HOP, SPIN, SYNC }
var piece_index := 0
var board: MotherBoard
var board_root: Node3D
var step := Step.RECOVER
var paused := false
var _left := 1.0
var _jump_time := 0.0
var _jump_start := Vector3.ZERO
var _jump_end := Vector3.ZERO
var _turn := 0
var _wave_requested := false
var _shots: Array[Node3D] = []
var attack_count := 0
var wave_count := 0
var _material: StandardMaterial3D

func _ready() -> void:
	super._ready()
	var start := global_transform
	top_level = true
	global_transform = start
	_left += float(piece_index) * 0.4
	_turn = piece_index

func _setup_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.top_radius = 0.65
	mesh.bottom_radius = 1.1
	mesh.height = 2.5
	body.mesh = mesh
	body.position.y = 1.25
	var material := StandardMaterial3D.new()
	_material = material
	material.albedo_color = [Color(0.85,0.55,0.15),Color(0.65,0.7,0.85),Color(0.7,0.2,0.5)][piece_index]
	body.material_override = material
	model.add_child(body)
	# Asymmetric crest makes the spin readable even with placeholder geometry.
	var crest := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.8, 0.8, 0.6)
	prism.material = material
	crest.mesh = prism
	crest.position = Vector3(0, 1.8, 0.9)
	model.add_child(crest)

func _uses_generic_hurt_reaction() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	if not is_instance_valid(target):
		target = _find_player()
	if step == Step.HOP:
		_jump_time = minf(_jump_time + delta / 0.8, 1.0)
		global_position = _jump_start.lerp(_jump_end, _jump_time) + Vector3.UP * sin(_jump_time * PI) * 2.5
		if _jump_time >= 1.0:
			board.land(piece_index)
			_start_spin()
		return
	if paused:
		return
	_left -= delta
	if step in [Step.SPIN, Step.SYNC]:
		model.rotation.y += delta * TAU * (1.5 if step == Step.SYNC else 1.0)
	if _left > 0.0 or step == Step.SYNC:
		return
	if step == Step.SPIN:
		_attack()
		step = Step.RECOVER
		_left = 1.2
	elif board and is_instance_valid(target):
		var destination := board.reserve_hop(piece_index, board_root.to_local(target.global_position))
		_jump_start = global_position
		_jump_end = board_root.to_global(MotherBoard.center(destination))
		_jump_time = 0
		step = Step.HOP

func _start_spin() -> void:
	step = Step.SYNC if _wave_requested else Step.SPIN
	_left = 0.8 if _wave_requested else 1.0
	_material.emission_enabled = true
	_material.emission = Color(0.8,0.35,1.0) if _wave_requested else (Color.GOLD if (_turn + 1) % 2 == 0 else Color.SKY_BLUE)
	_material.emission_energy_multiplier = 0.8

func _attack() -> void:
	if not is_instance_valid(target):
		return
	_material.emission_enabled = false
	attack_count += 1
	_turn += 1
	if _turn % 2 == 0:
		# Visible short ring marks the melee strike's reach, even if it misses.
		var strike := MotherWave.new()
		strike.target = target
		strike.damage = _attack_damage({})
		strike.max_radius = 3.0
		strike.color = Color.GOLD
		_own(strike, global_position)
	else:
		var shot := EnemyProjectile.new()
		shot.target = target
		shot.damage = _attack_damage({})
		shot.technique_id = ["foie", "barta", "zonde"][piece_index]
		shot.color = [Color.ORANGE_RED, Color.SKY_BLUE, Color.YELLOW][piece_index]
		shot.max_range = 30.0
		var direction := target.global_position - global_position
		direction.y = 0
		shot.dir = direction.normalized()
		_own(shot, global_position + Vector3.UP)

func _own(delivery: Node3D, origin: Vector3) -> void:
	board_root.get_parent().add_child(delivery)
	delivery.global_position = origin
	_shots = _shots.filter(is_instance_valid)
	_shots.append(delivery)

func request_wave() -> void:
	_wave_requested = true
	if step != Step.HOP:
		_start_spin()

func wave_ready() -> bool:
	return is_alive and not paused and step == Step.SYNC and _left <= 0.0

func release_wave(budget: Dictionary) -> void:
	var wave := MotherWave.new()
	wave.target = target
	wave.damage = _attack_damage({})
	wave.hit_budget = budget
	_own(wave, global_position)
	_material.emission_enabled = false
	wave_count += 1
	_wave_requested = false
	step = Step.RECOVER
	_left = 1.4

func hold_for_entry() -> void:
	paused = true
	_material.emission_enabled = false
	_wave_requested = false
	clear_deliveries()

func resume_board() -> void:
	paused = false
	if step != Step.HOP:
		step = Step.RECOVER
		_left = 1.0

func clear_deliveries() -> void:
	for shot in _shots:
		if is_instance_valid(shot):
			shot.set_physics_process(false)
			shot.queue_free()
	_shots.clear()

func _die() -> void:
	if not is_alive:
		return
	if board:
		board.release(piece_index)
	clear_deliveries()
	super._die()

func _exit_tree() -> void:
	if board:
		board.release(piece_index)
	clear_deliveries()
