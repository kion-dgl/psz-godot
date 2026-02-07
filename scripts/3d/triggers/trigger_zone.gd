extends Area3D
class_name TriggerZone
## Detects player entry and triggers map transitions

signal player_entered
signal player_exited

@export var trigger_index: int = 0
@export var target_map: String = ""
@export var spawn_index: int = 0
@export var trigger_size: Vector3 = Vector3(4, 3, 4)

var player_inside: bool = false
var has_triggered: bool = false


func _ready() -> void:
	# Set up collision
	collision_layer = 0
	collision_mask = 2  # Player layer
	monitoring = true
	monitorable = false

	# Create collision shape if not present
	if get_child_count() == 0 or not has_node("CollisionShape3D"):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = trigger_size
		shape.shape = box
		shape.position.y = trigger_size.y / 2  # Center vertically
		add_child(shape)

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Check for bodies already overlapping (in case player spawned inside)
	call_deferred("_check_initial_overlap")


func _check_initial_overlap() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_inside = true
		player_entered.emit()

		if not has_triggered:
			has_triggered = true
			_trigger_transition()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_inside = false
		player_exited.emit()


func _trigger_transition() -> void:
	# Get target from MapManager routes if not explicitly set
	var actual_target := target_map
	var actual_spawn := spawn_index

	if actual_target.is_empty():
		var route := MapManager.get_route(MapManager.current_map_id, trigger_index)
		if route.has("map"):
			actual_target = route["map"]
			actual_spawn = route.get("spawn", 0)

	if actual_target.is_empty():
		return

	print("[TriggerZone] Transitioning to: ", actual_target, " spawn: ", actual_spawn)

	# Notify the game to transition
	get_tree().call_group("map_controller", "on_trigger_activated", actual_target, actual_spawn)


func reset_trigger() -> void:
	has_triggered = false
