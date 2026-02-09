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
	_fix_texture_repeat(_map_root)
	await get_tree().process_frame

	# Setup collision from GLB -colonly meshes
	_setup_map_collision(_map_root)
	await get_tree().process_frame

	# Discover portal nodes from scene tree
	_portal_data = _find_portal_data(_map_root)
	print("[ValleyField] Portal data keys: %s" % str(_portal_data.keys()))
	for key in _portal_data:
		print("[ValleyField]   %s: spawn_pos=%s" % [key, _portal_data[key]["spawn_pos"]])

	# Spawn player
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	if not spawn_edge.is_empty() and _portal_data.has(spawn_edge):
		spawn_pos = _portal_data[spawn_edge]["spawn_pos"]
		# Face away from spawn edge (into the room)
		spawn_rot = _dir_to_yaw(OPPOSITE[spawn_edge])
	elif _portal_data.has("default"):
		# Standalone default spawn (boss rooms / gateless areas / fresh entry)
		spawn_pos = _portal_data["default"]["spawn_pos"]
		var arrow: Node3D = _find_child_by_name(_map_root, "spawn_default_arrow")
		if arrow:
			spawn_rot = arrow.rotation.y
	elif _portal_data.has("south"):
		# Legacy fallback: spawn at south portal (start cell enters from south)
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

	# Hide debug marker meshes (disabled for testing portal visibility)
	#_hide_debug_markers(_map_root)


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
		if not spawn_node:
			spawn_node = _find_child_by_name(portals_node, "spawn_" + dir)
		var trigger_area: Node3D = portals_node.get_node_or_null("trigger_" + dir + "-area")
		if not trigger_area:
			trigger_area = _find_child_by_name(portals_node, "trigger_" + dir + "-area")
		if spawn_node:
			# Use area's base position (y=0), not the box child (y=1.5)
			# since _create_gate_trigger adds its own y offset for the collision shape
			var trigger_pos: Vector3 = trigger_area.global_position if trigger_area else spawn_node.global_position
			portals[dir] = {
				"spawn_pos": spawn_node.global_position,
				"trigger_pos": trigger_pos,
			}

	# Look for standalone default spawn (boss rooms / gateless areas)
	var default_spawn: Node3D = _find_child_by_name(portals_node, "spawn_default")
	if default_spawn:
		portals["default"] = {
			"spawn_pos": default_spawn.global_position,
			"trigger_pos": default_spawn.global_position,
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

	# Set player facing direction (both model visual and movement state)
	player.player_rotation = rot
	var model := player.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.rotation.y = rot

	player.spawn_position = pos

	orbit_camera = ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(player)
	# Place camera behind the player's facing direction
	orbit_camera.camera_rotation = rot + PI


func _setup_map_collision(root: Node) -> void:
	_configure_collision_nodes(root)


func _fix_texture_repeat(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				if not mat.texture_repeat:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.texture_repeat = true
					mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_fix_texture_repeat(child)


func _configure_collision_nodes(node: Node) -> bool:
	var found_floor := false
	if node is StaticBody3D:
		if node.name == "collision_floor":
			found_floor = true
		# Skip trigger boxes — they define portal positions, not walls
		if str(node.name).begins_with("trigger_"):
			node.collision_layer = 0
			node.collision_mask = 0
		else:
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


func _create_gate_trigger(direction: String, target_cell_pos: String, _portal: Dictionary) -> void:
	var entry_edge: String = OPPOSITE[direction]
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] Player entered gate trigger: %s → cell %s" % [direction, target_cell_pos])
			_transition_to_cell(target_cell_pos, entry_edge)

	# Try to repurpose the GLB's trigger node
	var trigger_name := "trigger_" + direction + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + direction)
	if trigger_group:
		var area := _convert_static_to_area(trigger_group)
		if area:
			area.name = "GateTrigger_%s" % direction
			area.body_entered.connect(callback)
			return

	# Fallback: create programmatic trigger at portal position
	_create_fallback_trigger("GateTrigger_%s" % direction, _portal["trigger_pos"], callback)


func _create_exit_trigger(direction: String, _portal: Dictionary) -> void:
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] Player entered exit trigger")
			_on_end_reached()

	# Try to repurpose the GLB's trigger node
	var trigger_name := "trigger_" + direction + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + direction)
	if trigger_group:
		var area := _convert_static_to_area(trigger_group)
		if area:
			area.name = "ExitTrigger"
			area.body_entered.connect(callback)
			return

	# Fallback: create programmatic trigger at portal position
	_create_fallback_trigger("ExitTrigger", _portal["trigger_pos"], callback)


## Convert a GLB trigger group's -colonly StaticBody3D into a functional Area3D.
## The GLB structure is: trigger_{dir}-area (Node3D group)
##   ├── trigger_{dir}_box-colonly (StaticBody3D with CollisionShape3D)
##   └── trigger_{dir}_vis / trigger_{dir}_wire (MeshInstance3D, visual)
## We reparent the CollisionShape3D into a new Area3D and free the StaticBody3D.
func _convert_static_to_area(trigger_group: Node3D) -> Area3D:
	var static_body: StaticBody3D = null
	for child in trigger_group.get_children():
		if child is StaticBody3D:
			static_body = child
			break
	if not static_body:
		# Also search recursively in case of extra nesting
		static_body = _find_static_body(trigger_group)
	if not static_body:
		return null

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # Player layer

	# Move collision shapes from StaticBody3D to Area3D
	var shapes: Array = []
	for child in static_body.get_children():
		if child is CollisionShape3D:
			shapes.append(child)
	for shape in shapes:
		static_body.remove_child(shape)
		area.add_child(shape)

	# Place Area3D at the same position as the StaticBody3D
	trigger_group.add_child(area)
	area.global_position = static_body.global_position

	# Remove the now-empty StaticBody3D
	static_body.queue_free()
	return area


func _find_static_body(node: Node) -> StaticBody3D:
	for child in node.get_children():
		if child is StaticBody3D:
			return child
		var found := _find_static_body(child)
		if found:
			return found
	return null


## Fallback trigger when no GLB trigger node exists.
func _create_fallback_trigger(trigger_name: String, pos: Vector3, callback: Callable) -> void:
	var trigger := Area3D.new()
	trigger.name = trigger_name
	trigger.collision_layer = 0
	trigger.collision_mask = 2

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)

	trigger.body_entered.connect(callback)
	add_child(trigger)
	trigger.global_position = pos


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
