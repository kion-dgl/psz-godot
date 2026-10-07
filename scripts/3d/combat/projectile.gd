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
var max_hits: int = 1  # Cap on enemies hit. Default 1 = single-target (handgun/rifle).
                       # Spawners override per weapon: slicer = 4, pierce techs (Barta) high.
var element: String = ""  # Element type for status effect procs
var element_level: int = 0  # Element level (higher = more likely to proc)

const COLLISION_RADIUS := 0.15
var _spent := false

var _distance_traveled: float = 0.0
var _mesh: MeshInstance3D
var _hit_targets: Array = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 32  # Hit hurtboxes (layer 5)
	monitoring = false  # Swept queries own contact; no delayed overlap callbacks.
	monitorable = false

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
	shape.radius = COLLISION_RADIUS
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	if _spent or is_queued_for_deletion():
		return
	if spiral_rate != 0.0:
		direction = direction.rotated(Vector3.UP, spiral_rate * delta)
	var distance := minf(maxf(speed * delta, 0.0), maxf(max_range - _distance_traveled, 0.0))
	var motion := direction.normalized() * distance
	var start := global_position
	for hit in ProjectileSweep.contacts(get_world_3d().direct_space_state, start, motion, COLLISION_RADIUS):
		global_position = start + motion * float(hit.fraction)
		_on_area_entered(hit.hurtbox)
		if _spent:
			return
	global_position = start + motion
	_distance_traveled += distance
	if _distance_traveled >= max_range:
		_spent = true
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	if _spent or is_queued_for_deletion() or not area is Hurtbox or not area.monitorable:
		return
	var hurtbox := area as Hurtbox
	if not is_instance_valid(hurtbox.owner_node) or hurtbox.owner_node == owner_node:
		return
	if hurtbox.owner_node.get("is_alive") == false:
		return
	if hurtbox.owner_node in _hit_targets:
		return
	if max_hits > 0 and _hit_targets.size() >= max_hits:
		return
	_hit_targets.append(hurtbox.owner_node)
	# Latch before damage: death callbacks and additional parts can re-enter.
	_spent = not pierce or (max_hits > 0 and _hit_targets.size() >= max_hits)
	var hit_pos := hurtbox.owner_node.global_position
	hurtbox.take_hit(damage, direction * knockback, accuracy, element, element_level)
	if bounce_radius > 0.0:
		_bounce_to_nearby(hit_pos)
	if max_hits > 0 and _hit_targets.size() >= max_hits:
		_spent = true
	if _spent:
		queue_free()


func _bounce_to_nearby(hit_pos: Vector3) -> void:
	# Sort candidates by distance so we pick the closest first
	var candidates: Array = []
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy in _hit_targets:
			continue
		if not enemy.get("is_alive"):
			continue
		if not enemy.hurtbox:
			continue
		var dist: float = enemy.global_position.distance_to(hit_pos)
		if dist <= bounce_radius:
			candidates.append({"enemy": enemy, "dist": dist})

	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	for c in candidates:
		if max_hits > 0 and _hit_targets.size() >= max_hits:
			break
		var enemy = c.enemy
		# Angle penalty: sharper turns reduce effective bounce range
		var to_enemy: Vector3 = (enemy.global_position - hit_pos).normalized()
		var angle_factor: float = maxf(direction.dot(to_enemy), 0.0)  # 1.0=same dir, 0.0=perpendicular
		var effective_range: float = bounce_radius * (0.5 + 0.5 * angle_factor)
		if c.dist > effective_range:
			continue
		_hit_targets.append(enemy)
		var bounce_dir: Vector3 = to_enemy
		enemy.hurtbox.take_hit(damage, bounce_dir * knockback, accuracy, element, element_level)
