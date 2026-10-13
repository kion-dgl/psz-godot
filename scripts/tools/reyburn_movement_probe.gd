extends RefCounted
## Live floor and sequence-specific aerial behavior from original captures.
static func run(t: Node, boss: ReyburnBoss, player: Node3D) -> void:
	_ground_delivery_frame(t,boss)
	_original_assets(t,boss)
	_original_takeoff(t,boss)
	await _flight(t,boss)
	_ground_turn(t,boss,player)
	await _contact_and_approach(t,boss,player)

static func _flight(t: Node, boss: ReyburnBoss) -> void:
	var launches: Array[Vector3] = []
	var observe := func(id: int):
		if id == 19: launches.append(boss.global_position)
	boss.action_started.connect(observe)
	for sequence in [9,10,11]:
		launches.clear()
		boss._clear_deliveries()
		var emitted_before := boss.deliveries.serial
		boss.start_request({"id":sequence})
		for tick in 1800:
			boss._physics_process(1.0/30.0)
			if boss.sequence_id == -1: break
		t._check(boss.sequence_id == -1,"aerial cycle %d completes" % sequence)
		var expected := 1 if sequence == 11 else 0
		t._check(launches.size() == expected,"aerial sequence %d selects only its original attack" % sequence)
		t._check(boss.deliveries.serial-emitted_before == expected,"aerial sequence %d original projectile count" % sequence)
		if sequence == 10: t._check(boss.flight.pass_index == 6,"enhanced aerial spin completes six paths")
		var floor_hit := ReyburnFloor.sample(boss,boss.global_position)
		t._check(not floor_hit.is_empty() and absf(boss.global_position.y-floor_hit.position.y) < 0.1,"aerial cycle %d lands on supported floor" % sequence)
		await t.get_tree().physics_frame
	boss.action_started.disconnect(observe)
	# Reject an off-mesh landing, then fly back before beginning descent.
	var valid_position := boss.global_position
	boss.global_position += Vector3(100,8,0)
	boss._states.clear()
	boss.state_field = "0xe4"
	boss._state_ticks = 0
	boss._land()
	t._check(not ReyburnFloor.sample(boss,boss.flight.landing_point).is_empty(),"off-mesh landing chooses supported destination")
	for tick in 1800:
		boss._physics_process(1.0/30.0)
		if boss.state_field == "track": break
	var support := ReyburnFloor.sample(boss,boss.global_position)
	t._check(boss.state_field == "track" and not support.is_empty() and absf(boss.global_position.y-support.position.y) < 0.1,"off-mesh approach returns to the floor collision mesh")
	boss.global_position = valid_position

static func _ground_turn(t: Node, boss: ReyburnBoss, player: Node3D) -> void:
	boss.rotation.y = 0
	player.global_position = boss.global_position + Vector3(0,0,-15)
	boss.ground_motion.reset()
	var coupled := true
	var bounded := true
	var distance := 0.0
	for tick in 60:
		var position_before := boss.global_position
		var yaw_before := boss.rotation.y
		boss.ground_motion.step(boss,4.0)
		var traveled := boss.global_position.distance_to(position_before)
		var turn := absf(wrapf(boss.rotation.y-yaw_before,-PI,PI))
		coupled = coupled and (turn < 0.00001 or traveled > 0.00001)
		bounded = bounded and turn <= deg_to_rad(32.0)/30.0+0.00001
		distance += traveled
	t._check(coupled and bounded and distance > 1.0,"ground pursuit moves while turning at a bounded rate")
	boss._clear_deliveries()

static func _contact_and_approach(t: Node, boss: ReyburnBoss, player: Node3D) -> void:
	# A body raised above uneven ground must settle to the sampled mesh.
	boss.global_position.y += 1.0
	boss.ground_motion.step(boss,4.0)
	var floor_after := ReyburnFloor.sample(boss,boss.global_position)
	t._check(not floor_after.is_empty() and absf(boss.global_position.y-floor_after.position.y) < 0.01,"ground locomotion follows floor height instead of hovering")
	var player_position := player.global_position
	player.global_position = boss.global_position + Vector3(0,0.2,8)
	boss.force_update_transform()
	player.force_update_transform()
	await t.get_tree().process_frame
	var collision: KinematicCollision3D = player.move_and_collide(Vector3(0,0,-10))
	t._check(collision != null and collision.get_collider() == boss and collision.get_travel().length() < 10.0,"player movement collides with Reyburn torso")
	player.global_position = boss.global_position + Vector3(0,0,1.5)
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0.0
	var hp := GameState.hp
	for action in [5,6]:
		boss.play_action(action,{0:-1})
		for tick in 180: boss.clock.advance(1.0/30.0)
	t._check(GameState.hp == hp,"ordinary walk and run windows cannot chain damage")
	player.current_state = player.PlayerState.DODGING
	player.dodge_timer = 0.0
	boss.rotation.y = 0
	player.global_position = boss.global_position + Vector3(0,0,24)
	boss.controller.breath_timer = 0
	boss.approach.begin(boss)
	t._check(boss.approach.tick(boss).id == 6,"valid vantage commits to fireball without extra walking")
	player.global_position = boss.global_position + Vector3(0,0,-10)
	boss.approach.begin(boss)
	var request := {"id":-1}
	for tick in 210:
		request = boss.approach.tick(boss)
		if int(request.id) >= 0: break
	t._check(int(request.id) >= 0,"denied firing angle cannot cause endless repositioning")
	boss.approach.reset()
	player.global_position = player_position
	boss._clear_deliveries()

static func _original_takeoff(t: Node, boss: ReyburnBoss) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/reyburn_parity.json"))
	var fixture: Dictionary = data.takeoff_fixture
	var original: Vector3 = boss.global_position
	var enhanced := boss.controller.enhanced
	boss.controller.enhanced = false
	var p: Array = fixture.positions_raw[0]
	boss.global_position = boss.get_parent().global_transform*(Vector3(p[0],p[1],p[2])/4096.0)
	boss.rotation.y = float(fixture.facing_raw)*TAU/65536.0
	boss.start_request({"id":9,"entry_side":0,"landing":Vector3.ZERO})
	var measured: Array[Vector3] = []
	for tick in 500:
		measured.append(boss.flight.local_position(boss))
		boss._physics_process(1.0/30.0)
		if boss.state_field != "0xdc": break
	var worst := 0.0
	for i in mini(measured.size(),fixture.positions_raw.size()):
		var q: Array = fixture.positions_raw[i]
		worst = maxf(worst,measured[i].distance_to(Vector3(q[0],q[1],q[2])/4096.0))
	print("[reyburn-original] takeoff duration Godot=%d original=%d max aligned position error=%f" % [measured.size(),fixture.positions_raw.size(),worst])
	t._check(boss.state_field == "0xe0","original takeoff exits into end reentry")
	t._check(measured.size() == fixture.positions_raw.size(),"whole original takeoff duration matches 266 updates")
	t._check(worst < 0.02,"whole original takeoff stays within 0.02 world units")
	boss.global_position = original
	boss.controller.enhanced = enhanced
	boss._states.clear()
	boss._enter_next_state()

static func _original_assets(t: Node, boss: ReyburnBoss) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/reyburn_parity.json"))
	for clip: String in data.animation_inventory.slots:
		t._check(boss.animation_player.has_animation(clip.get_basename()),"original body clip available: "+clip)

static func _ground_delivery_frame(t: Node, boss: ReyburnBoss) -> void:
	# A non-origin mission room must not immediately expire its first ground shots.
	var parent := boss.get_parent() as Node3D
	var previous := parent.position
	parent.position.x += 128.0
	boss._initialized_position = false
	boss._clear_deliveries()
	var serial := boss.deliveries.serial
	boss.start_request({"id":6,"types":[0],"counts":[1]})
	for tick in 180:
		boss._physics_process(1.0/30.0)
		if boss.deliveries.serial > serial: break
	for tick in 3: boss.deliveries.tick(boss)
	var flying := boss.deliveries.shots.size() == 3
	for shot: Dictionary in boss.deliveries.shots: flying = flying and shot.impact == -1
	t._check(flying,"translated arena keeps first ground fan inside arena-local bounds")
	boss._clear_deliveries()
	parent.position = previous
	boss._initialized_position = false
	boss._states.clear()
	boss._enter_next_state()
	boss._physics_process(1.0/30.0)
