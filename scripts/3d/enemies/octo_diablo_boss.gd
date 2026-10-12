class_name OctoDiabloBoss extends DescriptorBoss
## ov21 body and six independent limb channels. Capture/escape semantics and
## retail arena transforms remain explicit parity gaps; see /states/reyburn-octo.
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

func _ready() -> void:
	super._ready()
	rng.randomize()
	for index in 6:
		var limb := BossModelChannel.new()
		var short := index < 4
		limb.setup(self,index+1,load(SHORT_MESH if short else LONG_MESH),SHORT_CLIPS if short else LONG_CLIPS,catalog.actions)
		# Authored arena-relative placement; original controller transforms TBD.
		var angle := TAU * (index+0.5) / 4.0 if short else (-0.8 if index == 4 else 0.8)
		limb.model.position = Vector3(sin(angle)*9.0,0,cos(angle)*9.0) if short else Vector3(-10 if index == 4 else 10,0,8)
		limb.model.rotation.y = angle + PI if short else 0.0
		limb.model.visible = short
		limb.attack_tick.connect(_limb_attack)
		limbs.append(limb)
		var part := _register_part(limb.model,2.0,index+1 if short else 11+(index-4)*2,Vector3(0,1,0))
		part.set_deferred("monitorable",short)
		limb.play([22] if short else [])
	play_sequence([0,1])

func _setup_hurtbox() -> void:
	hurtbox = _register_part(self,4.0,0,Vector3(0,2,0))

func _after_damage_applied(amount: int) -> void:
	current_hp = controller.clamp_hp(current_hp,encounter_max_hp)
	controller.latch(current_hp,encounter_max_hp)
	controller.hit_count += 1
	var index := hit_part-1 if hit_part >= 1 and hit_part <= 4 else 4+(hit_part-11)/2 if hit_part >= 11 else -1
	if index >= 0 and index < limbs.size():
		limb_damage[index] += amount
		# Provisional per-limb break budget; retail per-part routing is recovered,
		# but its difficulty-sensitive budget is not yet ported.
		if limb_damage[index] >= maxi(1,encounter_max_hp/10):
			limb_damage[index] = 0
			limbs[index].play([24,22] if index < 4 else [45])

func _controller_tick() -> void:
	if not _origin_set:
		_origin_set = true
		_phase_origin = global_position
	controller.tick()
	body_ticks += 1
	for limb in limbs:
		if limb.model.visible: limb.tick()
	if controller.transition_step != 0:
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
	var request_id := controller.select_request(spatial,false,-1,not _limbs_idle())
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
		3,17:
			for index in 2: limbs[index].play([28,{"id":30,"ticks":62},29,33,{"id":26,"ticks":32},27])
			_idle_body()
		11:
			controller.timers[1] = 0
			for index in 4: limbs[index].play([25,{"id":26,"ticks":62},38,{"id":39,"ticks":62},40,{"id":41,"ticks":62},42,27])
			_idle_body()
		12,13,15:
			if id == 12: controller.timers[3] = 0
			if id == 13: controller.hit_count = 0
			limbs[4].play([55 if id == 13 else 47,44])
			limbs[5].play([55 if id == 13 else 48,44])
			_idle_body()
		5,6:
			controller.timers[controller.mode*2] = 0
			controller.timers[controller.mode*2+1] = 0
			body_state = "absorb"
			play_sequence([12,{"id":13,"loops":{0:3}},15,{"id":16,"loops":{0:3}},17,4])
		_: _idle_body()

func _idle_body() -> void:
	body_state = "idle"
	body_ticks = 0
	play_action(1,{0:-1})

func _action_finished() -> void:
	if _dying:
		super._action_finished()
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
				global_position = _phase_origin + Vector3(0,0,-25)
				for index in 4:
					limbs[index].model.visible = false
					_hurt_parts[index+1].set_deferred("monitorable",false)
			elif transition_ticks == 103:
				controller.boundary(true)
				transition_ticks = 0
				for index in [4,5]:
					limbs[index].model.visible = true
					_hurt_parts[index+1].set_deferred("monitorable",true)
				limbs[5].play([43])
				limbs[4].play([])
		18:
			if transition_ticks == 30:
				limbs[4].play([43])
				play_action(0)
				model.position.y = 0
				hurtbox.set_deferred("monitorable",true)
			if transition_ticks >= 92:
				controller.boundary(true)
				_idle_body()

func _limbs_idle() -> bool:
	return limbs.all(func(limb): return not limb.model.visible or not limb.busy)

func _boss_notification(id: int, kind: String) -> void:
	if kind != "point" or id != 0 or action_id != 10: return
	projectile_variant = OctoController.projectile_variant(controller.mode,projectile_roll)
	var angles := [-0.25,0.0,0.25] if projectile_variant == 2 else [0.0]
	for angle in angles:
		_shoot(angle,"orb",Color(0.05,0.1,0.15) if projectile_variant == 1 else Color(0.15,0.6,1.0))

func _limb_attack(limb: BossModelChannel) -> void:
	# Limb combat is controller-owned (these descriptors have no class-0 events).
	# Slam's original allocation occurs at local update 3, ov21:0219BB84.
	if limb.action_id == 40 and limb.ticks == 3:
		_limb_contact(limb,5.0)
	# Ranged/sweep delivery remains provisional pending full subcontroller port.
	if limb.action_id == 29 and limb.ticks == 1:
		_shoot()
		if not _owned_shots.is_empty(): _owned_shots.back().global_position = limb.model.global_position + Vector3.UP
	if limb.action_id in [47,48,55] and limb.ticks == 20: _limb_contact(limb,8.0)

func _limb_contact(limb: BossModelChannel, radius: float) -> void:
	if not is_instance_valid(target): return
	var offset := target.global_position-limb.model.global_position
	if Vector2(offset.x,offset.z).length() <= radius: _damage_target()

func _clear_deliveries() -> void:
	for limb in limbs: limb.stop()
	super._clear_deliveries()

func _death_action() -> int:
	# No body death descriptor; sink the existing damage pose before freeing.
	return 7
