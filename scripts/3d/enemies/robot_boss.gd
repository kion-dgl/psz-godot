class_name RobotBoss extends DescriptorBoss
## Shared robot part ownership and delivery cleanup. See /states/robot-bosses.
var robots: Array[BossModelChannel] = []
var contact_hits: Dictionary = {}

func add_robot(index: int, mesh_path: String, clips: AnimationLibrary, idle: int) -> void:
	var part := BossModelChannel.new()
	part.setup(self,index,load(mesh_path),clips,catalog.actions,idle)
	robots.append(part)
	_register_part(part.model,2.0,index,Vector3(0,1,0))

func robot_shot(origin: Vector3, yaw: float) -> void:
	if not is_alive or not is_instance_valid(target): return
	var shot := EnemyProjectile.new()
	shot.target = target
	shot.damage = _attack_damage({})
	shot.max_range = 45.0
	shot.visual = "laser"
	shot.color = Color(0.4,0.8,1.0)
	shot.dir = Vector3(sin(yaw),0,cos(yaw))
	get_parent().add_child(shot)
	shot.global_position = origin + Vector3.UP
	_owned_shots = _owned_shots.filter(is_instance_valid)
	_owned_shots.append(shot)

func robot_contact(key: String, origin: Vector3, radius: float, active: bool) -> void:
	if not active:
		contact_hits.erase(key)
		return
	if contact_hits.has(key) or not is_instance_valid(target): return
	var distance := Vector2(target.global_position.x-origin.x,target.global_position.z-origin.z).length()
	if distance <= radius + 0.5:
		contact_hits[key] = true
		_damage_target()

func _clear_deliveries() -> void:
	super._clear_deliveries()
	contact_hits.clear()
	for part in robots: part.stop()
