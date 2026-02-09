extends Node3D
## Valley Field 3D Controller — loads GLB models, reads portal nodes, handles
## grid cell transitions, key-gate mechanics, and section progression.

const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

var player: CharacterBody3D
var orbit_camera: Node3D
var _map_root: Node3D
var _transitioning := false
var _keys_collected: Dictionary = {}
var _current_cell: Dictionary = {}
var _portal_data: Dictionary = {}


func _ready() -> void:
	var data: Dictionary = SceneManager.get_transition_data()
	var current_cell_pos: String = str(data.get("current_cell_pos", ""))
	var spawn_edge: String = str(data.get("spawn_edge", ""))
	_keys_collected = data.get("keys_collected", {})

	# Get sections and current cell
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()
	if section_idx >= sections.size():
		push_error("[ValleyField] Invalid section index: %d" % section_idx)
		_return_to_city()
		return

	var section: Dictionary = sections[section_idx]
	var cells: Array = section.get("cells", [])

	# Find current cell
	_current_cell = _find_cell(cells, current_cell_pos)
	if _current_cell.is_empty():
		push_error("[ValleyField] Cell not found: %s" % current_cell_pos)
		_return_to_city()
		return

	# Load GLB
	var stage_id: String = str(_current_cell["stage_id"])
	var map_path := "res://assets/environments/valley/%s.glb" % stage_id
	var packed_scene := load(map_path) as PackedScene
	if not packed_scene:
		push_error("[ValleyField] Failed to load map: %s" % map_path)
		_return_to_city()
		return

	_map_root = packed_scene.instantiate() as Node3D
	_map_root.name = "Map"

	# Apply grid rotation
	var rotation_deg: int = int(_current_cell.get("rotation", 0))
	_map_root.rotation.y = deg_to_rad(rotation_deg)

	add_child(_map_root)
	await get_tree().process_frame

	# Setup collision from GLB -colonly meshes
	_setup_map_collision(_map_root)
	await get_tree().process_frame

	# Discover portal nodes from scene tree
	_portal_data = _find_portal_data(_map_root)

	# Spawn player
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	if not spawn_edge.is_empty() and _portal_data.has(spawn_edge):
		spawn_pos = _portal_data[spawn_edge]["spawn_pos"]
		# Face away from spawn edge (into the room)
		spawn_rot = _dir_to_yaw(OPPOSITE[spawn_edge])
	elif _portal_data.has("south"):
		# Default: spawn at south portal (start cell enters from south)
		spawn_pos = _portal_data["south"]["spawn_pos"]
		spawn_rot = _dir_to_yaw("north")
	else:
		# Fallback: center of map
		spawn_pos = Vector3(0, 1, 0)

	_spawn_player(spawn_pos, spawn_rot)
	await get_tree().process_frame

	# Create gate triggers for each connection (skip the entry edge)
	var connections: Dictionary = _current_cell.get("connections", {})
	for dir in connections:
		if dir == spawn_edge:
			continue
		if not _portal_data.has(dir):
			continue

		# Check key-gate lock
		var is_locked := false
		if _current_cell.get("is_key_gate", false):
			var locked_dir: String = str(_current_cell.get("key_gate_direction", ""))
			if locked_dir == dir and not _keys_collected.has(_current_cell.get("pos", "")):
				is_locked = true

		if not is_locked:
			_create_gate_trigger(dir, str(connections[dir]), _portal_data[dir])

	# Create exit trigger on end cell warp_edge
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))
	if not warp_edge.is_empty() and _portal_data.has(warp_edge):
		_create_exit_trigger(warp_edge, _portal_data[warp_edge])

	# Place key pickup if this cell has one
	if _current_cell.get("has_key", false):
		var key_for: String = str(_current_cell.get("key_for_cell", ""))
		if not key_for.is_empty() and not _keys_collected.has(key_for):
			_create_key_pickup(key_for)

	# Hide debug marker meshes
	_hide_debug_markers(_map_root)


func _find_cell(cells: Array, pos: String) -> Dictionary:
	for cell in cells:
		if str(cell.get("pos", "")) == pos:
			return cell
	return {}


func _find_portal_data(map_root: Node3D) -> Dictionary:
	var portals := {}
	var portals_node: Node3D = map_root.get_node_or_null("portals")
	if not portals_node:
		portals_node = _find_child_by_name(map_root, "portals")
	if not portals_node:
		return portals

	for dir in ["north", "east", "south", "west"]:
		var spawn_node: Node3D = portals_node.get_node_or_null("spawn_" + dir)
		var trigger_area: Node3D = portals_node.get_node_or_null("trigger_" + dir + "-area")
		if spawn_node:
			var trigger_pos: Vector3 = spawn_node.global_position
			if trigger_area:
				var trigger_box: Node3D = trigger_area.get_node_or_null("trigger_" + dir + "_box")
				if trigger_box:
					trigger_pos = trigger_box.global_position
				else:
					trigger_pos = trigger_area.global_position
			portals[dir] = {
				"spawn_pos": spawn_node.global_position,
				"trigger_pos": trigger_pos,
			}
	return portals


func _find_child_by_name(node: Node, child_name: String) -> Node:
	for child in node.get_children():
		if child.name == child_name:
			return child
		var found := _find_child_by_name(child, child_name)
		if found:
			return found
	return null


func _dir_to_yaw(dir: String) -> float:
	match dir:
		"north": return 0.0
		"east": return -PI / 2.0
		"south": return PI
		"west": return PI / 2.0
	return 0.0


func _spawn_player(pos: Vector3, rot: float) -> void:
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.add_to_group("player")
	add_child(player)
	player.global_position = pos

	var model := player.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.rotation.y = rot

	player.spawn_position = pos

	orbit_camera = ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(player)


func _setup_map_collision(root: Node) -> void:
	_configure_collision_nodes(root)


func _configure_collision_nodes(node: Node) -> bool:
	var found_floor := false
	if node is StaticBody3D:
		if node.name == "collision_floor":
			found_floor = true
		node.collision_layer = 1
		node.collision_mask = 0
	for child in node.get_children():
		if _configure_collision_nodes(child):
			found_floor = true
	return found_floor


func _hide_debug_markers(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_name: String = node.name
		if mesh_name.begins_with("gate_") or mesh_name.begins_with("spawn_") \
				or mesh_name.begins_with("trigger_"):
			node.visible = false
	for child in node.get_children():
		_hide_debug_markers(child)


func _create_gate_trigger(direction: String, target_cell_pos: String, portal: Dictionary) -> void:
	var trigger := Area3D.new()
	trigger.name = "GateTrigger_%s" % direction
	trigger.collision_layer = 0
	trigger.collision_mask = 2  # Player layer
	trigger.global_position = portal["trigger_pos"]

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)

	var entry_edge: String = OPPOSITE[direction]
	trigger.body_entered.connect(func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			_transition_to_cell(target_cell_pos, entry_edge)
	)
	add_child(trigger)


func _create_exit_trigger(direction: String, portal: Dictionary) -> void:
	var trigger := Area3D.new()
	trigger.name = "ExitTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.global_position = portal["trigger_pos"]

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)

	trigger.body_entered.connect(func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			_on_end_reached()
	)
	add_child(trigger)


func _create_key_pickup(key_for_cell: String) -> void:
	# Floating key indicator at center of room
	var key_area := Area3D.new()
	key_area.name = "KeyPickup"
	key_area.collision_layer = 0
	key_area.collision_mask = 2
	key_area.global_position = Vector3(0, 1.5, 0)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	key_area.add_child(shape)

	# Visual indicator
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.0)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	key_area.add_child(mesh)

	key_area.body_entered.connect(func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			_keys_collected[key_for_cell] = true
			key_area.queue_free()
			# Unlock any gate triggers that were blocked
			_unlock_gates_for(key_for_cell)
	)
	add_child(key_area)


func _unlock_gates_for(key_for_cell: String) -> void:
	# If this cell IS the key-gate cell, create the previously locked trigger
	var cell_pos: String = str(_current_cell.get("pos", ""))
	if cell_pos != key_for_cell:
		return
	if not _current_cell.get("is_key_gate", false):
		return
	var locked_dir: String = str(_current_cell.get("key_gate_direction", ""))
	if locked_dir.is_empty():
		return
	var connections: Dictionary = _current_cell.get("connections", {})
	if not connections.has(locked_dir):
		return
	if not _portal_data.has(locked_dir):
		return
	_create_gate_trigger(locked_dir, str(connections[locked_dir]), _portal_data[locked_dir])


func _transition_to_cell(target_pos: String, spawn_edge: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": target_pos,
		"spawn_edge": spawn_edge,
		"keys_collected": _keys_collected,
	})


func _on_end_reached() -> void:
	if _transitioning:
		return
	_transitioning = true
	if SessionManager.advance_section():
		var sections: Array = SessionManager.get_field_sections()
		var new_idx: int = SessionManager.get_current_section()
		var new_section: Dictionary = sections[new_idx]
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": str(new_section.get("start_pos", "")),
			"spawn_edge": "",
			"keys_collected": {},
		})
	else:
		_return_to_city()


func _return_to_city() -> void:
	SessionManager.return_to_city()
	SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_city()
		get_viewport().set_input_as_handled()
