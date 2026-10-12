class_name ReyburnDeliveries extends RefCounted
## Separate six-slot projectiles, six-slot delayed ground fire and claw hazard.
## Retail trajectories/timing; visual primitives and shared damage remain adapters.
var shots: Array[Dictionary] = []
var fires: Array[Dictionary] = []
var hazard: Dictionary = {}
var trail: Dictionary = {}
var contact_hit := false
var serial := 0

func reset_contact() -> void:
	contact_hit = false

func clear() -> void:
	for item in shots+fires:
		if is_instance_valid(item.node): item.node.queue_free()
	if not hazard.is_empty() and is_instance_valid(hazard.node): hazard.node.queue_free()
	shots.clear(); fires.clear(); hazard.clear(); trail.clear()

func _visual(boss, point: Vector3, radius: float, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius; mesh.height = radius*2
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	node.material_override = material
	boss.get_parent().add_child(node)
	node.global_position = point
	return node

func launch(boss, angle: float, variant: int, airborne := false) -> void:
	if shots.size() >= 6 or not boss.is_alive: return
	var before: int = boss._owned_shots.size()
	boss._shoot(angle,"orb",Color(1.0,0.4,0.05))
	if before == boss._owned_shots.size(): return
	var node = boss._owned_shots.back()
	node.set_physics_process(false)
	var origin: Vector3 = boss._shot_origin()
	var bone: int = boss._skeleton.find_bone("ago") if boss._skeleton else -1
	if bone >= 0: origin = boss._skeleton.global_transform*boss._skeleton.get_bone_global_pose(bone).origin
	node.global_position = origin
	var dir: Vector3 = boss.global_basis.z.rotated(Vector3.UP,angle)
	if airborne: dir = (boss.flight.arena.origin-origin).normalized()
	node.dir = dir
	serial += 1
	shots.append({"node":node,"dir":dir,"variant":variant,"airborne":airborne,"impact":-1})

func _hit(boss, point: Vector3, shape: int) -> bool:
	if not is_instance_valid(boss.target): return false
	var radius: float = float(boss.catalog.shapes[shape].get("radius_raw",0))/4096.0
	var delta: Vector3 = boss.target.global_position-point
	return Vector2(delta.x,delta.z).length() <= radius+0.5

func contact(boss, shape: int) -> void:
	if not contact_hit and _hit(boss,boss.global_position,shape):
		contact_hit = true
		boss._damage_target()

func tick(boss) -> void:
	for i in range(shots.size()-1,-1,-1):
		if _tick_shot(boss,shots[i]): shots.remove_at(i)
	if boss.state_field == "0x108" and boss.flight.fired and shots.is_empty() and not boss.flight.center_fire_finished:
		boss.flight.center_fire_finished = true
		var toward: Vector3 = (boss.target.global_position-boss.flight.arena.origin)*Vector3(1,0,1) if is_instance_valid(boss.target) else Vector3.FORWARD
		trail = {"position":boss.flight.arena.origin,"yaw":atan2(toward.x,toward.z),"age":0,"wait":0}
	for i in range(fires.size()-1,-1,-1):
		var f: Dictionary = fires[i]
		# Original age > 2 and <= 15 creates/retains the attack record.
		if f.age > 2 and f.age <= 15 and not f.hit and _hit(boss,f.node.global_position,5):
			f.hit = true; boss._damage_target()
		f.age += 1
		if f.age >= 32:
			f.node.queue_free(); fires.remove_at(i)
	_tick_trail(boss)
	_tick_hazard(boss)

func _tick_shot(boss, s: Dictionary) -> bool:
	if not is_instance_valid(s.node) or s.node.is_queued_for_deletion(): return true
	if s.impact >= 0:
		s.impact += 1
		if s.impact >= 17: s.node.queue_free(); return true
		return false
	var local: Vector3 = boss.flight.arena.affine_inverse()*s.node.global_position
	var hit := local.y <= 2.0 and _hit(boss,s.node.global_position,3 if s.variant else 2)
	if local.y < 0 or hit or (not s.airborne and (absf(local.x) > 32 or absf(local.z) > 25)):
		if hit: boss._damage_target()
		s.impact = 0
		s.node.global_position.y = boss.flight.arena.origin.y
		s.node.scale *= 1.5
		return false
	if not s.airborne and is_instance_valid(boss.target): _home_shot(boss,s)
	s.node.dir = s.dir
	s.node.global_position += s.dir*(1.25 if s.airborne else 1.5 if s.variant else 2458.0/4096.0)
	return false

func _home_shot(boss, s: Dictionary) -> void:
	var to: Vector3 = boss.target.global_position-s.node.global_position
	var yaw := atan2(s.dir.x,s.dir.z)
	var bearing := wrapf(atan2(to.x,to.z)-yaw,-PI,PI)
	var turn := (318.0 if s.variant else 45.0)*TAU/65536.0
	turn *= minf(absf(bearing)/(910.0*TAU/65536.0),1.0)
	yaw += clampf(bearing,-turn,turn)
	s.dir = Vector3(sin(yaw),0,cos(yaw))

func _tick_trail(boss) -> void:
	if trail.is_empty(): return
	trail.age += 1
	trail.wait -= 4096
	if trail.wait <= 0:
		trail.wait = 30720
		if fires.size() < 6:
			var sideways := Vector3(cos(trail.yaw),0,-sin(trail.yaw))
			var point: Vector3 = trail.position+sideways*boss.rng.randf_range(-3.75,3.75)
			fires.append({"node":_visual(boss,point+Vector3.UP*0.3,0.6,Color(1,0.25,0.04)),"age":0,"hit":false})
	if is_instance_valid(boss.target):
		var delta: Vector3 = boss.target.global_position-trail.position
		var bearing := wrapf(atan2(delta.x,delta.z)-float(trail.yaw),-PI,PI)
		trail.yaw += clampf(bearing,-TAU*0x222/65536.0,TAU*0x222/65536.0)
	trail.position += Vector3(sin(trail.yaw),0,cos(trail.yaw))*0.5
	if trail.age >= 150 or not boss._has_floor_at(trail.position): trail.clear()

func claw_hazard(boss, point: Vector3) -> void:
	if not hazard.is_empty(): return
	hazard = {"node":_visual(boss,point,2.0,Color(0.5,0.16,0.05)),"age":0,"height":-0.4,"hit":false,"yaw":boss.rotation.y}

func _tick_hazard(boss) -> void:
	if hazard.is_empty(): return
	hazard.age += 1
	var age: int = hazard.age
	hazard.height = minf(-0.4+float(age)*109.0/4096.0,0.0) if age < 316 else maxf(-0.4,-float(age-315)*109.0/4096.0)
	hazard.node.position.y = hazard.height
	if age >= 16 and age <= 315 and not hazard.hit and is_instance_valid(boss.target):
		var delta: Vector3 = (boss.target.global_position-hazard.node.global_position).rotated(Vector3.UP,-float(hazard.yaw))
		# Kind-1 region remains the documented rectangular adapter.
		if absf(delta.x) <= 10.5 and absf(delta.z) <= 7.5:
			hazard.hit = true; boss._damage_target()
	if age >= 331: hazard.node.queue_free(); hazard.clear()
