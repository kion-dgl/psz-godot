class_name Projectile extends Area3D
## A projectile that travels forward, damages the first enemy it hits, then despawns.

var speed: float = 30.0
var max_range: float = 20.0
var damage: int = 10
var knockback: float = 3.0
var accuracy: int = 100
var direction: Vector3 = Vector3.FORWARD
var owner_node: Node3D

var _distance_traveled: float = 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 32  # Hit hurtboxes (layer 5)
	monitoring = true
	monitorable = false

	area_entered.connect(_on_area_entered)

	# Visual: small glowing sphere
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	sphere.radial_segments = 8
	sphere.rings = 4
	_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	add_child(_mesh)

	# Collision shape
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	var move := direction * speed * delta
	global_position += move
	_distance_traveled += move.length()

	if _distance_traveled >= max_range:
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if area is Hurtbox:
		var hurtbox := area as Hurtbox
		if hurtbox.owner_node == owner_node:
			return
		hurtbox.take_hit(damage, direction * knockback, accuracy)
		queue_free()
