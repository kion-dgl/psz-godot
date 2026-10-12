class_name MotherPiece extends EnemyBase
## Independently damageable test piece. Procedural marker and movement are
## placeholders until the original km* model and board controller are ported.

var piece_index := 0
var _home := Vector3.ZERO
var _delay := 2.0
var _jump_time := -1.0
var _jump_start := Vector3.ZERO
var _jump_end := Vector3.ZERO

func _ready() -> void:
	super._ready()
	var start := global_transform
	top_level = true
	global_transform = start
	_home = global_position
	_delay += float(piece_index)

func _setup_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.65
	mesh.bottom_radius = 1.1
	mesh.height = 2.5
	body.mesh = mesh
	body.position.y = 1.25
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color(0.85,0.55,0.15),Color(0.65,0.7,0.85),Color(0.7,0.2,0.5)][piece_index]
	body.material_override = material
	model.add_child(body)

func _uses_generic_hurt_reaction() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	if not is_instance_valid(target):
		target = _find_player()
	if _jump_time >= 0.0:
		_jump_time = minf(_jump_time + delta, 1.0)
		global_position = _jump_start.lerp(_jump_end, _jump_time) + Vector3.UP * sin(_jump_time * PI) * 3.0
		if _jump_time >= 1.0:
			_jump_time = -1.0
			_delay = 3.0
			if is_instance_valid(target) and global_position.distance_to(target.global_position) < 3.0 and target.has_method("take_damage"):
				target.take_damage(_attack_damage({}))
		return
	_delay -= delta
	if _delay <= 0.0 and is_instance_valid(target):
		_jump_start = global_position
		var aim := target.global_position
		aim.y = _home.y
		_jump_end = _home + (aim - _home).limit_length(8.0)
		_jump_time = 0.0
