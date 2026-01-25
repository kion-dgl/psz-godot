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

## Attack tracking
var attack_cooldown_timer: float = 0.0
var hurt_timer: float = 0.0
const HURT_DURATION: float = 0.3

## Movement
const GRAVITY: float = 20.0

## Signals
signal died(enemy: EnemyBase)
signal damaged(enemy: EnemyBase, amount: int)


func _ready() -> void:
	_setup_from_data()
	_setup_hurtbox()
	_setup_navigation()
	_find_target()


func _setup_from_data() -> void:
	if enemy_data:
		current_hp = enemy_data.hp_base
	else:
		push_warning("[Enemy] No enemy_data set!")


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
	velocity.x = 0
	velocity.z = 0

	# Check if target is in detection range
	if target and is_instance_valid(target):
		var dist := global_position.distance_to(target.global_position)
		if enemy_data and dist <= enemy_data.detection_range:
			current_state = EnemyState.CHASING


func _process_chasing(delta: float) -> void:
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

	# Chase target
	nav_agent.target_position = target.global_position

	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var direction := (next_pos - global_position).normalized()
		direction.y = 0

		var speed := 3.0
		if enemy_data:
			speed = enemy_data.move_speed

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

		# Face movement direction
		if direction.length() > 0.1:
			look_at(global_position + direction, Vector3.UP)


func _process_attacking(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	# Attack animation would play here
	# For now, just return to chasing after a delay
	current_state = EnemyState.CHASING


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	if hurt_timer <= 0:
		current_state = EnemyState.CHASING


func _start_attack() -> void:
	if not target or not is_instance_valid(target):
		return

	# Deal damage to player
	var damage := 10
	if enemy_data:
		damage = enemy_data.attack_base

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
		current_state = EnemyState.HURT
		hurt_timer = HURT_DURATION
		velocity = knockback


func _die() -> void:
	is_alive = false
	current_state = EnemyState.DEAD
	died.emit(self)

	print("[Enemy] ", enemy_data.name if enemy_data else "Enemy", " died!")

	# Drop meseta
	if enemy_data:
		var meseta: int = enemy_data.get_meseta_drop()
		_spawn_meseta_drop(meseta)

	# Remove after delay
	var tween := create_tween()
	tween.tween_interval(0.5)
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
