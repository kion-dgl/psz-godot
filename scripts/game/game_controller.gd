extends Node3D
class_name GameController
## Main game controller - handles map loading, player spawning, and transitions

@export var starting_map: String = "s01a_ga1"
@export var starting_spawn: int = 0

# Scene references
@onready var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
@onready var camera_scene: PackedScene = preload("res://scenes/camera/orbit_camera.tscn")

# Node references
var environment_container: Node3D
var player: CharacterBody3D
var camera: Node3D

# Lighting nodes (created once, persist across maps)
var world_environment: WorldEnvironment
var directional_light: DirectionalLight3D


func _ready() -> void:
	add_to_group("map_controller")

	# Create persistent nodes
	_setup_environment()
	_setup_lighting()

	# Create container for map geometry
	environment_container = Node3D.new()
	environment_container.name = "EnvironmentContainer"
	add_child(environment_container)

	# Load starting map
	load_map(starting_map, starting_spawn)


func _setup_environment() -> void:
	# Create sky and environment
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.4, 0.6, 0.9, 1)
	sky_material.sky_horizon_color = Color(0.7, 0.8, 0.95, 1)
	sky_material.ground_bottom_color = Color(0.2, 0.15, 0.1, 1)
	sky_material.ground_horizon_color = Color(0.5, 0.45, 0.35, 1)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.9, 0.9, 0.95, 1)
	env.ambient_light_energy = 1.0

	world_environment = WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)


func _setup_lighting() -> void:
	# Main light pointing down
	directional_light = DirectionalLight3D.new()
	directional_light.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, 0.707, 0.707), Vector3(0, -0.707, 0.707)),
		Vector3(0, 20, 0)
	)
	directional_light.light_color = Color(1, 0.98, 0.95, 1)
	directional_light.light_energy = 0.8
	directional_light.shadow_enabled = true
	add_child(directional_light)


func load_map(map_id: String, spawn_index: int = 0) -> void:
	print("[GameController] Loading map: ", map_id)

	# Clear existing triggers
	for child in get_children():
		if child is TriggerZone:
			child.queue_free()

	# Clear existing enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()

	# Clear existing map
	for child in environment_container.get_children():
		child.queue_free()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Load map GLB
	var map_path := "res://assets/environments/valley/" + map_id + ".glb"
	var packed_scene := load(map_path) as PackedScene
	if not packed_scene:
		push_error("Failed to load map: " + map_path)
		return

	# Instance and add map
	var map_instance := packed_scene.instantiate() as Node3D
	environment_container.add_child(map_instance)

	# Configure collision from exported -colonly meshes
	_setup_map_collision(map_instance)

	# Wait for map to be in tree
	await get_tree().process_frame

	# Update MapManager
	MapManager.current_map_id = map_id

	# Get spawn info
	var cfg := MapManager.get_map_config(map_id)
	var spawn := cfg.get_spawn(spawn_index)

	# Spawn or move player
	print("[GameController] Spawning player at: ", spawn.position)
	if not player:
		_spawn_player(spawn.position, spawn.rotation)
	else:
		_move_player(spawn.position, spawn.rotation)

	# Wait for player to be in tree before setting up triggers
	await get_tree().process_frame

	# Set up triggers from the loaded map
	_setup_triggers(map_instance, map_id)

	# Spawn test enemies (temporary - will be data-driven later)
	_spawn_test_enemies(map_id)

	MapManager.map_changed.emit(map_id)


func _spawn_player(spawn_pos: Vector3, spawn_rot: float) -> void:
	player = player_scene.instantiate() as CharacterBody3D
	if not player:
		push_error("[GameController] Failed to instantiate player!")
		return
	player.add_to_group("player")
	add_child(player)
	print("[GameController] Player added: ", player.name, " at ", spawn_pos)

	# Set position after adding to tree
	player.global_position = spawn_pos

	# Set player model rotation
	var model := player.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.rotation.y = spawn_rot

	# Create camera
	camera = camera_scene.instantiate()
	add_child(camera)

	# Set camera target directly (target_path is checked in _ready which already ran)
	camera.set_target(player)


func _move_player(spawn_pos: Vector3, spawn_rot: float) -> void:
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO

	# Update spawn position for respawn
	player.spawn_position = spawn_pos

	# Set player rotation (both internal state and model)
	player.player_rotation = spawn_rot
	var model := player.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.rotation.y = spawn_rot


func _setup_triggers(_map_root: Node3D, map_id: String) -> void:
	# Create triggers from MapManager configuration
	var trigger_count := MapManager.get_trigger_count(map_id)

	for i in range(trigger_count):
		var trigger_data := MapManager.get_trigger_data(map_id, i)
		if not trigger_data:
			continue

		# Get route for this trigger
		var route := MapManager.get_route(map_id, i)
		if route.is_empty():
			print("[GameController] No route for trigger %d in %s" % [i, map_id])
			continue

		# Create trigger zone
		var trigger_zone := TriggerZone.new()
		trigger_zone.name = "Trigger_%d" % i
		trigger_zone.trigger_index = i
		trigger_zone.trigger_size = trigger_data.size
		trigger_zone.target_map = route.get("map", "")
		trigger_zone.spawn_index = route.get("spawn", 0)

		add_child(trigger_zone)

		# Set position and rotation
		trigger_zone.global_position = trigger_data.position
		trigger_zone.rotation.y = trigger_data.rotation

		print("[GameController] Created trigger %d at %s -> %s" % [i, trigger_data.position, trigger_zone.target_map])


# Called by TriggerZone when activated
func on_trigger_activated(target_map: String, spawn_index: int) -> void:
	print("[GameController] Trigger activated -> ", target_map, " spawn: ", spawn_index)

	# Small delay to prevent instant re-triggering
	await get_tree().create_timer(0.1).timeout

	load_map(target_map, spawn_index)


func _setup_map_collision(root: Node) -> void:
	## Configure collision from exported map GLBs.
	##
	## REQUIRED CONVENTION: Map GLBs must be exported from the stage-editor with:
	##   - "collision_floor-colonly" mesh: Defines walkable floor areas
	##     Godot auto-converts this to StaticBody3D named "collision_floor"
	##   - Optional "trigger_*_box-colonly" meshes: Trigger zones
	##
	## The -colonly suffix tells Godot to:
	##   1. Create a StaticBody3D with trimesh collision shape
	##   2. Remove the -colonly suffix from the node name
	##   3. Hide the visual mesh (collision only)
	##
	## Without collision_floor, player will fall through the map!

	var found_floor := _configure_collision_nodes(root)

	# Validate that required collision was found
	if not found_floor:
		push_warning("[GameController] No 'collision_floor' found in map! " +
			"Map must be exported from stage-editor with collision_floor-colonly mesh.")


func _configure_collision_nodes(node: Node) -> bool:
	var found_floor := false

	# Configure auto-created StaticBody3D nodes from -colonly meshes
	if node is StaticBody3D:
		# Check if this is the required floor collision
		if node.name == "collision_floor":
			found_floor = true

		# Set collision layer for floor/obstacle detection
		node.collision_layer = 1  # Environment layer (player raycasts use mask 1)
		node.collision_mask = 0   # Doesn't need to detect anything

	# Hide debug markers from stage editor export
	if node is MeshInstance3D:
		var mesh_name := node.name
		if mesh_name.begins_with("gate_") or mesh_name.begins_with("spawn_") or mesh_name.begins_with("trigger_"):
			node.visible = false

	# Process children
	for child in node.get_children():
		if _configure_collision_nodes(child):
			found_floor = true

	return found_floor


func _spawn_test_enemies(map_id: String) -> void:
	# Only spawn test enemies in the starting map for now
	if map_id != "s01a_ga1":
		return

	var ghowl_scene = load("res://scenes/enemies/ghowl.tscn")
	if not ghowl_scene:
		push_warning("[GameController] Could not load ghowl.tscn")
		return

	# Spawn a few test enemies near the spawn point
	var spawn_positions := [
		Vector3(0, 1, 10),
		Vector3(5, 1, 15),
		Vector3(-5, 1, 12),
	]

	for pos in spawn_positions:
		var enemy: Node3D = ghowl_scene.instantiate()
		add_child(enemy)
		enemy.global_position = pos
		print("[GameController] Spawned Ghowl at ", pos)
