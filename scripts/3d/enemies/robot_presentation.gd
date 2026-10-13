extends Node
## Authored two-robot framing; recovered retail camera curves are not available.
var camera: Camera3D
var previous: Camera3D
var player: Node3D
var player_mode := Node.PROCESS_MODE_INHERIT
var active := false
var elapsed := 0.0
var hidden_huds: Dictionary = {}
var entrance := false
var entrance_position := Vector3.ZERO

func begin(actor: Node3D, entering := false) -> void:
	finish()
	if not is_instance_valid(actor): return
	entrance = entering
	player = actor
	var away: Vector3 = player.global_position-get_parent().global_position
	away.y = 0.0
	if away.is_zero_approx(): away = Vector3.BACK
	entrance_position = player.global_position+away.normalized()*6.0+Vector3.UP*4.0
	player_mode = player.process_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.push_modal()
	active = true
	var field_hud = get_tree().current_scene.get("_field_hud")
	for hud in [HudStats,field_hud]:
		if is_instance_valid(hud):
			hidden_huds[hud] = hud.visible
			hud.hide()
	elapsed = 0.0
	previous = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.fov = 60
	add_child(camera)
	_frame(0.0)
	camera.make_current()

func _process(delta: float) -> void:
	if active: _frame(delta)

func _frame(delta: float) -> void:
	elapsed += delta
	var boss := get_parent() as RobotBoss
	if entrance:
		_frame_entrance(boss)
		return
	var a := boss.robots[0].model.global_position
	var b := boss.robots[1].model.global_position
	var focus := (a+b)*0.5 + Vector3.UP*2.0
	var distance := maxf(a.distance_to(b)*0.9, 12.0)
	var angle := -0.25 + minf(elapsed,4.0)*0.1
	camera.global_position = focus + Vector3(sin(angle)*distance,distance*0.5,cos(angle)*distance)
	camera.look_at(focus)

func finish() -> void:
	if not active: return
	active = false
	GameState.pop_modal()
	for hud in hidden_huds:
		if is_instance_valid(hud): hud.visible = hidden_huds[hud]
	hidden_huds.clear()
	if is_instance_valid(player): player.process_mode = player_mode
	if is_instance_valid(previous): previous.make_current()
	if is_instance_valid(camera): camera.queue_free()
	camera = null
	player = null

func _exit_tree() -> void:
	finish()

func _frame_entrance(boss: RobotBoss) -> void:
	camera.global_position = entrance_position
	# The model origins stay at +/-6 while the skeletons fly across the arena.
	# Equal angular weight keeps the nearer robot in view as the other arrives.
	var directions: Array[Vector3] = []
	for robot in boss.robots:
		var point := robot.skeleton.global_transform * robot.skeleton.get_bone_global_pose(0).origin
		directions.append((point-camera.global_position).normalized())
	var forward := (directions[0]+directions[1]).normalized()
	if forward.is_zero_approx(): forward = -camera.global_basis.z
	camera.look_at(camera.global_position+forward)
	var separation := rad_to_deg(directions[0].angle_to(directions[1]))
	camera.fov = clampf(separation+25.0,60.0,100.0)
