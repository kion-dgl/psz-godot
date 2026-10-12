class_name ReyburnFlight extends RefCounted
## Retail ov20 DC/E0/E8/EC/108/E4 states. The arena transform is an adapter;
## spline arithmetic and travel controller come from retained emulator samples.
var path := ReyburnPath.new()
var arena := Transform3D.IDENTITY
var phase := 0
var side := 1
var landing_point := Vector3.ZERO
var returning := false
var released := false
var downward := 0
var drop_motion := Vector3i.ZERO
var claw_speed := 0
var claw_edge := Vector3.ZERO
var pass_index := 0
var pass_speed := 3072
var pass_gain := 102
var wait := 0
var fired := false
var center_fire_finished := false
var spin_offset := Vector3i.ZERO
var spin_velocity := 0

func begin(boss = null) -> void:
	phase = 0
	released = false
	returning = false
	path = ReyburnPath.new()
	if boss != null:
		arena = boss.get_parent().global_transform
		arena.origin.y = boss._ground_height

func local_position(boss) -> Vector3:
	return arena.affine_inverse()*boss.global_position

func _target(boss) -> Vector3:
	return arena.affine_inverse()*boss.target.global_position if is_instance_valid(boss.target) else Vector3.ZERO

func _points(_boss, points: Array[Vector3], speed: int, gain: int, reset := false) -> void:
	var raw_points: Array[Vector3i] = []
	for point in points: raw_points.append(ReyburnPath.raw(point))
	path.begin(raw_points,speed,gain,reset)
	spin_offset = Vector3i.ZERO
	spin_velocity = 0

func _move_body(boss, steer := true) -> void:
	var before: Vector3 = boss.global_position
	var point := path.tick()
	if boss.state_field == "0xec": point += spin_offset
	boss.global_position = arena*ReyburnPath.vector(point)
	var movement: Vector3 = boss.global_position-before
	if steer and Vector2(movement.x,movement.z).length() > 0.001:
		boss.rotation.y = lerp_angle(boss.rotation.y,atan2(movement.x,movement.z),0.15)

func takeoff(boss) -> void:
	phase = 0
	released = false
	side = 1 if local_position(boss).x >= 0 else -1
	path.position = ReyburnPath.raw(local_position(boss))
	boss.play_action(7,{1:-1})

func move(boss, to_floor := false) -> void:
	returning = to_floor
	phase = 0
	if to_floor:
		land(boss)
		return
	# E0 re-enters below an END of the arena, not above the player.
	var end := 1 if int(boss.request.get("entry_side",0)) != 0 else -1
	path.position = Vector3i(0,-30*4096,end*40*4096)
	path.motion = Vector3i.ZERO
	path.active = false
	boss.global_position = arena*ReyburnPath.vector(path.position)
	boss.rotation.y = arena.basis.get_euler().y + (PI if end > 0 else 0.0)
	boss.play_action(18,{0:-1})
	# Retail E0 uses action rate 0x1400.
	boss.clock.action = boss.clock.action.duplicate(true)
	boss.clock.action.stages[0].playback_rate_raw = 5120

func claw(boss) -> void:
	phase = 0
	var p := local_position(boss)
	var end := 1 if p.z >= 0 else -1
	_points(boss,[p,p+Vector3(0,1,-2*end),Vector3(p.x,0,22*end),Vector3(p.x,1,20*end)],410,410)
	boss.play_action(18,{0:-1})

func spin(boss) -> void:
	phase = 0
	pass_index = 0
	pass_speed = 3072
	pass_gain = 102
	var p := local_position(boss)
	var end := 1 if p.z > 0 else -1
	var z := clampf(_target(boss).z,10.0,18.0) if end > 0 else clampf(_target(boss).z,-18.0,-10.0)
	_points(boss,[p,Vector3(p.x,4,22*end),Vector3(15,4,z),Vector3(30,10,z)],pass_speed,pass_gain)
	boss.play_action(22)

func _next_spin(boss) -> void:
	var p := local_position(boss)
	var target := _target(boss)
	var dz := target.z-p.z
	if absf(dz) < 10.0: dz = 10.0 if dz > 0 else -10.0
	elif absf(dz) < 20.0: dz = 20.0 if dz > 0 else -20.0
	var bend := p+Vector3(absf(dz) if p.x > 0 else -absf(dz),0,dz*0.5)
	var turn := p+Vector3(0,0,dz)
	var toward := (target-turn)*Vector3(1,0,1)
	toward = toward.normalized()
	# Degenerate alignment is a port guard; retail arena targeting avoids it.
	if absf(toward.x) < 0.001: toward = Vector3(-signf(p.x),0,0)
	var inner := turn+toward*((absf(turn.x)-15.0)/absf(toward.x)); inner.y = 4
	var across := inner+toward*(5.0/absf(toward.x))
	var end := across+toward*(15.0/absf(toward.x)); end.y = 10
	pass_speed = ReyburnPath.mul(pass_speed,4506)
	pass_gain = ReyburnPath.mul(pass_gain,4506)
	_points(boss,[p,bend,turn,inner,across,end],pass_speed,pass_gain)

func air_breath(boss) -> void:
	phase = 0
	wait = 0
	fired = false
	released = false
	center_fire_finished = false
	boss.play_action(19)

func land(boss) -> void:
	phase = 0
	var wanted: Vector3 = boss.request.get("landing",Vector3.ZERO)
	var floor_hit := ReyburnFloor.landing(boss,arena*wanted)
	if floor_hit.is_empty():
		phase = -1
		return
	landing_point = floor_hit.position
	var local_landing: Vector3 = arena.affine_inverse()*landing_point
	_points(boss,[local_position(boss),local_landing+Vector3.UP*5],2048,20)
	boss.play_action(18,{0:-1})

func tick(boss) -> void:
	match boss.state_field:
		"0xdc": _takeoff_tick(boss)
		"0xe0": _rise_tick(boss)
		"0xe8": _claw_tick(boss)
		"0xec": _spin_tick(boss)
		"0x108":
			if released and not fired:
				fired = true
				boss.deliveries.launch(boss,0.0,1,true)
			_move_body(boss,false)
			if not boss.clock.running and boss.action_id == 19: boss.play_action(18,{0:-1})
			if boss.action_id == 18 and center_fire_finished:
				wait += 1
				if wait > 10: boss._enter_next_state()
		"0xe4","air_return": _land_tick(boss)

func _takeoff_tick(boss) -> void:
	if phase == 0:
		if not released: return
		var p := local_position(boss)
		_points(boss,[p,p+Vector3.UP*5],614,41,true)
		phase = 1
	elif phase == 1 and not path.active:
		var p := local_position(boss)
		_points(boss,[p,p+Vector3(5*side,5,0),p+Vector3(10*side,5,0),Vector3(20*side,7,0),Vector3(60*side,7,0)],2048,20,true)
		phase = 2
	elif phase == 2 and not path.active:
		drop_motion = path.motion
		downward = 0
		boss.play_action(20,{1:-1})
		phase = 3
	elif phase == 3:
		if path.position.y <= -30*4096:
			phase = 4
			wait = 2
			return
		downward = mini(downward+102,5*4096)
		path.motion = drop_motion+Vector3i(0,-downward,0)
	elif phase == 4:
		wait -= 1
		if wait <= 0: boss._enter_next_state()
		return
	_move_body(boss)

func _rise_tick(boss) -> void:
	if path.position.y >= 51200:
		boss._enter_next_state()
		return
	var target := _target(boss)
	var p := ReyburnPath.vector(path.position)
	var x := 0
	if absf(target.x-p.x) > 1 and absf(p.x) < 5: x = 410 if target.x > p.x else -410
	var frame := float(boss.clock.frame_q12)/4096.0
	path.motion = Vector3i(x,1024+roundi(1024*absf(cos((frame-22)*PI/30.0))),0)
	_move_body(boss,false)

func _claw_tick(boss) -> void:
	if phase == 0:
		if path.active:
			var progress := float(path.distance)/float(path.distances.back())
			path.wanted_speed = 410+roundi((4096-410)*progress)
			if progress > 0.5 and boss.action_id != 20: boss.play_action(20,{1:-1})
		else:
			boss.controller.head_damage = 0
			claw_speed = ReyburnPath.magnitude(path.motion)
			phase = 1
	elif phase in [1,2]:
		boss._turn_step(0x1c7)
		var ahead: Vector3 = boss.global_position+boss.global_basis.z*(30.0 if phase == 1 else 10.0)
		if not boss._has_floor_at(ahead):
			if phase == 1:
				claw_edge = boss.global_position
				phase = 2
			else:
				phase = 3
				boss.play_action(21,{1:-1})
		path.motion = ReyburnPath.scaled(ReyburnPath.raw(arena.basis.inverse()*boss.global_basis.z),claw_speed)
		boss.deliveries.contact(boss,0)
	elif phase == 3:
		claw_speed = maxi(0,claw_speed-205)
		path.motion = ReyburnPath.scaled(ReyburnPath.raw(arena.basis.inverse()*boss.global_basis.z),claw_speed)
		if claw_speed == 0:
			var toward: Vector3 = (claw_edge-boss.global_position)*Vector3(1,0,1)
			boss.deliveries.claw_hazard(boss,boss.global_position+toward.normalized()*5)
			var floor_hit := ReyburnFloor.landing(boss,boss.global_position)
			if not floor_hit.is_empty(): boss.global_position = floor_hit.position
			boss._ground_height = boss.global_position.y
			boss._enter_next_state()
			return
	_move_body(boss)
	if path.position.y < 0: path.position.y = 0; boss.global_position = arena*ReyburnPath.vector(path.position)

func _spin_tick(boss) -> void:
	if phase == 0:
		if not path.active:
			pass_index += 1
			if pass_index == 6:
				phase = 1; wait = 30
				boss.play_action(23)
			else:
				boss.deliveries.reset_contact()
				_next_spin(boss)
		else:
			_spin_steering(boss)
			boss.deliveries.contact(boss,1)
	else:
		wait -= 1
		if boss.model: boss.model.rotation.z *= maxf(0.0,float(wait)/30.0)
		if wait < 0:
			boss._enter_next_state()
			return
	_move_body(boss)

func _spin_steering(boss) -> void:
	var progress := float(path.distance)/float(path.distances.back())
	# Remaining counter starts at five: alternate paths steer after 0x266/4096.
	if pass_index%2 == 1 and progress > 614.0/4096.0:
		spin_velocity = ReyburnPath.mul(spin_velocity,3072)
		var acceleration := roundi(410*absf(sin(boss._bearing())))
		spin_velocity += acceleration if _target(boss).z > local_position(boss).z else -acceleration
		spin_velocity = clampi(spin_velocity,-3072,3072)
		spin_offset.z += spin_velocity
	if boss.model:
		var turns := int(path.distances.back()/4096)/15
		boss.model.rotation.z = TAU*turns*(1.0-cos(progress*PI))*0.5

func _land_tick(boss) -> void:
	if phase == -1:
		if boss._state_ticks%30 == 0: land(boss)
		return
	if phase == 0 and not path.active:
		phase = 1
		downward = 0
	if phase == 1:
		downward = mini(downward+41,614)
		path.motion.y = -downward
		var floor_y := ReyburnPath.raw(arena.affine_inverse()*landing_point).y
		if boss.action_id != 8 and path.position.y-floor_y < downward*40: boss.play_action(8)
		_move_body(boss,false)
		if path.position.y < floor_y: path.position.y = floor_y; boss.global_position = arena*ReyburnPath.vector(path.position)
		if boss.action_id == 8 and not boss.clock.running:
			boss.global_position = landing_point
			boss._ground_height = landing_point.y
			boss._home = landing_point
			boss._enter_next_state()
	else: _move_body(boss)
