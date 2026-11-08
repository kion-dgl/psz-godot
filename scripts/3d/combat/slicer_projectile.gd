extends Projectile
## Prototype slicer: a visible blade travels between distinct targets.
const BLADE := "res://assets/weapons/wslc01/wslc01/wslc01_3_o/wslc01_3_o.glb"
var _blade: Node3D
var _next_target: Node3D

func _ready() -> void:
	super._ready()
	if ResourceLoader.exists(BLADE):
		_mesh.hide()
		var spin := Node3D.new()
		add_child(spin)
		_blade = spin
		var model := (load(BLADE) as PackedScene).instantiate() as Node3D
		spin.add_child(model)
		model.scale = Vector3.ONE * 0.45
		model.position = Vector3(-0.505, 0, -0.33) * 0.45

func _physics_process(delta: float) -> void:
	if _spent or is_queued_for_deletion(): return
	if is_instance_valid(_blade): _blade.rotate_y(delta * 22.0)
	if is_instance_valid(_next_target):
		if not _next_target.is_alive or not _next_target.hurtbox.monitorable:
			_bounce_to_nearby(global_position)
		if _spent: return
		if is_instance_valid(_next_target):
			var aim: Vector3 = _next_target.global_position + Vector3.UP - global_position
			if not aim.is_zero_approx(): direction = aim.normalized()
	var distance := minf(maxf(speed * delta, 0.0), maxf(max_range - _distance_traveled, 0.0))
	var start := global_position
	var motion := direction.normalized() * distance
	for hit in ProjectileSweep.contacts(get_world_3d().direct_space_state, start, motion, COLLISION_RADIUS):
		var before := _hit_targets.size()
		global_position = start + motion * float(hit.fraction)
		_on_area_entered(hit.hurtbox)
		if _hit_targets.size() != before:
			_distance_traveled += start.distance_to(global_position)
			return # Next frame follows the new direction, never the old sweep segment.
	global_position = start + motion
	_distance_traveled += distance
	if _distance_traveled >= max_range:
		_spent = true
		queue_free()

func _bounce_to_nearby(hit_pos: Vector3) -> void:
	_next_target = null
	var nearest := bounce_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy in _hit_targets or not enemy.is_alive: continue
		if not enemy.hurtbox or not enemy.hurtbox.monitorable: continue
		var distance: float = enemy.global_position.distance_to(hit_pos)
		if distance < nearest:
			nearest = distance
			_next_target = enemy
	if not is_instance_valid(_next_target):
		_spent = true
		queue_free()
