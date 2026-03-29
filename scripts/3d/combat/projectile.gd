class_name Projectile extends Area3D
## A projectile that travels forward, damages enemies it hits, then despawns.
## Set pierce = true to hit all enemies along the path (e.g. Barta).

var speed: float = 30.0
var max_range: float = 20.0
var damage: int = 10
var knockback: float = 3.0
var accuracy: int = 100
var direction: Vector3 = Vector3.FORWARD
var owner_node: Node3D
var color: Color = Color(1.0, 0.9, 0.5)
var pierce: bool = false
var spiral_rate: float = 0.0  # Radians per second to curve direction (0 = straight)
var spiral_origin: Vector3 = Vector3.ZERO  # Center point for spiral expansion
var bounce_radius: float = 0.0  # On hit, also damage unhit enemies within this radius (slicers)
var max_hits: int = 0  # Max total enemies to hit (0 = unlimited for pierce, 1 for normal)

var _distance_traveled: float = 0.0
var _mesh: MeshInstance3D
var _hit_targets: Array = []


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
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
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
	# Spiral: rotate direction around Y axis each frame
	if spiral_rate != 0.0:
		direction = direction.rotated(Vector3.UP, spiral_rate * delta)

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
		if hurtbox.owner_node in _hit_targets:
			return
		if max_hits > 0 and _hit_targets.size() >= max_hits:
			return
		_hit_targets.append(hurtbox.owner_node)
		hurtbox.take_hit(damage, direction * knockback, accuracy)

		# Bounce: damage nearby unhit enemies within radius
		if bounce_radius > 0.0:
			_bounce_to_nearby(hurtbox.owner_node.global_position)

		if not pierce:
			if max_hits > 0 and _hit_targets.size() >= max_hits:
				queue_free()
			else:
				queue_free()


func _bounce_to_nearby(hit_pos: Vector3) -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if max_hits > 0 and _hit_targets.size() >= max_hits:
			break
		if not is_instance_valid(enemy) or enemy in _hit_targets:
			continue
		if not enemy.get("is_alive"):
			continue
		var dist: float = enemy.global_position.distance_to(hit_pos)
		if dist <= bounce_radius and enemy.hurtbox:
			_hit_targets.append(enemy)
			var bounce_dir: Vector3 = (enemy.global_position - hit_pos).normalized()
			enemy.hurtbox.take_hit(damage, bounce_dir * knockback, accuracy)
