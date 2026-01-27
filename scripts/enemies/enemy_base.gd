class_name EnemyBase extends CharacterBody3D
## Base class for all enemies. Uses EnemyData resource for stats.

## Enemy data resource (set in inspector or via spawn)
@export var enemy_data: Resource  # EnemyData

## Current HP
var current_hp: int = 100

## Is enemy alive?
var is_alive: bool = true

## Target to chase (usually the player)
var target: Node3D

## State machine
enum EnemyState {
	IDLE,
	CHASING,
	ATTACKING,
	HURT,
	DEAD,
}
var current_state: EnemyState = EnemyState.IDLE

## Components
var hurtbox: Hurtbox
var model: Node3D
var nav_agent: NavigationAgent3D
var animation_player: AnimationPlayer

## Attack tracking
var attack_cooldown_timer: float = 0.0
var hurt_timer: float = 0.0
const HURT_DURATION: float = 0.3

## Animation state tracking
var is_attacking: bool = false
var current_anim: String = ""

## Wandering behavior (idle state)
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_wandering: bool = false
const WANDER_INTERVAL_MIN: float = 2.0  # Min time before changing direction
const WANDER_INTERVAL_MAX: float = 5.0  # Max time before changing direction
const WANDER_PAUSE_CHANCE: float = 0.3  # Chance to pause instead of walk
const WANDER_SPEED_MULT: float = 0.5  # Wander at half chase speed

## Movement
const GRAVITY: float = 20.0

## Floor detection (raycast-based) - same as player
const FLOOR_CHECK_DISTANCE: float = 1.0  # How far ahead to check
const FLOOR_CHECK_SIDE: float = 0.5  # Side offset for corner checks
const FLOOR_RAY_LENGTH: float = 5.0  # How far down to raycast

## Signals
signal died(enemy: EnemyBase)
signal damaged(enemy: EnemyBase, amount: int)


func _ready() -> void:
	add_to_group("enemies")
	_setup_from_data()
	_setup_model()
	_setup_hurtbox()
	_setup_navigation()
	_find_target()

	# Randomize initial wander timer so enemies don't sync up
	wander_timer = randf_range(0.0, WANDER_INTERVAL_MAX)
	print("[Enemy] Ready: ", name, " at ", global_position, " | AnimPlayer: ", animation_player != null)


func _setup_from_data() -> void:
	if enemy_data:
		current_hp = enemy_data.hp_base
	else:
		push_warning("[Enemy] No enemy_data set!")


func _setup_model() -> void:
	# Find the Model node (added in scene)
	model = get_node_or_null("Model")
	if not model:
		return

	# Find AnimationPlayer in the model hierarchy
	animation_player = _find_animation_player(model)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
		print("[Enemy] Found AnimationPlayer with animations: ", animation_player.get_animation_list())
	else:
		push_warning("[Enemy] No AnimationPlayer found in model")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.owner_node = self
	hurtbox.hit_received.connect(_on_hit_received)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()

	if enemy_data:
		capsule.radius = enemy_data.collision_radius
		capsule.height = enemy_data.collision_height
	else:
		capsule.radius = 0.5
		capsule.height = 1.5

	shape.shape = capsule
	shape.position.y = capsule.height / 2
	hurtbox.add_child(shape)

	add_child(hurtbox)


func _setup_navigation() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.5
	add_child(nav_agent)


func _find_target() -> void:
	# Find the player in the scene
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]
		print("[Enemy] Found player target: ", target.name)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Update state
	match current_state:
		EnemyState.IDLE:
			_process_idle(delta)
		EnemyState.CHASING:
			_process_chasing(delta)
		EnemyState.ATTACKING:
			_process_attacking(delta)
		EnemyState.HURT:
			_process_hurt(delta)

	# Update cooldowns
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	move_and_slide()


func _process_idle(delta: float) -> void:
	# Try to find target if we don't have one
	if not target or not is_instance_valid(target):
		_find_target()

	# Check if target is in detection range - become alert!
	if target and is_instance_valid(target):
		var dist := global_position.distance_to(target.global_position)
		if enemy_data and dist <= enemy_data.detection_range:
			current_state = EnemyState.CHASING
			is_wandering = false
			_play_animation("tht", true)  # Threat/war cry when becoming active
			return

	# Wandering behavior
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander_behavior()

	if is_wandering and wander_direction.length() > 0.1:
		# Walking in wander direction
		_play_animation("wlk")

		var speed := 3.0
		if enemy_data:
			speed = enemy_data.move_speed * WANDER_SPEED_MULT

		# Apply movement if floor ahead
		if _can_move_to(wander_direction):
			velocity.x = wander_direction.x * speed
			velocity.z = wander_direction.z * speed
			# Face movement direction
			_face_direction(wander_direction)
		else:
			# Hit an edge, pick new direction
			_pick_new_wander_behavior()
	else:
		# Standing idle
		velocity.x = 0
		velocity.z = 0
		_play_animation("wat")


func _pick_new_wander_behavior() -> void:
	wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)

	# Chance to just stand still
	if randf() < WANDER_PAUSE_CHANCE:
		is_wandering = false
		wander_direction = Vector3.ZERO
	else:
		# Pick random direction
		is_wandering = true
		var angle := randf() * TAU
		wander_direction = Vector3(sin(angle), 0, cos(angle))


func _process_chasing(_delta: float) -> void:
	if not target or not is_instance_valid(target):
		current_state = EnemyState.IDLE
		return

	var dist := global_position.distance_to(target.global_position)

	# Check if in attack range
	var attack_range := 2.0
	if enemy_data:
		attack_range = enemy_data.attack_range

	if dist <= attack_range and attack_cooldown_timer <= 0:
		current_state = EnemyState.ATTACKING
		_start_attack()
		return

	# Play run animation while chasing
	_play_animation("run")

	# Calculate direction to target (horizontal only, properly normalized)
	var to_target := target.global_position - global_position
	var horizontal_dir := Vector3(to_target.x, 0, to_target.z)
	var direction := horizontal_dir.normalized() if horizontal_dir.length() > 0.1 else Vector3.ZERO

	# Try navigation if available, but keep direct path as fallback
	nav_agent.target_position = target.global_position
	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var nav_dir := (next_pos - global_position)
		nav_dir.y = 0
		# Only use nav direction if it's valid (not pointing at ourselves)
		if nav_dir.length() > 0.5:
			direction = nav_dir.normalized()

	# Apply movement
	var speed := 3.0
	if enemy_data:
		speed = enemy_data.move_speed

	# Apply movement if we have a valid direction and floor ahead
	if direction.length() > 0.1 and _can_move_to(direction):
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Face movement direction (model faces -Z, so look opposite)
		_face_direction(direction)


func _process_attacking(_delta: float) -> void:
	velocity.x = 0
	velocity.z = 0

	# Wait for attack animation to finish
	if not is_attacking:
		current_state = EnemyState.CHASING


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta

	# Check floor during knockback - stop if approaching edge
	if velocity.length() > 0.1:
		var move_dir := velocity.normalized()
		move_dir.y = 0
		if not _can_move_to(move_dir):
			velocity.x = 0
			velocity.z = 0

	if hurt_timer <= 0:
		current_state = EnemyState.CHASING


func _start_attack() -> void:
	if not target or not is_instance_valid(target):
		return

	is_attacking = true
	_play_animation("atk", true)  # Force play attack animation

	# Face the target
	var dir_to_target := (target.global_position - global_position).normalized()
	dir_to_target.y = 0
	if dir_to_target.length() > 0.1:
		_face_direction(dir_to_target)

	# Deal damage to player (fixed 10 damage for now, per user request)
	var damage := 10

	if target.has_method("take_damage"):
		var knockback_dir := (target.global_position - global_position).normalized()
		knockback_dir.y = 0
		target.take_damage(damage, knockback_dir * 5.0)

	# Set cooldown
	var cooldown := 1.5
	if enemy_data:
		cooldown = enemy_data.attack_cooldown
	attack_cooldown_timer = cooldown


func _on_hit_received(damage: int, knockback: Vector3) -> void:
	if not is_alive:
		return

	current_hp -= damage
	damaged.emit(self, damage)
	print("[Enemy] ", enemy_data.name if enemy_data else "Enemy", " took ", damage, " damage (HP: ", current_hp, ")")

	if current_hp <= 0:
		_die()
	else:
		# Enter hurt state
		is_attacking = false  # Cancel any attack
		current_state = EnemyState.HURT
		hurt_timer = HURT_DURATION

		# Only apply knockback if it won't push us off the edge
		var knockback_dir := knockback.normalized()
		knockback_dir.y = 0
		if knockback_dir.length() > 0.1 and _can_move_to(knockback_dir):
			velocity = knockback
		else:
			velocity = Vector3.ZERO  # Stop at edge

		_play_animation("dmg", true)  # Force play damage animation


func _die() -> void:
	is_alive = false
	is_attacking = false
	current_state = EnemyState.DEAD
	died.emit(self)

	print("[Enemy] ", enemy_data.name if enemy_data else "Enemy", " died!")

	# Play death animation
	_play_animation("ded", true)

	# Drop meseta
	if enemy_data:
		var meseta: int = enemy_data.get_meseta_drop()
		_spawn_meseta_drop(meseta)

	# Remove after death animation (or delay if no animation)
	var delay := 1.5  # Default delay
	if animation_player and animation_player.has_animation("ded"):
		delay = animation_player.get_animation("ded").length + 0.3
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(queue_free)


func _spawn_meseta_drop(amount: int) -> void:
	# Spawn a meseta drop at our position
	var drop_scene: PackedScene = load("res://scenes/elements/drop_meseta.tscn")
	if drop_scene:
		var drop: Node3D = drop_scene.instantiate()
		drop.set("amount", amount)
		drop.global_position = global_position + Vector3(0, 0.5, 0)
		get_parent().add_child(drop)
	else:
		# Just add meseta directly if no drop scene
		GameState.add_meseta(amount)
		print("[Enemy] Dropped ", amount, " meseta (no scene)")


## Set the enemy data and reinitialize
func set_enemy_data(data: Resource) -> void:
	enemy_data = data
	if is_inside_tree():
		_setup_from_data()


## Face a direction (model faces -Z, so we look opposite way)
func _face_direction(dir: Vector3) -> void:
	if dir.length() < 0.1:
		return
	# Look at the opposite direction since model faces -Z
	look_at(global_position - dir, Vector3.UP)


## Check if enemy can move in direction (floor detection)
func _can_move_to(move_dir: Vector3) -> bool:
	# Check multiple points to prevent walking off edges
	var center := global_position + move_dir * FLOOR_CHECK_DISTANCE

	# Calculate perpendicular direction for side checks
	var side_dir := Vector3(-move_dir.z, 0, move_dir.x)  # 90 degree rotation
	var left := center + side_dir * FLOOR_CHECK_SIDE
	var right := center - side_dir * FLOOR_CHECK_SIDE

	# All three points must have floor
	return _has_floor_at(center) and _has_floor_at(left) and _has_floor_at(right)


func _has_floor_at(check_pos: Vector3) -> bool:
	# Cast a ray downward from check_pos to see if there's floor
	var space_state := get_world_3d().direct_space_state
	var ray_origin := Vector3(check_pos.x, global_position.y + 1.0, check_pos.z)
	var ray_end := Vector3(check_pos.x, global_position.y - FLOOR_RAY_LENGTH, check_pos.z)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Environment layer
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	return not result.is_empty()


## Play an animation by name (short name like "atk" will match "s_001_atk")
func _play_animation(anim_name: String, force: bool = false) -> void:
	if not animation_player:
		return

	# Don't interrupt same animation unless forced
	if not force and current_anim == anim_name:
		return

	# Try to find the animation - GLB animations are named like "s_001_atk"
	var full_name := _find_animation(anim_name)
	if full_name.is_empty():
		return

	animation_player.play(full_name)
	current_anim = anim_name


## Find animation by short name (e.g., "atk" matches "s_001_atk")
func _find_animation(short_name: String) -> String:
	# Direct match first
	if animation_player.has_animation(short_name):
		return short_name

	# Search all animations for one ending with the short name
	var anim_list: PackedStringArray = animation_player.get_animation_list()
	for i in range(anim_list.size()):
		var anim_name: String = anim_list[i]
		if anim_name.ends_with("_" + short_name):
			return anim_name

	# Search in libraries
	var lib_list: Array[StringName] = animation_player.get_animation_library_list()
	for j in range(lib_list.size()):
		var lib_name: StringName = lib_list[j]
		var lib: AnimationLibrary = animation_player.get_animation_library(lib_name)
		var lib_anim_list: PackedStringArray = lib.get_animation_list()
		for k in range(lib_anim_list.size()):
			var anim_name: String = lib_anim_list[k]
			if anim_name.ends_with("_" + short_name):
				var full: String = str(lib_name) + "/" + anim_name if lib_name else anim_name
				return full

	return ""


## Called when animation finishes
func _on_animation_finished(anim_name: String) -> void:
	# Extract short name (e.g., "s_001_atk" -> "atk")
	var short_name := anim_name
	if "_" in anim_name:
		short_name = anim_name.get_slice("_", -1)  # Get last part after underscore

	match short_name:
		"atk":
			is_attacking = false
		"tht":
			# After threat animation, start chasing
			if current_state == EnemyState.CHASING:
				_play_animation("run")
