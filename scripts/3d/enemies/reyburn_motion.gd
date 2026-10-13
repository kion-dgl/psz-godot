class_name ReyburnMotion extends RefCounted
## Ground steering is tied to traveled distance, with speed/yaw acceleration.
var speed := 0.0
var yaw_speed := 0.0
var reverse_ticks := 0

func reset() -> void:
	speed = 0.0
	yaw_speed = 0.0
	reverse_ticks = 0

func step(boss, requested_speed: float, destination: Variant = null) -> bool:
	var bearing: float = boss._bearing()
	if destination is Vector3:
		var offset: Vector3 = destination - boss.global_position
		bearing = wrapf(atan2(offset.x,offset.z)-boss.rotation.y,-PI,PI)
	var reversing := reverse_ticks > 0
	if reversing: reverse_ticks -= 1
	speed = move_toward(speed,-1.5 if reversing else requested_speed,3.0/30.0)
	var yaw_limit := deg_to_rad(32.0) * minf(absf(speed)/2.4,1.0)
	yaw_speed = move_toward(yaw_speed,clampf(bearing*1.5,-yaw_limit,yaw_limit),deg_to_rad(48.0)/30.0)
	var turn := yaw_speed/30.0
	var direction: Vector3 = boss.global_basis.z.rotated(Vector3.UP,turn)
	var motion := direction*speed/30.0
	var floor_hit := ReyburnFloor.sample(boss,boss.global_position+motion)
	if floor_hit.is_empty():
		reverse_ticks = 30
		speed = 0.0
		yaw_speed = 0.0
		return false
	motion.y = clampf(float(floor_hit.position.y)-boss.global_position.y,-0.25,0.25)
	var before: Vector3 = boss.global_position
	boss.move_and_collide(motion)
	var displacement: Vector3 = boss.global_position - before
	var traveled := Vector2(displacement.x,displacement.z).length()
	var actual_floor := ReyburnFloor.sample(boss,boss.global_position)
	if not actual_floor.is_empty():
		boss.global_position.y = actual_floor.position.y
		boss._ground_height = actual_floor.position.y
	# Blocked bodies cannot spin in place while their feet stay planted.
	boss.rotation.y += turn*minf(traveled/maxf(motion.length(),0.0001),1.0)
	if traveled < motion.length()*0.2 and absf(speed) > 0.5: reverse_ticks = 30
	return absf(boss._bearing()) < 0.12
