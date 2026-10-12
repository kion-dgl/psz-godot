extends RefCounted
## Live floor, repeated aerial deliveries and movement-coupled steering checks.
static func run(t: Node, boss: ReyburnBoss, player: Node3D) -> void:
	var launches: Array[Vector3] = []
	var observe := func(id: int):
		if id == 19: launches.append(boss.global_position)
	boss.action_started.connect(observe)
	for sequence in [9,10,11]:
		launches.clear()
		boss._clear_deliveries()
		boss.start_request({"id":sequence})
		for tick in 1800:
			boss._physics_process(1.0/30.0)
			if boss.sequence_id == -1: break
		t._check(boss.sequence_id == -1,"aerial cycle %d completes" % sequence)
		t._check(launches.size() in [2,3],"aerial cycle %d attacks two or three times" % sequence)
		t._check(boss._owned_shots.size() == launches.size(),"each aerial attack delivers a fireball")
		var relocated := launches.size() > 1
		for index in range(1,launches.size()):
			relocated = relocated and launches[index].distance_to(launches[index-1]) > 3.0
		t._check(relocated,"aerial cycle %d relocates between attacks" % sequence)
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
	t._check(boss.state_field == "air_return","off-mesh landing redirects to safe approach")
	for tick in 1800:
		boss._physics_process(1.0/30.0)
		if boss.state_field == "track": break
	var support := ReyburnFloor.sample(boss,boss.global_position)
	t._check(boss.state_field == "track" and not support.is_empty() and absf(boss.global_position.y-support.position.y) < 0.1,"off-mesh approach returns to the floor collision mesh")
	boss.global_position = valid_position
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
