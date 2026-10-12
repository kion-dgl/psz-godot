class_name OctoDiabloBoss extends DescriptorBoss
## ov21 body/limb requests plus measured 30 Hz encounter timelines.
## See docs/reyburn-octo-implementation.md for evidence and remaining spatial/capture gaps.
const SHORT_MESH = "res://assets/enemies/boss_octopus/parts/z_002_tt/z_002_tt.glb"
const LONG_MESH = "res://assets/enemies/boss_octopus/parts/z_002_st/z_002_st.glb"
const SHORT_CLIPS = preload("res://data/boss_animations/z_002_tt.tres")
const LONG_CLIPS = preload("res://data/boss_animations/z_002_st.tres")

var controller := OctoController.new()
var limbs: Array[BossModelChannel] = []
var body_state := "intro"
var body_ticks := 0
var transition_ticks := 0
var projectile_variant := 0
var projectile_roll := 0
var pending_request := 0
var limb_damage: Array[int] = [0,0,0,0,0,0]
var rng := RandomNumberGenerator.new()
var _phase_origin := Vector3.ZERO
var _origin_set := false
var _spouts_left := 0
var _timeline: Array = []
var _timeline_index := 0
var _timeline_tick := 0
var _attack_origin := Vector3.ZERO
var _attack_heading := 0.0
var _sector := 0
var _turn_from := 0.0
var _turn_to := 0.0
var _return_ticks := 0
var _death_ticks := 0
var _edge_radii: Array[float] = []
var presentation: OctoPresentation
# Captured intervals, including controller handshakes, not animation lengths.
const CENTER_SUCTION := [[12,61],[13,91],[15,21],[16,16],[17,35],[18,41],[2,181],[4,21]]
const EDGE_SUCTION := [[12,61],[13,154],[14,31],[3,151],[4,23]]

func _ready() -> void:
	super._ready()
	rng.randomize()
	for index in 6:
		var limb := BossModelChannel.new()
		var short := index < 4
		limb.setup(self,index+1,load(SHORT_MESH if short else LONG_MESH),SHORT_CLIPS if short else LONG_CLIPS,catalog.actions)
		# Authored arena-relative placement; original controller transforms TBD.
		var angle: float = [-PI/4,PI/4,-3*PI/4,3*PI/4][index] if short else (-0.8 if index == 4 else 0.8)
		limb.model.position = Vector3(sin(angle)*6.0,0,cos(angle)*6.0) if short else Vector3(-8 if index == 4 else 8,0,0)
		limb.model.rotation.y = angle if short else 0.0
		limb.model.visible = false
		limb.attack_tick.connect(_limb_attack)
		limbs.append(limb)
		# NSBMD indices 7/10 map to Point07/Point10, not GLB bone indices.
		# Sphere is still an approximation of the original joint-pair volume.
		var joint := BoneAttachment3D.new()
		joint.bone_name = "Point07" if short else "Point10"
		limb.skeleton.add_child(joint)
		var part := _register_part(joint,1.5,index+3 if short else 11+(index-4))
		part.set_deferred("monitorable",false)
		limb.play([])
	model.visible = false
	play_action(1,{0:-1})
	presentation = OctoPresentation.new()
	add_child(presentation)

func _setup_hurtbox() -> void:
	hurtbox = _register_part(self,4.0,0,Vector3(0,2,0))

func _after_damage_applied(amount: int) -> void:
	current_hp = controller.clamp_hp(current_hp,encounter_max_hp)
	controller.latch(current_hp,encounter_max_hp)
	controller.hit_count += 1
	var index := hit_part-3 if hit_part >= 3 and hit_part <= 6 else hit_part-7 if hit_part >= 7 and hit_part <= 10 else 4+(hit_part-11)%2 if hit_part >= 11 and hit_part <= 14 else -1
	if index >= 0 and index < limbs.size():
		limb_damage[index] += amount
		# 0219B878: strict > maxHP/5 only in waiting state, not every attack.
		if not limbs[index].busy and limb_damage[index] > encounter_max_hp/5:
			limb_damage[index] = 0
			limbs[index].play([24,22] if index < 4 else [45,43])

func _accepts_damage() -> bool:
	return body_state != "intro" and controller.transition_step != 14 \
		and (controller.transition_step != 18 or transition_ticks >= 30) \
		and (body_state != "spin" or body_ticks >= 120)

func _physics_process(delta: float) -> void:
	if not _dying:
		super._physics_process(delta)
		return
	_tick_fraction += delta*30.0
	while _tick_fraction >= 1.0:
		_tick_fraction -= 1.0
		_death_ticks += 1
		clock.advance(1.0/30.0)
		_sync_pose()
		for limb in limbs: limb.tick()
		if _death_ticks >= 20 and _death_ticks < 110:
			model.position.y = -float(_death_ticks-20)/12.0
		if _death_ticks == 110:
			model.visible = false
			for limb in limbs: limb.model.visible = false
		if _death_ticks >= 181:
			presentation.finish()
			presentation.clear_storm()
			queue_free()
			break

func _controller_tick() -> void:
	if not _origin_set:
		_origin_set = true
		_phase_origin = global_position
		_measure_arena_edges()
	controller.tick()
	body_ticks += 1
	_tick_limbs()
	if body_state == "intro":
		_intro_tick()
	elif not _timeline.is_empty():
		_suction_tick()
	elif body_state == "spin":
		_spin_tick()
	elif body_state == "relocate":
		_relocate_tick()
	elif body_state == "return":
		_return_ticks += 1
		global_position = _attack_origin.lerp(_phase_origin,float(_return_ticks)/25.0)
		if _return_ticks >= 25:
			_restore_limbs()
			_idle_body()
	elif controller.transition_step != 0:
		_transition_tick()
	elif body_state == "idle" and body_ticks >= 62:
		_body_boundary()
	elif body_state == "wait" and (_limbs_idle() or body_ticks > 601):
		_execute_request(pending_request)
	elif body_state == "spout" and action_id == 9:
		if _turn_step(0x200) or body_ticks >= 30:
			play_action(10)
			body_ticks = 0

func _body_boundary() -> void:
	if controller.transition_latch:
		controller.boundary(_limbs_idle())
		body_state = "transition"
		transition_ticks = 0
		play_action(1,{0:-1})
		return
	var spatial := _distance() >= 8.0 and _distance() <= 60.0 and absf(_bearing()) < PI/2
	# Single-player eligibility adapter; original four-slot flags remain unported.
	var behind := absf(_bearing()) > PI*0.6
	var request_id := controller.select_request(spatial,behind and controller.timers[1] > 300,
		0 if controller.mode == 1 and behind else -1,not _limbs_idle())
	projectile_roll = rng.randi_range(0,99)
	if request_id in [1,4]:
		_execute_request(request_id)
	else:
		pending_request = request_id
		body_state = "wait"
		body_ticks = 0
		play_action(1,{0:-1})

func _execute_request(id: int) -> void:
	body_ticks = 0
	match id:
		4:
			body_state = "spout"
			_spouts_left = {"normal":0,"hard":1,"super-hard":2}.get(SessionManager.get_session().get("difficulty","normal"),0) if controller.mode == 0 else 0
			play_action(8)
		3:
			var index := _target_limb()
			limbs[index].play([28,{"id":30,"ticks":62},29,33,{"id":26,"ticks":32},27])
			_idle_body()
		11:
			controller.timers[1] = 0
			var index := _target_limb()
			limbs[index].play([25,{"id":26,"ticks":62},38,{"id":39,"ticks":62},40,{"id":41,"ticks":62},42,27])
			_idle_body()
		12:
			controller.timers[3] = 0
			limbs[4].play([55,44])
			limbs[5].play([55,44])
			_idle_body()
		13,15:
			controller.hit_count = 0
			body_state = "relocate"
			_turn_from = float(_sector)*PI/4.0
			_sector = (_sector+1)%8
			_turn_to = _turn_from+PI/4.0
			if id == 15:
				for index in [2,3]:
					limbs[index].model.visible = true
					limbs[index].play([34,{"id":36,"ticks":79},37])
			else:
				limbs[4].play([47,44])
				limbs[5].play([48,44])
			play_action(1,{0:-1})
		17:
			body_state = "spin"
			controller.timers[1] = 0
			for index in 4:
				limbs[index].model.visible = true
				limbs[index]._idle = 26
				limbs[index].play([])
			play_action(1,{0:-1})
			_set_parts(false)
		5,6:
			controller.timers[controller.mode*2] = 0
			controller.timers[controller.mode*2+1] = 0
			body_state = "absorb"
			_attack_origin = global_position
			_attack_heading = rotation.y
			for index in (4 if controller.mode == 0 else 2):
				limbs[index if controller.mode == 0 else index+4].play([24 if controller.mode == 0 else 46])
			_timeline = (CENTER_SUCTION if controller.mode == 0 else EDGE_SUCTION).duplicate(true)
			_timeline_index = 0
			_timeline_tick = 0
			play_action(int(_timeline[0][0]),{0:-1})
		_: _idle_body()

func _idle_body() -> void:
	body_state = "idle"
	body_ticks = 0
	play_action(1,{0:-1})

func _action_finished() -> void:
	if _dying or body_state in ["intro","absorb","spin","relocate","transition","return"]:
		return
	if body_state != "spout":
		super._action_finished()
		return
	body_ticks = 0
	match action_id:
		8: play_action(9,{0:-1})
		10:
			if _spouts_left > 0 and projectile_variant != 2:
				_spouts_left -= 1
				play_action(9,{0:-1})
			else: play_action(11)
		11:
			_idle_body()
			if controller.transition_latch: _body_boundary()

func _sequence_finished() -> void:
	_idle_body()
	if controller.transition_latch: _body_boundary()

func _transition_tick() -> void:
	transition_ticks += 1
	match controller.transition_step:
		2:
			if _limbs_idle():
				controller.boundary(true)
				transition_ticks = 0
				hurtbox.set_deferred("monitorable",false)
				for index in 4: limbs[index].play([24])
		14:
			# Original withdrawal and reappearance are separate controller states.
			if transition_ticks <= 100:
				model.position.y = -minf(transition_ticks/20.0,5.0)
			if transition_ticks == 102:
				controller.change_mode()
				model.visible = false
				global_position = _edge_position(0.0)
				rotation.y = 0
				_sector = 0
				for index in 4:
					limbs[index].model.visible = false
					_hurt_parts[index+1].set_deferred("monitorable",false)
			elif transition_ticks == 103:
				controller.boundary(true)
				transition_ticks = 0
				for index in [4,5]:
					limbs[index].model.visible = index == 5
					_hurt_parts[index+1].set_deferred("monitorable",false)
				limbs[5].play([43])
				presentation.begin(target,global_position)
				limbs[4].play([])
		18:
			if transition_ticks == 30:
				limbs[4].model.visible = true
				model.visible = true
				limbs[4].play([43])
				play_action(0)
				model.position.y = 0
				hurtbox.set_deferred("monitorable",true)
			if transition_ticks >= 92:
				presentation.finish()
				controller.boundary(true)
				_idle_body()
				_set_parts(true)

func _limbs_idle() -> bool:
	return limbs.all(func(limb): return not limb.model.visible or not limb.busy)

func _boss_notification(id: int, kind: String) -> void:
	if kind != "point" or id != 0 or action_id != 10: return
	projectile_variant = OctoController.projectile_variant(controller.mode,projectile_roll)
	var angles := [-0.25,0.0,0.25] if projectile_variant == 2 else [0.0]
	for angle in angles:
		_shoot(angle,"orb",Color(0.05,0.1,0.15) if projectile_variant == 1 else Color(0.15,0.6,1.0))
		if projectile_variant == 1 and not _owned_shots.is_empty():
			_owned_shots.back().on_hit = _ink_hit

func _limb_attack(limb: BossModelChannel) -> void:
	# Limb combat is controller-owned (these descriptors have no class-0 events).
	# Slam's original allocation occurs at local update 3, ov21:0219BB84.
	if limb.action_id == 40 and limb.ticks == 3:
		_limb_contact(limb,5.0)
	# Ranged/sweep delivery remains provisional pending full subcontroller port.
	if limb.action_id == 29 and limb.ticks == 1:
		_shoot()
		if not _owned_shots.is_empty(): _owned_shots.back().global_position = _limb_tip(limb)
	if limb.action_id in [47,48] and limb.ticks == 20: _limb_contact(limb,8.0)
	# 0219CFD4: screw allocates combat 3 at 45; travel 46..64, off at 65.
	if limb.action_id == 55 and limb.ticks == 45: _limb_contact(limb,8.0)

func _limb_contact(limb: BossModelChannel, radius: float) -> void:
	if not is_instance_valid(target): return
	var offset := target.global_position-_limb_tip(limb)
	if Vector2(offset.x,offset.z).length() <= radius: _damage_target()

func _clear_deliveries() -> void:
	for limb in limbs: limb.stop()
	super._clear_deliveries()

func _death_action() -> int:
	# 0219FDB8: abscnc body pose + procedural sink, camera 3 for 181 updates.
	_timeline.clear()
	presentation.finish()
	presentation.begin(target,global_position)
	for index in [4,5]:
		if limbs[index].model.visible: limbs[index].play([45])
	return 21

func _intro_tick() -> void:
	if body_ticks == 1:
		if is_instance_valid(target):
			var toward := target.global_position-global_position
			rotation.y = atan2(toward.x,toward.z)
		presentation.begin(target,_phase_origin)
	# Original channel 2, then channel 1, then center body (0219D614).
	if body_ticks in [25,90]:
		var index := 1 if body_ticks == 25 else 0
		limbs[index].model.visible = true
		limbs[index].play([22])
		presentation.focus(limbs[index].model.global_position)
	if body_ticks in [85,150]: limbs[1 if body_ticks == 85 else 0].play([24])
	if body_ticks in [106,171]: limbs[1 if body_ticks == 106 else 0].model.visible = false
	if body_ticks == 180:
		model.visible = true
		play_action(0)
		presentation.focus(global_position+Vector3.UP*2)
	if body_ticks >= 240:
		presentation.finish()
		_restore_limbs()
		_idle_body()

func _target_limb() -> int:
	var best := 0
	var distance := INF
	if not is_instance_valid(target): return best
	for index in 4:
		var d := _limb_tip(limbs[index]).distance_squared_to(target.global_position)
		if d < distance and not limbs[index].busy:
			distance = d
			best = index
	return best

func _set_parts(enabled: bool) -> void:
	for index in _hurt_parts.size():
		_hurt_parts[index].set_deferred("monitorable",enabled and (index == 0 or limbs[index-1].model.visible))

func _restore_limbs() -> void:
	for index in limbs.size():
		limbs[index].model.visible = index < 4 if controller.mode == 0 else index >= 4
		limbs[index]._idle = (23 if index%2 == 0 else 26) if index < 4 else 44
		limbs[index].play([])
	_position_short_limbs()
	_set_parts(true)
	_set_exposure(_accepts_damage())

func _suction_tick() -> void:
	_timeline_tick += 1
	if action_id == 13: _pull_target()
	if controller.mode == 0 and action_id == 17 and _timeline_tick >= 20:
		# Measured nine-unit recoil, world transform included; spatial scale is
		# still a port adapter. Keep the original attack heading during recoil.
		global_position = _attack_origin - Vector3(sin(_attack_heading),0,cos(_attack_heading))*9.0*minf(float(_timeline_tick-19)/15.0,1.0)
	if _timeline_tick < int(_timeline[_timeline_index][1]): return
	_timeline_index += 1
	_timeline_tick = 0
	if _timeline_index >= _timeline.size():
		_timeline.clear()
		if controller.mode == 0:
			body_state = "return"
			_attack_origin = global_position
			_return_ticks = 0
			play_action(1,{0:-1})
		else:
			_restore_limbs()
			_idle_body()
		return
	play_action(int(_timeline[_timeline_index][0]),{0:-1})

func _pull_target() -> void:
	if not is_instance_valid(target): return
	if target.has_method("can_take_hit") and not target.can_take_hit(): return
	var mouth := global_position + global_basis.z*3.0
	var offset := mouth-target.global_position
	offset.y = 0
	if offset.length() > 30.0 or offset.length() < 1.0: return
	# Tuned pull below run speed; collision-aware, never teleports through planks.
	# Capture/eat/release needs a successful original trace before porting.
	var motion := offset.normalized()*0.10
	if target.has_method("_has_floor_at") and not target._has_floor_at(target.global_position+motion): return
	if target is CharacterBody3D: target.move_and_collide(motion)

func _spin_tick() -> void:
	# 0219E7CC: ramp before 30; combat 11 active [30,90), restore at 120.
	var speed := mini(body_ticks,30)*0x50
	if body_ticks > 90: speed = maxi(0,(120-body_ticks))*0x50
	rotation.y += TAU*float(speed)/65536.0
	if body_ticks >= 30 and body_ticks < 90 and not _window_hits.has(-17) and _distance() <= 17.0:
		_window_hits[-17] = true
		_damage_target()
	if body_ticks == 120: _restore_limbs()
	if body_ticks >= 164: _idle_body()

func _relocate_tick() -> void:
	# Heading sectors are recovered; arc radius/easing remain Godot adapters.
	var angle := lerpf(_turn_from,_turn_to,clampf(float(body_ticks)/120.0,0.0,1.0))
	global_position = _edge_position(angle)
	rotation.y = -angle
	if body_ticks >= 120:
		_restore_limbs()
		_idle_body()

func _ink_hit(body: Node3D) -> void:
	var tier: int = {"normal":0,"hard":1,"super-hard":2}.get(SessionManager.get_session().get("difficulty","normal"),0)
	if rng.randi_range(0,99) >= [50,100,100][tier]: return
	if body.has_method("apply_octo_poison"): body.apply_octo_poison(tier)

func _exit_tree() -> void:
	if is_instance_valid(presentation): presentation.finish()
	super._exit_tree()

func _limb_tip(limb: BossModelChannel) -> Vector3:
	var bone := limb.skeleton.find_bone("Point07" if limb.channel < 5 else "Point10")
	return limb.skeleton.global_transform * limb.skeleton.get_bone_global_pose(bone).origin

func _position_short_limbs() -> void:
	for index in 4:
		var limb := limbs[index]
		# Raised clips curl back toward their root; stretched clips reach ~17
		# units. Authored roots keep both visible above/along the plank ring.
		var radius := 6.0 if limb.action_id in [22,23,24,28,29,30,31,32] else 0.0
		var angle := limb.model.rotation.y
		limb.model.position = Vector3(sin(angle),0,cos(angle))*radius

func _tick_limbs() -> void:
	for limb in limbs:
		if limb.model.visible: limb.tick()
		if body_state == "absorb" and not limb.busy:
			limb.model.visible = false
			_hurt_parts[limb.channel].set_deferred("monitorable",false)
	_position_short_limbs()

# Find the outer plank boundary on each octagon side. Keep the body in water,
# with its front hurt volume close enough to the edge for melee.
func _measure_arena_edges() -> void:
	for sector in 8:
		var direction := Vector3(sin(sector*PI/4.0),0,-cos(sector*PI/4.0))
		var outer := 0.0
		for step in range(8,121):
			var point := _phase_origin + direction*float(step)*0.5
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*12,point-Vector3.UP*12,1,[get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and hit.normal.y > 0.7:
				outer = float(step)*0.5
		_edge_radii.append(outer+4.5 if outer > 0.0 else 26.0)

func _edge_position(angle: float) -> Vector3:
	var sector := wrapf(angle/(PI/4.0),0.0,8.0)
	var index := int(sector)
	var radius := lerpf(_edge_radii[index],_edge_radii[(index+1)%8],sector-index)
	return _phase_origin + Vector3(sin(angle),0,-cos(angle))*radius
