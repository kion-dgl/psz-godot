class_name ParuRobotBoss extends RobotBoss
## Partial ov22 split encounter. Counter spans/HP tuning are recovered;
## trajectories, target predicates and delivery geometry remain provisional.
const Motion = preload("res://scripts/3d/enemies/paru_robot_motion.gd")
const CHANNEL0_CLIPS = preload("res://data/boss_animations/paru_z_003u.tres")
const CHANNEL1_CLIPS = preload("res://data/boss_animations/paru_z_003n.tres")
var states: Array[int] = [0,0]
var counters: Array[int] = [0,0]
var starts: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var goals: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var rounds := 0
var origin := Vector3.ZERO
var initialized := false
var intro_complete := false
var presentation: Node
var selected_part: Hurtbox
var defeat_pending := false
var death_body_finished := false
var cinematic_ticks := 0.0
var lower_rounds := 0
var intro_dig_shown := false
var burrow_warning: MeshInstance3D
var drill_buried := false

func _ready() -> void:
	super._ready()
	model.hide()
	hurtbox.set_deferred("monitorable",false)
	add_robot(0,"res://assets/enemies/boss_robot_paru/z_003u/z_003u.glb",CHANNEL0_CLIPS,4)
	add_robot(1,"res://assets/enemies/boss_robot_paru/z_003n/z_003n.glb",CHANNEL1_CLIPS,5)
	robots[0].model.position = Vector3(-6,0,0)
	robots[1].model.position = Vector3(6,0,0)
	robots[0].play([0])
	robots[1].play([1])
	presentation = preload("res://scripts/3d/enemies/robot_presentation.gd").new()
	add_child(presentation)
	_setup_drill()

func _controller_tick() -> void:
	if not initialized:
		origin = global_position
		initialized = true
	if not intro_complete:
		if not is_instance_valid(target): return
		if not presentation.active: presentation.begin(target,true)
		cinematic_ticks += 1
		for index in 2:
			robots[index].tick()
		var drill_position := robots[0].skeleton.global_transform * robots[0].skeleton.get_bone_global_pose(0).origin
		if not intro_dig_shown and drill_position.y >= origin.y:
			intro_dig_shown = true
			_spawn_dig_effect(Vector3(drill_position.x,origin.y,drill_position.z))
		if not robots[0].busy and not robots[1].busy:
			intro_complete = true
			presentation.finish()
		return
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
		9: _strafe()
		10: _approach(tick)
		11:
			var fraction := clampf(float(tick-7)/17.0,0.0,1.0)
			robots[1].model.global_position = starts[1].lerp(goals[1],fraction)
			robot_contact("1",robots[1].model.global_position,1.5,RobotAttackRules.contact(11,tick))
			if tick >= 24: _face(1)
			if Motion.followup_shot(lower_rounds,tick,_tier()):
				robot_shot(robots[1].model.global_position,_target_yaw(1))
		_: _face(1)

func _aerial(tick: int) -> void:
	var burrowing := Motion.drill_mode(rounds) == "burrow"
	var part := robots[0].model
	part.global_position = Motion.burrow_position(starts[0],goals[0],tick) if burrowing else Motion.hover_position(starts[0],goals[0],tick)
	_set_buried(burrowing and Motion.submerged(tick))
	burrow_warning.visible = burrowing and tick >= 165 and tick < 210
	burrow_warning.global_position = goals[0]+Vector3.UP*0.08
	_face(0)
	var contact := (tick == 15 or tick == 210) if burrowing else (tick >= 90 and tick < 140)
	robot_contact("0",part.global_position,2.0,contact)
	if burrowing and tick in [15,210]: _spawn_dig_effect(part.global_position)

func _approach(tick: int) -> void:
	_face(1)
	if tick >= 90 or not is_instance_valid(target): return
	var part := robots[1].model
	var direction := target.global_position-part.global_position
	direction.y = 0.0
	if direction.length() > 5.0:
		part.global_position = _arena_position(part.global_position+direction.normalized()*0.055)

func _strafe() -> void:
	_face(1)
	if lower_rounds % 3 != 2: return
	var part := robots[1].model
	var yaw := _target_yaw(1)+PI/2.0
	part.global_position = _arena_position(part.global_position+Vector3(sin(yaw),0,cos(yaw))*0.045)

func _arena_position(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x,origin.x-13,origin.x+13),origin.y,clampf(point.z,origin.z-13,origin.z+13))

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
	if index == 0:
		_set_buried(false)
		burrow_warning.hide()
	if index == 1 and state == 11: lower_rounds += 1
	states[index] = state
	counters[index] = 1 # entry reset followed by original enclosing increment
	starts[index] = robots[index].model.global_position
	var aim := target.global_position if is_instance_valid(target) else origin
	goals[index] = Vector3(clampf(aim.x,origin.x-13,origin.x+13),origin.y,clampf(aim.z,origin.z-13,origin.z+13))

func _physics_process(delta: float) -> void:
	if is_instance_valid(selected_part) and _reticle.visible:
		_reticle.global_position = selected_part.get_child(0).global_position
	if _dying:
		cinematic_ticks += delta*30.0
	super._physics_process(delta)
	if _dying:
		for index in 2: _stage_defeat_part(index)
	if _dying and death_body_finished and not robots[1].busy:
		_finish_defeat()

func _death_action() -> int:
	hide_reticle()
	_set_buried(false)
	burrow_warning.hide()
	cinematic_ticks = 0
	presentation.begin(target)
	animation_player = robots[0].player
	robots[1].play([7])
	return 6

func _accepts_damage() -> bool:
	return intro_complete and not (drill_buried and hit_part == 0) and super._accepts_damage()

func hurtbox_in_cone(point: Vector3, yaw: float, config: Dictionary) -> Dictionary:
	if not intro_complete: return {}
	return super.hurtbox_in_cone(point,yaw,config)

func show_reticle() -> void:
	# Re-scan from the player's view; companion/hit scans must not steal selection.
	var actor := _find_player()
	if not is_instance_valid(actor): return
	var config: Dictionary = CombatManager.get_weapon_type_config(actor._get_equipped_weapon_type()).duplicate()
	var tech: Dictionary = actor._get_technique_targeting()
	var reach := float(tech.get("range",0.0))
	config.hit_h_dist = maxf(float(config.get("hit_h_dist",2.4)),reach)
	var angle := rad_to_deg(atan2(float(tech.get("half_width",0.0)),maxf(reach*0.5,0.001))) if reach > 0.0 else 0.0
	if tech.get("has_zonde",false): angle = maxf(angle,25.0)
	config.hit_h_angle_deg = maxf(float(config.get("hit_h_angle_deg",30.0)),angle)
	var hit := hurtbox_in_cone(actor.global_position+Vector3.UP,float(actor.player_rotation),config)
	if hit.is_empty(): return
	selected_part = hit.hurtbox
	_reticle.global_position = selected_part.get_child(0).global_position
	super.show_reticle()

func _emit_defeat() -> void:
	defeat_pending = true

func _action_finished() -> void:
	if _dying:
		death_body_finished = true
	else:
		super._action_finished()

func _finish_defeat() -> void:
	if not defeat_pending: return
	defeat_pending = false
	presentation.finish()
	died.emit(self)
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(presentation): presentation.finish()
	super._exit_tree()

func _stage_defeat_part(index: int) -> void:
	# Retail shots contain arena-wide root travel (up to 79 units). Keep the
	# joint animation but author local root travel for this small test arena.
	var skeleton := robots[index].skeleton
	var height := 2.0 if index == 0 else 0.7055664
	height *= 1.0-clampf(cinematic_ticks/180.0,0.0,1.0)
	skeleton.set_bone_pose_position(0,Vector3(0,height,0))

func _die() -> void:
	super._die()
	# Stage the first death frame before it can be rendered.
	if _dying:
		for index in 2: _stage_defeat_part(index)

func _setup_drill() -> void:
	burrow_warning = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.7
	ring.outer_radius = 2.0
	burrow_warning.mesh = ring
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0,0.65,0.1)
	burrow_warning.material_override = material
	burrow_warning.scale.y = 0.15
	add_child(burrow_warning)
	burrow_warning.hide()

func _set_buried(buried: bool) -> void:
	drill_buried = buried
	robots[0].model.visible = not buried
	_hurt_parts[0].set_deferred("monitorable",not buried and is_alive)
	if buried and selected_part == _hurt_parts[0]: hide_reticle()

func _spawn_dig_effect(point: Vector3) -> void:
	var effect := (load("res://assets/enemies/boss_robot_paru/o0c_bsef01/o0c_bsef01.glb") as PackedScene).instantiate() as Node3D
	add_child(effect)
	effect.add_to_group("robot_dig_effects")
	effect.global_position = Vector3(point.x,origin.y+0.06,point.z)
	effect.scale = Vector3.ONE*0.3
	var tween := effect.create_tween()
	tween.tween_property(effect,"scale",Vector3.ONE,0.25)
	tween.tween_interval(0.35)
	tween.tween_property(effect,"scale",Vector3.ONE*0.02,0.25)
	tween.tween_callback(effect.queue_free)
