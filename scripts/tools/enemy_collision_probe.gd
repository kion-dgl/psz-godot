extends Node3D
## Real physics regression for #773. Run enemy_collision_probe.tscn headlessly.
var failures := 0

class Enemy extends EnemyBase:
	func _setup_model() -> void: pass
	func _setup_sound_playback() -> void: pass
	func _setup_reticle() -> void: pass

class Player extends "res://scripts/3d/player/player.gd":
	func _ready() -> void: pass

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		return
	failures += 1
	push_error("[enemy-collision] " + message)

func shape_for(body: CharacterBody3D, radius: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = capsule.height / 2.0
	body.add_child(shape)

func enemy_at(pos: Vector3, radius := 0.5, asleep := false) -> Enemy:
	var e := Enemy.new()
	e.enemy_data = EnemyData.new()
	e.enemy_data.collision_radius = radius
	e.collision_layer = 8
	e.collision_mask = 1
	e.dormant = asleep
	shape_for(e, radius, maxf(1.5, radius * 2.0))
	e.position = pos
	add_child(e)
	e.set_physics_process(false)
	return e

func advance(body: CharacterBody3D, direction: Vector3, ticks := 90) -> void:
	for i in range(ticks):
		await get_tree().physics_frame
		body.velocity = direction
		body.move_and_slide()

func player_scene_value(property: String) -> float:
	var pattern := RegEx.new()
	pattern.compile("(?m)^%s = ([0-9.]+)$" % property)
	var found := pattern.search(FileAccess.get_file_as_string("res://scenes/3d/player/player.tscn"))
	assert(found != null, "Missing player scene property: " + property)
	return float(found.get_string(1))

func _run() -> void:
	# Read shipped shape/masks without requiring proprietary GLB assets in CI.
	var p := Player.new()
	p.collision_layer = int(player_scene_value("collision_layer"))
	p.collision_mask = int(player_scene_value("collision_mask"))
	p.safe_margin = player_scene_value("safe_margin")
	shape_for(p, player_scene_value("radius"), player_scene_value("height"))
	p.get_child(0).name = "CollisionShape3D"
	var visual := Node3D.new()
	visual.name = "PlayerModel"
	p.add_child(visual)
	var navigation := NavigationAgent3D.new()
	navigation.name = "NavigationAgent3D"
	p.add_child(navigation)
	add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	var e := enemy_at(Vector3(2, 0, 0))
	await advance(p, Vector3(4, 0, 0))
	check(p.position.x < 1.2, "player cannot walk through stationary enemy")
	p.position = Vector3(-10, 0, 0)
	var other := enemy_at(Vector3(5, 0, 0), 0.9)
	await advance(e, Vector3(4, 0, 0))
	check(other.position.distance_to(e.position) >= 1.39, "mixed-size enemies retain their body radii")
	# Initial spawn overlaps must separate under the physics solver.
	e.position = Vector3(4.8, 0, 0)
	await advance(e, Vector3.ZERO, 10)
	check(other.position.distance_to(e.position) >= 1.39, "spawn overlap recovers without custom repulsion")
	var before := e.position
	await advance(e, Vector3(-8, 0, 0), 15)
	check(e.position.x < before.x - 1.5, "knockback can separate touching enemies")
	e.free()
	other.free()
	await check_crowd_and_corridor(p)
	await check_body_lifecycle(p)
	p.free()
	print("[enemy-collision] DONE failures=%d" % failures)
	get_tree().quit(1 if failures else 0)


func check_crowd_and_corridor(p: Player) -> void:
	# Several bodies converge on one point on a real floor, including Helion.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var crowd: Array[Enemy] = []
	for i in range(6):
		var angle := TAU * i / 6.0
		var radius: float = EnemyRegistry.get_enemy("helion").collision_radius if i == 0 else 0.5
		crowd.append(enemy_at(Vector3(cos(angle), 0, sin(angle)) * 4, radius))
	for tick in range(120):
		await get_tree().physics_frame
		for member in crowd:
			var direction := -member.position
			direction.y = 0
			member.velocity = direction.normalized() * 3 + Vector3.DOWN
			member.move_and_slide()
	var separated := true
	for i in range(crowd.size()):
		for j in range(i):
			var distance := Vector2(crowd[i].position.x, crowd[i].position.z).distance_to(Vector2(crowd[j].position.x, crowd[j].position.z))
			separated = separated and distance >= crowd[i].enemy_data.collision_radius + crowd[j].enemy_data.collision_radius - 0.05
	check(separated, "six converging enemies including Helion cannot stack")
	for member in crowd: member.free()
	await check_detour(false)
	await check_detour(true)
	# A narrow corridor still admits a player after a blocking body is removed.
	var walls: Array[StaticBody3D] = []
	for side in [-1, 1]:
		var wall := StaticBody3D.new()
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(8, 3, 1)
		wall_shape.shape = wall_box
		wall.position = Vector3(0, 1.5, side * 1.15)
		wall.add_child(wall_shape)
		add_child(wall)
		walls.append(wall)
	p.position = Vector3(-2, 0, 0)
	await advance(p, Vector3(4, -1, 0), 70)
	check(p.position.x > 2, "player can traverse a 1.3-unit corridor")
	for wall in walls: wall.free()
	floor_body.free()


func check_body_lifecycle(p: Player) -> void:
	var sleeper := enemy_at(Vector3(0, 0, 0), 0.5, true)
	p.position = Vector3(-2, 0, 0)
	await advance(p, Vector3(4, 0, 0))
	check(p.position.x > 2, "dormant enemy does not form an invisible wall")
	sleeper.reveal()
	p.position = Vector3(-2, 0, 0)
	await advance(p, Vector3(4, 0, 0))
	check(p.position.x < -0.8, "revealed enemy becomes solid")
	p.current_state = p.PlayerState.DODGING
	p.dodge_timer = 0
	p._sync_dodge_body_collisions()
	await advance(p, Vector3(4, 0, 0), 45)
	check(p.position.x > 1, "dodge contact window permits passage")
	p.current_state = p.PlayerState.IDLE
	p._sync_dodge_body_collisions()
	await advance(p, Vector3(-4, 0, 0), 60)
	check(p.position.x > 0.8, "enemy solidity returns after dodge")
	sleeper._die()
	await advance(p, Vector3(-4, 0, 0), 45)
	check(p.position.x < -1, "defeated enemy no longer blocks player")


func check_detour(box_obstacle: bool) -> void:
	var obstacle: PhysicsBody3D
	if box_obstacle:
		obstacle = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 2, 2)
		shape.shape = box
		shape.position.y = 1.0
		obstacle.add_child(shape)
		add_child(obstacle)
	else:
		obstacle = enemy_at(Vector3.ZERO)
	var goal := Node3D.new()
	goal.position = Vector3(4, 0, 0)
	add_child(goal)
	var mover := enemy_at(Vector3(-4, 0, 0))
	mover.target = goal
	mover.current_state = EnemyBase.EnemyState.CHASING
	mover.attack_cooldown_timer = 100.0
	mover._archetype = "stance_riser"  # Garapython / Garahadan chase path.
	var reached := false
	for tick in range(480):
		await get_tree().physics_frame
		mover._physics_process(1.0 / 60.0)
		if mover.position.x > 2.5:
			reached = true
			break
	check(reached, "snake chases around a solid box" if box_obstacle else "snake chases around another stationary snake")
	mover.free()
	goal.free()
	obstacle.free()
