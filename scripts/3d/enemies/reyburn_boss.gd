class_name ReyburnBoss extends DescriptorBoss
## Recovered ov20 sequences and damage history. Motion adapters are documented
## in /states/reyburn-octo; no fixed-percent enrage or percent-of-clip damage.

@export var original_ground_pacing := true
var deliveries := ReyburnDeliveries.new()
var _breath_ready := false

var entrance := ReyburnEntrance.new()
var pacing := ReyburnPacing.new()
var flight := ReyburnFlight.new()
var ground_motion := ReyburnMotion.new()
var approach := ReyburnApproach.new()

var controller: ReyburnController
var sequence_id := -1
var state_field := ""
var request: Dictionary = {}
var _states: Array = []
var _state_ticks := 0
var _state_limit := 0
var _breath_cursor := 0
var _breath_type := 0
var _shots_left := 0
var _shot_wait := -1
var _ground_height := 0.0
var _motion_start := Vector3.ZERO
var _motion_end := Vector3.ZERO
var _jump_ticks := -1
var _tail_heading := 0.0
var _part_broken := false
var _bite_pending := false
var _bite_complete := false
var _horn: Node3D
var _skeleton: Skeleton3D
var _home := Vector3.ZERO
var _initialized_position := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	super._ready()
	set_collision_layer_value(7,true)
	# Keep the solid torso full-width down to the floor rather than tapering
	# to a point at the bottom of the large capsule.
	for child in get_children():
		if child is CollisionShape3D:
			var torso := CylinderShape3D.new()
			torso.radius = enemy_data.collision_radius
			torso.height = enemy_data.collision_height
			child.shape = torso
			child.position.y = torso.height/2.0
	rng.randomize()
	var tier: int = {"normal":0,"hard":1,"super-hard":2}.get(SessionManager.get_session().get("difficulty","normal"),0)
	controller = ReyburnController.new(int(catalog.stats[tier][0]),encounter_max_hp)
	_skeleton = NodeUtils.first_of_type(model,"Skeleton3D") as Skeleton3D if model else null
	_attach_horn()
	_set_exposure(false)

func _attach_horn() -> void:
	# Original model channel 1 is mode 2, parent channel 0, raw joint 12 (atama).
	if not _skeleton or _skeleton.find_bone("atama") < 0: return
	var mesh := load("res://assets/enemies/boss_dragon/parts/z_001_horn/z_001_horn.glb") as PackedScene
	if not mesh: return
	var anchor := BoneAttachment3D.new()
	_skeleton.add_child(anchor)
	anchor.bone_name = "atama"
	_horn = mesh.instantiate()
	anchor.add_child(_horn)

func _physics_process(delta: float) -> void:
	if entrance != null:
		if dormant: return
		if entrance.tick(self, delta):
			entrance = null
			controller.finish(0)
			_states.clear()
			_enter_next_state()
		return
	if is_alive and not dormant: pacing.check_target(self)
	super._physics_process(delta)

func _accepts_damage() -> bool:
	return entrance == null

func _combat_event(record: Dictionary) -> void:
	# Walking/running is repositioning, not a repeatable full-strength attack.
	if action_id in [5,6]: return
	if entrance == null and not pacing.target_defeated(target): super._combat_event(record)

func _die() -> void:
	if entrance != null:
		entrance.finish(self)
		entrance = null
	super._die()

func _exit_tree() -> void:
	deliveries.clear()
	if entrance != null: entrance.finish(self)
	super._exit_tree()

func _setup_hurtbox() -> void:
	var skeleton := NodeUtils.first_of_type(model,"Skeleton3D") as Skeleton3D if model else null
	var parts := [[3.5,"",Vector3.ZERO],[4.0,"atama",Vector3(0,-0.5,0)],
		[0.75,"atama",Vector3(0,-0.5,0)],[1.0,"sippo_02",Vector3.ZERO]]
	for index in parts.size():
		var part: Array = parts[index]
		var anchor: Node3D = self
		if skeleton and not str(part[1]).is_empty() and skeleton.find_bone(part[1]) >= 0:
			var attachment := BoneAttachment3D.new()
			skeleton.add_child(attachment)
			attachment.bone_name = part[1]
			anchor = attachment
		var hb := _register_part(anchor,float(part[0]),index,part[2])
		if index == 0: hurtbox = hb

func _after_damage_applied(amount: int) -> void:
	var bearing := 0.0
	var known := is_instance_valid(hit_source) and hit_source != self
	if known:
		var direction := hit_source.global_position - global_position
		bearing = wrapf(atan2(direction.x,direction.z) - rotation.y,-PI,PI)
	if controller.hit(amount,hit_part,bearing,known):
		_part_broken = true
		if is_instance_valid(_horn): _horn.hide()

func start_request(value: Dictionary) -> void:
	if entrance != null:
		entrance.finish(self)
		entrance = null
	request = value.duplicate(true)
	sequence_id = int(request.id)
	_states = _reyburn_sequences[sequence_id].duplicate()
	ground_motion.reset()
	approach.reset()
	deliveries.reset_contact()
	if sequence_id in [9,10,11]:
		flight.begin(self)
		if not request.has("entry_side"): request.entry_side = rng.randi_range(0,1)
		if not request.has("landing"): request.landing = Vector3(float(rng.randi_range(0,0xbfff)-0x6000)/4096.0,0,float(rng.randi_range(0,0x21fff)-0x11000)/4096.0)
	_breath_cursor = 0
	_enter_next_state()

func _enter_next_state() -> void:
	if _states.is_empty():
		ground_motion.reset()
		approach.reset()
		pacing.completed(sequence_id)
		if original_ground_pacing: pacing.rest_ticks = 0; pacing.bite_ticks = 0
		controller.finish(sequence_id,int(request.get("flags",0)),sequence_id in [8,14] and controller.enhanced and rng.randi_range(0,1) == 1)
		sequence_id = -1
		state_field = "track"
		_state_ticks = 0
		play_action(4,{0:-1})
		return
	_sequence.clear()
	state_field = str(_states.pop_front())
	_state_ticks = 0
	_state_limit = 0
	var entries := {
		"0xcc":_intro,"0xdc":_takeoff,"0xe0":_aerial,"0xe4":_land,"air_return":_air_return,
		"0xe8":_claw,"0xec":_aerial_turn,"0xf0":_breath,"0xf4":_bite,
		"0xf8":_wing,"0xfc":_roar,"0x100":_run,"0x108":_air_breath,
		"0x10c":_turn,"0x110":_modifier,"0x114":_jump,"0x118":_tail,"0xd4":_reaction}
	entries[state_field].call()

func _controller_tick() -> void:
	if state_field == "loaf": return
	deliveries.tick(self)
	pacing.tick()
	if not _initialized_position:
		_initialized_position = true
		_home = global_position
		_ground_height = global_position.y
	controller.tick()
	_state_ticks += 1
	if state_field == "track":
		_track()
	elif state_field == "0x10c":
		_tick_turn()
	elif state_field in ["0xdc","0xe0","0xe8","0xec","0x108","0xe4","air_return"]:
		flight.tick(self)
	elif state_field == "0xf0":
		_tick_breath()
	elif state_field == "0xf4":
		_tick_bite()
	elif state_field == "0x118" and not clock.running:
		if _state_ticks >= _state_limit: _enter_next_state()
	elif state_field == "0x114":
		_tick_jump()
	elif _state_limit > 0 and _state_ticks >= _state_limit:
		_enter_next_state()
	_tick_motion()

func _tick_turn() -> void:
	if original_ground_pacing:
		var maximum := int(request.get("turn",0x222))
		var turn := roundi(maximum*sin(minf(float(_state_ticks)/90.0,1.0)*PI))
		if absf(_bearing()) <= TAU*turn/65536.0 or _state_ticks >= 90: _enter_next_state()
		else: _turn_step(turn)
	elif absf(_bearing()) < 0.12 or ground_motion.step(self,2.4):
		ground_motion.reset()
		_enter_next_state()
	elif _state_ticks >= 240:
		_states.clear()
		_enter_next_state()

func _track() -> void:
	if original_ground_pacing:
		_track_original()
		return
	if pacing.rest_ticks > 0: return
	if approach.active:
		var next: Dictionary = approach.tick(self)
		if int(next.id) >= 0: start_request(next)
		return
	var chosen := {"id":-1}
	if _part_broken:
		_part_broken = false
		chosen = {"id":12}
	elif controller.flight_timer <= 0:
		chosen = {"id":(10 if controller.enhanced else 9) if controller.aerial_alternation else 11,"flags":3}
	elif controller.fallback_timer <= 0:
		var roll := rng.randi_range(0,3)
		var secondary := rng.randi_range(0,1) if roll == 0 or (roll == 2 and controller.enhanced) else 0
		chosen = controller.fallback(roll,secondary,pacing.bite_ticks <= 0)
	else:
		chosen = controller.priority(_distance(),_bearing(),pacing.bite_ticks <= 0)
	if int(chosen.id) >= 0:
		start_request(chosen)
	else:
		approach.begin(self)
		var next: Dictionary = approach.tick(self)
		if int(next.id) >= 0: start_request(next)

func _track_original() -> void:
	var chosen := {"id":-1}
	if _part_broken:
		_part_broken = false
		chosen = {"id":12}
	elif controller.flight_timer <= 0:
		chosen = controller.flight_request()
	elif controller.fallback_timer <= 0:
		var roll := rng.randi_range(0,3)
		var secondary := rng.randi_range(0,1) if roll == 0 or (roll == 2 and controller.enhanced) else 0
		chosen = controller.fallback(roll,secondary)
	else:
		chosen = controller.priority(_distance(),_bearing())
	if chosen.get("breath_choice",false): chosen = controller.breath_request(rng.randi_range(0,1))
	if int(chosen.id) >= 0:
		start_request(chosen)
	else:
		if action_id != 5: play_action(5,{0:-1})
		ground_motion.retail_step(self)

func _clear_deliveries() -> void:
	deliveries.clear()
	super._clear_deliveries()

func _intro() -> void:
	# Intro camera/arena approach is a bounded adapter, not retail spawn motion.
	play_sequence([7,18])

func _takeoff() -> void:
	flight.takeoff(self)

func _aerial() -> void:
	flight.move(self)

func _air_return() -> void:
	flight.move(self,true)

func _land() -> void:
	flight.land(self)

func _claw() -> void:
	flight.claw(self)

func _aerial_turn() -> void:
	flight.spin(self)

func _breath() -> void:
	var types: Array = request.get("types",[0])
	var counts: Array = request.get("counts",[1])
	_breath_type = int(types[mini(_breath_cursor,types.size()-1)])
	_shots_left = int(counts[mini(_breath_cursor,counts.size()-1)])
	_breath_cursor += 1
	_shot_wait = -1
	_breath_ready = false
	play_action(10)

func _bite() -> void:
	_bite_pending = false
	_bite_complete = false
	var actions: Array = []
	for i in int(request.get("normal",1)): actions.append(16)
	for i in int(request.get("advance",0)): actions.append(17)
	actions.append(4)
	play_sequence(actions)

func _wing() -> void:
	_state_limit = int(request.get("duration",150))
	play_action(13,{0:-1})

func _roar() -> void:
	play_action(1)

func _run() -> void:
	_state_limit = int(request.get("duration",150))
	play_action(6,{0:-1})

func _air_breath() -> void:
	flight.air_breath(self)

func _turn() -> void:
	play_action(5,{0:-1})

func _modifier() -> void:
	play_action(2)

func _reaction() -> void:
	play_action(3)

func _jump() -> void:
	_motion_start = global_position
	_motion_end = global_position - global_basis.z * 12.0
	var floor_hit := ReyburnFloor.landing(self,_motion_end)
	_motion_end = floor_hit.get("position",global_position)
	_jump_ticks = -1
	play_action(7,{1:-1})

func _tail() -> void:
	_tail_heading = rotation.y + PI
	play_action(14 if _bearing() >= 0 else 15)

func _tick_breath() -> void:
	if action_id == 11 and _state_ticks >= (1 if _breath_type == 0 else 2):
		play_action(12)
	if _breath_ready:
		_breath_ready = false
		_emit_breath()
		return
	if _shot_wait >= 0:
		_shot_wait -= 1
		if _shot_wait < 0 and _shots_left > 0: _emit_breath()

func _tick_jump() -> void:
	if _jump_ticks < 0: return
	_jump_ticks += 1
	var progress := minf(float(_jump_ticks)/75.0,1.0)
	global_position = _motion_start.lerp(_motion_end,(1.0-cos(progress*PI))*0.5)
	global_position.y += sin(progress*PI)*3.0
	if _jump_ticks == 32: play_action(8)
	if _jump_ticks >= 75 and not clock.running: _enter_next_state()

func _tick_motion() -> void:
	match state_field:
		"0x100": ground_motion.step(self,8.0)
		"0xf4":
			# Translational adapter until original flagged root curves are transferred.
			if action_id == 17 and clock.frame_q12 >= 10*4096 and clock.frame_q12 <= 37*4096:
				var next_position := global_position + global_basis.z * (6.0/30.0)
				if not ReyburnFloor.sample(self,next_position).is_empty(): _move_forward(6.0)

func _action_finished() -> void:
	if entrance != null: return
	if _dying:
		super._action_finished()
		return
	if state_field in ["0xdc","0xe0","0xe8","0xec","0x108","0xe4","air_return"]: return
	if state_field == "0xf0":
		if action_id == 10:
			_state_ticks = 0
			play_action(11,{0:-1})
		elif action_id == 12: _enter_next_state()
	elif state_field == "0xf4":
		_bite_pending = true
	elif state_field == "0x114":
		pass # Jump finishes only after both interpolation and landing animation.
	elif state_field == "0x118":
		rotation.y = _tail_heading
		_state_limit = _state_ticks + 30
	else:
		super._action_finished()

func _sequence_finished() -> void:
	_enter_next_state()

func _boss_notification(id: int, kind: String) -> void:
	if entrance != null: return
	if kind != "point": return
	controller.notify(id)
	if id == 2 and state_field == "0x114": _jump_ticks = 0
	if id == 2 and state_field == "0xdc": flight.released = true
	if id == 4 and state_field == "0xf0": _breath_ready = true
	if id == 4 and state_field == "0x108": flight.released = true

func _emit_breath() -> void:
	if _shots_left <= 0: return
	_fire(0.0)
	if _breath_type == 0:
		_fire(TAU * 0x0e38 / 65536.0)
		_fire(-TAU * 0x0e38 / 65536.0)
	_shots_left -= 1
	_shot_wait = 8 if _shots_left > 0 else -1

func _fire(angle: float) -> void:
	deliveries.launch(self,angle,_breath_type,state_field == "0x108")

func _damage_target() -> void:
	if is_alive and is_instance_valid(target) and not pacing.target_defeated(target) and target.has_method("take_damage"):
		target.take_damage(int(_attack_damage({}) * (1.5 if controller.enhanced else 1.0)))

func _death_action() -> int:
	return 9

func _event_anchor(event: Dictionary) -> Transform3D:
	# The GLB converter reorders joints: raw NSBMD indices are NOT bone indices.
	var names := {12:"atama",18:"sippo_02"}
	var bone: String = names.get(int(event.get("joint_index",-1)),"")
	if int(event.get("coordinate_mode",0)) == 2 and _skeleton and not bone.is_empty():
		var index := _skeleton.find_bone(bone)
		if index >= 0: return _skeleton.global_transform * _skeleton.get_bone_global_pose(index)
	return global_transform

func _tick_bite() -> void:
	# ov20:0219D1D4 returns through substate zero for one update between bites.
	if _bite_complete:
		_enter_next_state()
	elif _bite_pending:
		_bite_pending = false
		_next_action()
		_bite_complete = action_id == 4
