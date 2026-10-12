class_name MotherWave extends Node3D
## Authored expanding, dodgeable ground wave; shared budget prevents triple hits.
var target: Node3D
var damage := 1
var hit_budget: Dictionary = {}
var radius := 0.3
var max_radius := 7.0
var color := Color(0.8, 0.35, 1.0)
var _ring: MeshInstance3D

func _ready() -> void:
	_ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material = material
	_ring.mesh = mesh
	_ring.position.y = 0.15
	add_child(_ring)

func _physics_process(delta: float) -> void:
	var previous := radius
	radius += 5.0 * delta
	_ring.scale = Vector3(radius, 1, radius)
	if is_instance_valid(target) and not hit_budget.has(target.get_instance_id()):
		var offset := target.global_position - global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance >= previous - 0.65 and distance <= radius + 0.65 and absf(offset.y) < 2.0:
			hit_budget[target.get_instance_id()] = true
			if target.has_method("take_damage"):
				target.take_damage(damage)
	if radius >= max_radius:
		queue_free()
