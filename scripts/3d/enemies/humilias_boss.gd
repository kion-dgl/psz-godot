class_name HumiliasBoss extends RobotBoss
## ov22 combined action families, HP-gated split and paired return.
## Attack selection, motion, collision geometry/status payloads remain partial.
var mode := "intro"
var request := ""
var ticks := 0
var active_ticks := 0
var floor_ticks := 0
var split_count := 0
var attack_round := 0
var split_origin := Vector3.ZERO
var split_starts: Array[Vector3] = []
var grid: RobotFloorGrid
var _shot_serial := -1
var _floor_hits: Dictionary = {}
var _arena_set := false

func _setup_model() -> void:
	# The asset pack stored the combined NARC mesh under boss_robot.
	var scene := load("res://assets/enemies/boss_robot/boss_robot.glb") as PackedScene
	var body := scene.instantiate()
	body.name = "Model"
	add_child(body)
	super._setup_model()

func _ready() -> void:
	super._ready()
	add_robot(0,"res://assets/enemies/boss_robot/parts/z_103u/z_103u.glb",null,4)
	add_robot(1,"res://assets/enemies/boss_robot/parts/z_003n/z_003n.glb",null,5)
	grid = RobotFloorGrid.new()
	add_child(grid)
	grid.top_level = true
	_split_visibility(true)
	robots[0].play([2])
	robots[1].play([3])

func _controller_tick() -> void:
	if not _arena_set:
		grid.global_position = Vector3(0,global_position.y,0)
		_arena_set = true
	ticks += 1
	grid.advance()
	_floor_contact()
	if mode != "combined":
		_parts_tick()
		return
	active_ticks = mini(active_ticks+1,int(HumiliasRules.DATA.data.parameters[_tier()][5])*30)
	floor_ticks += 1
	if request.is_empty():
		_idle_tick()
	else:
		_attack_tick()

func _idle_tick() -> void:
	_turn_step(0x400)
	if ticks < RobotAttackRules.parameters(current_hp,encounter_max_hp,_tier())[0]: return
	if HumiliasRules.split_due(split_count,active_ticks,current_hp,encounter_max_hp,_tier()):
		_start_split()
		return
	if floor_ticks >= int(HumiliasRules.DATA.data.parameters[_tier()][5])*30:
		floor_ticks = 0
		var row := attack_round%3
		grid.pulse([row*3,row*3+1,row*3+2])
	if _distance() > 9.0:
		_start("move",[17,{"id":18,"loops":{0:-1}}])
	else:
		var selection := attack_round%5
		attack_round += 1
		match selection:
			0: _start("gun",[24,25,26])
			1: _start("sweep",[35,{"id":36,"loops":{0:-1}}])
			2: _start("drill",[27,28,{"id":29,"loops":{0:-1}}])
			3: _start("gun",[21,22,23])
			4: _start("drill",[31,32,{"id":33,"loops":{0:-1}}])

func _attack_tick() -> void:
	match request:
		"move":
			_turn_step(0x400)
			if action_id == 18:
				_move_forward(3.5)
				if _distance() <= 8.0 or ticks >= 180: play_action(19)
		"gun":
			if action_id in [21,24]: _turn_step(0x400)
			if action_id in [22,25] and clock.frame_q12 >= 2*4096 and _shot_serial != _action_serial:
				_shot_serial = _action_serial
				robot_shot(global_position,rotation.y)
		"sweep":
			if action_id == 36:
				_turn_step(0x400)
				if ticks >= 71: play_sequence([37,38])
			robot_contact("sweep",global_position+global_basis.z*3,5.0,action_id == 37 and clock.frame_q12 >= 8*4096)
		"drill":
			var hold_end := 67 + int(HumiliasRules.DATA.data.parameters[_tier()][2])
			if action_id in [29,33] and ticks >= hold_end: play_action(30 if action_id == 29 else 34)
			robot_contact("drill",global_position+global_basis.z*3,2.0,ticks >= 52 and ticks < 67)

func _start(kind: String, actions: Array) -> void:
	request = kind
	ticks = 0
	play_sequence(actions)

func _sequence_finished() -> void:
	if request == "drill" and action_id == 29: return # nonloop hold pose, controller releases it
	request = ""
	ticks = 0
	play_action(16,{0:-1})

func _parts_tick() -> void:
	for part in robots: part.tick()
	match mode:
		"intro":
			if _parts_done(): _join()
		"splitting":
			if _parts_done():
				mode = "split"
				ticks = 0
		"split":
			_split_attack()
			if ticks >= HumiliasRules.split_duration(_tier()): _join()
		"join_move":
			for i in 2: robots[i].model.global_position = split_starts[i].lerp(global_position,ticks/30.0)
			if ticks >= 30:
				mode = "joining"
				robots[0].play([12])
				robots[1].play([13])
		"joining":
			if _parts_done():
				mode = "combined"
				_split_visibility(false)
				_sequence_finished()

func _parts_done() -> bool:
	return not robots[0].busy and not robots[1].busy

func _start_split() -> void:
	split_count += 1
	active_ticks = 0
	ticks = 0
	mode = "splitting"
	request = ""
	clock.cancel()
	_sequence.clear()
	contact_hits.clear()
	split_origin = global_position
	for part in robots:
		part.model.position = Vector3.ZERO
		part.model.rotation = Vector3.ZERO
	_split_visibility(true)
	robots[0].play([14])
	robots[1].play([15])

func _split_attack() -> void:
	# Recovered 149/54-tick primitive windows; movement/selection are adapters.
	var aim := target.global_position if is_instance_valid(target) else split_origin
	for i in 2:
		var period := 204 if i == 0 else 174
		var step := ticks%period
		var duration := 149 if i == 0 else 54
		var idle := period-duration
		var part := robots[i].model
		if step <= idle:
			part.rotation.y = lerp_angle(part.rotation.y,atan2(aim.x-part.global_position.x,aim.z-part.global_position.z),0.1)
		else:
			var attack_tick := step-idle
			var state := 13 if i == 0 else 11
			var active := RobotAttackRules.contact(state,attack_tick)
			if active:
				var motion := part.global_basis.z * 0.3
				var candidate := part.global_position+motion
				if candidate.distance_to(split_origin) < 18.0: part.global_position = candidate
			robot_contact("part%d"%i,part.global_position,1.5,active)

func _join() -> void:
	mode = "join_move"
	ticks = 0
	contact_hits.clear()
	split_starts = [robots[0].model.global_position,robots[1].model.global_position]

func _split_visibility(split: bool) -> void:
	model.visible = not split
	hurtbox.set_deferred("monitorable",not split)
	for i in 2:
		robots[i].model.visible = split
		_hurt_parts[i+1].set_deferred("monitorable",split)

func _setup_hurtbox() -> void:
	hurtbox = _register_part(self,3.0,2,Vector3(0,2,0))

func _floor_contact() -> void:
	for index in 9:
		if not grid.damaging(index): _floor_hits.erase(index)
	if not is_instance_valid(target): return
	var cell := grid.cell_at(target.global_position)
	if cell >= 0 and grid.damaging(cell) and not _floor_hits.has(cell):
		_floor_hits[cell] = true
		_damage_target()

func _clear_deliveries() -> void:
	super._clear_deliveries()
	if is_instance_valid(grid): grid.stop()
	_floor_hits.clear()

func _death_action() -> int:
	model.hide()
	for part in robots:
		part.model.position = Vector3.ZERO
		part.model.rotation = Vector3.ZERO
		part.model.show()
	animation_player = robots[0].player
	robots[1].play([11])
	return 10
