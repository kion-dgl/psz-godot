class_name FalzTail extends Node3D
## Fixed-location floor warning, emergence, single strike, then retreat.
const WINDUP := 1.0
const ACTIVE := 0.45
const RECOVERY := 0.65
var target: Node3D
var damage := 1
var elapsed := 0.0
var struck := false
var _warning: MeshInstance3D
var _tail: Node3D

func _ready() -> void:
	_warning = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75,0.15,0.8)
	ring.material = mat
	_warning.mesh = ring
	_warning.position.y = 0.08
	add_child(_warning)
	_tail = Node3D.new()
	add_child(_tail)
	for index in 5:
		var segment := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = 0.65 - index * 0.1
		cone.top_radius = maxf(0.02, cone.bottom_radius - 0.18)
		cone.height = 1.0
		cone.material = mat
		segment.mesh = cone
		segment.position = Vector3(sin(index * 0.45) * 1.2, index * 0.7, 0)
		segment.rotation.z = -index * 0.16
		_tail.add_child(segment)
	_tail.hide()

func _physics_process(delta: float) -> void:
	elapsed += delta
	_warning.visible = elapsed < WINDUP
	_tail.visible = elapsed >= WINDUP
	_tail.position.y = -3.5 * (1.0 - clampf((elapsed - WINDUP) / 0.18, 0.0, 1.0))
	if elapsed >= WINDUP + ACTIVE:
		_tail.position.y = -3.5 * clampf((elapsed - WINDUP - ACTIVE) / RECOVERY, 0.0, 1.0)
	if elapsed >= WINDUP and elapsed < WINDUP + ACTIVE and not struck and is_instance_valid(target):
		var offset := target.global_position - global_position
		if Vector2(offset.x, offset.z).length() <= 1.8 and absf(offset.y) < 2.5:
			struck = true # A dodge consumes contact, as with other enemy deliveries.
			if target.has_method("take_damage"): target.take_damage(damage)
	if elapsed >= WINDUP + ACTIVE + RECOVERY:
		queue_free()
