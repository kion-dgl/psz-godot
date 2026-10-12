class_name ParuRobotBoss extends RobotBoss
## Partial ov22 split encounter. Counter spans/HP tuning are recovered;
## trajectories, target predicates and delivery geometry remain provisional.
const CHANNEL0_CLIPS = preload("res://data/boss_animations/paru_z_003u.tres")
const CHANNEL1_CLIPS = preload("res://data/boss_animations/paru_z_003n.tres")
var states: Array[int] = [0,0]
var counters: Array[int] = [0,0]
var starts: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var goals: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var rounds := 0
var origin := Vector3.ZERO
var initialized := false

func _ready() -> void:
	super._ready()
	model.hide()
	hurtbox.set_deferred("monitorable",false)
	add_robot(0,"res://assets/enemies/boss_robot/parts/z_103u/z_103u.glb",CHANNEL0_CLIPS,4)
	add_robot(1,"res://assets/enemies/boss_robot/parts/z_003n/z_003n.glb",CHANNEL1_CLIPS,5)
	robots[0].model.position = Vector3(-6,0,0)
	robots[1].model.position = Vector3(6,0,0)
	robots[0].play([0])
	robots[1].play([1])

func _controller_tick() -> void:
	if not initialized:
		origin = global_position
		initialized = true
	# Original parent dispatch: child38/channel0 before child34/channel1.
	for index in 2:
		robots[index].tick()
		_tick_robot(index)

func _tick_robot(index: int) -> void:
	var state := states[index]
	var tick := counters[index]
	if state == 0:
		if not robots[index].busy: _enter(index,10 if index == 0 else 9)
		return
	if _boundary(index,state,tick): return
	if index == 0: _channel0(state,tick)
	else: _channel1(state,tick)
	counters[index] += 1

func _boundary(index: int, state: int, tick: int) -> bool:
	var tuning := RobotAttackRules.parameters(current_hp,encounter_max_hp,_tier())
	var next := _next_channel0(state,tick,tuning[4]) if index == 0 else _next_channel1(state,tick,tuning[3])
	if next < 0: return false
	robot_contact(str(index),Vector3.ZERO,0,false)
	_enter(index,next)
	return true

func _next_channel0(state: int, tick: int, idle: int) -> int:
	if state == 10 and tick >= idle:
		if rounds >= 3: return 7
		rounds += 1
		return 12
	if state == 12 and tick >= 299: return 10
	if state == 7 and tick >= 45:
		_enter(1,7)
		return 8
	if state == 8 and tick >= 90: return 9
	if state == 9 and tick >= 150:
		rounds = 0
		return 10
	return -1

func _next_channel1(state: int, tick: int, idle: int) -> int:
	if state == 9 and tick >= idle: return 10
	if state == 10 and tick >= 120: return 11
	if state == 11 and tick >= 54: return 9
	if state == 7 and tick >= 90: return 8
	if state == 8 and tick >= 150: return 9
	return -1

func _channel0(state: int, tick: int) -> void:
	match state:
		12: _aerial(tick)
		7,8:
			var destination := origin + Vector3(2,1.25,0)
			robots[0].model.global_position = starts[0].lerp(destination,clampf(tick/90.0,0.0,1.0))
		9: _orbit(0,tick)
		_: _face(0)

func _channel1(state: int, tick: int) -> void:
	match state:
		7:
			robots[1].model.global_position = starts[1].lerp(origin+Vector3(-2,0,0),tick/90.0)
		8: _orbit(1,tick)
		11:
			var fraction := clampf(float(tick-7)/17.0,0.0,1.0)
			robots[1].model.global_position = starts[1].lerp(goals[1],fraction)
			robot_contact("1",robots[1].model.global_position,1.5,RobotAttackRules.contact(11,tick))
		_: _face(1)

func _aerial(tick: int) -> void:
	var part := robots[0].model
	var t := float(tick)
	if tick < 15: _face(0)
	elif tick < 60: part.global_position = starts[0].lerp(goals[0],(t-15.0)/45.0)
	elif tick < 105: part.position.y = (t-60.0)/45.0*6.0
	elif tick < 195: part.position.y = 6.0
	elif tick < 255: part.position.y = 6.0*(1.0-(t-195.0)/60.0)
	else: part.position.y = 0.0
	# Original expanding areas remain a delivery gap; initial bounded pulses.
	robot_contact("0",goals[0],3.5,tick == 15 or tick == 210)

func _orbit(index: int, tick: int) -> void:
	var angle := -TAU * tick / 150.0 + index*PI
	var part := robots[index].model
	part.global_position = origin + Vector3(cos(angle)*2.0,1.25 if index == 0 else 0.0,-sin(angle)*2.0)
	part.rotation.y = angle
	if RobotAttackRules.orbit_shoot(tick):
		var yaw := _target_yaw(index)
		if index == 0: robot_shot(part.global_position,yaw)
		else:
			for side in [-0.25,0.25]: robot_shot(part.global_position,yaw+side)

func _target_yaw(index: int) -> float:
	var aim := target.global_position if is_instance_valid(target) else origin
	var direction := aim-robots[index].model.global_position
	return atan2(direction.x,direction.z)

func _face(index: int) -> void:
	robots[index].model.rotation.y = lerp_angle(robots[index].model.rotation.y,_target_yaw(index),0.1)

func _enter(index: int, state: int) -> void:
	states[index] = state
	counters[index] = 1 # entry reset followed by original enclosing increment
	starts[index] = robots[index].model.global_position
	var aim := target.global_position if is_instance_valid(target) else origin
	goals[index] = Vector3(clampf(aim.x,origin.x-13,origin.x+13),origin.y,clampf(aim.z,origin.z-13,origin.z+13))

func _tier() -> int:
	return int({"normal":0,"hard":1,"super-hard":2}.get(SessionManager.get_session().get("difficulty","normal"),0))

func _physics_process(delta: float) -> void:
	if _dying:
		robots[1].clock.advance(delta)
		robots[1].player.seek(robots[1].clock.frame_q12/4096.0/60.0,true)
	super._physics_process(delta)

func _death_action() -> int:
	animation_player = robots[0].player
	robots[1].play([7])
	return 6
