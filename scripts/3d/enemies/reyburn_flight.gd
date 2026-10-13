class_name ReyburnFlight extends RefCounted
## Authored aerial pass: fire, relocate, fire again, then approach safe floor.
var pass_index := 0
var landing_point := Vector3.ZERO
var returning := false

func begin() -> void:
	pass_index = 0
	returning = false

func move(boss, to_floor: bool = false) -> void:
	returning = to_floor
	var preferred: Vector3 = boss.global_position
	if not to_floor and is_instance_valid(boss.target):
		var outward: Vector3 = (boss.global_position-boss.target.global_position) * Vector3(1,0,1)
		if outward.length_squared() < 0.01: outward = -boss.global_basis.z
		preferred = boss.target.global_position + outward.normalized().rotated(Vector3.UP,0.8 if pass_index%2 == 0 else -1.2)*24.0
		pass_index += 1
	var floor_hit := ReyburnFloor.landing(boss,preferred)
	boss._motion_start = boss.global_position
	boss._motion_end = boss.global_position
	boss._state_limit = 0 # Retry safely if the stage has no usable collision yet.
	if not floor_hit.is_empty():
		landing_point = floor_hit.position
		boss._motion_end = landing_point + Vector3.UP*8.0
		boss._state_limit = maxi(60,ceili(boss._motion_start.distance_to(boss._motion_end)/8.0*30.0))
	boss.play_action(18,{0:-1})

func tick(boss) -> void:
	if boss._state_limit == 0:
		if boss._state_ticks%30 == 0:
			boss._state_ticks = 0
			move(boss,returning)
		return
	var progress := smoothstep(0.0,float(boss._state_limit),float(boss._state_ticks))
	boss.global_position = boss._motion_start.lerp(boss._motion_end,progress)
	boss._turn_step(0x100)
	if boss._state_ticks >= boss._state_limit: boss._enter_next_state()

func land(boss) -> void:
	var floor_hit := ReyburnFloor.sample(boss,boss.global_position)
	if floor_hit.is_empty():
		# Never descend at an unchecked XZ, including legacy claw/landing paths.
		boss._states.push_front("0xe4")
		boss.state_field = "air_return"
		move(boss,true)
		return
	landing_point = floor_hit.position
	boss._motion_start = boss.global_position
	boss._motion_end = landing_point
	boss.play_action(8)

func descend(boss) -> void:
	var progress := minf(float(boss._state_ticks)/50.0,1.0)
	boss.global_position = boss._motion_start.lerp(landing_point,smoothstep(0.0,1.0,progress))
	if progress == 1.0:
		boss._ground_height = landing_point.y
		boss._home = landing_point
