extends Node3D
## Valley Field 3D Controller — loads GLB models, reads portal nodes, handles
## grid cell transitions, key-gate mechanics, and section progression.

const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const MapOverlayScript := preload("res://scripts/3d/field/map_overlay.gd")

const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const ROTATE_CW := {"north": "east", "east": "south", "south": "west", "west": "north"}

var player: CharacterBody3D
var orbit_camera: Node3D
var _map_root: Node3D
var _world_env: WorldEnvironment
var _dir_light: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _transitioning := false
var _keys_collected: Dictionary = {}
var _current_cell: Dictionary = {}
var _portal_data: Dictionary = {}
var _rotation_deg: int = 0
var _map_overlay: CanvasLayer
var _blob_shadow: MeshInstance3D


func _ready() -> void:
	# Grab lighting nodes immediately so _process() applies TimeManager from frame 1
	_world_env = $WorldEnvironment
	_dir_light = $DirectionalLight3D
	_sky_material = _world_env.environment.sky.sky_material as ProceduralSkyMaterial
	TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light)

	var data: Dictionary = SceneManager.get_transition_data()
	var current_cell_pos: String = str(data.get("current_cell_pos", ""))
	var spawn_edge: String = str(data.get("spawn_edge", ""))
	_keys_collected = data.get("keys_collected", {})
	var map_overlay_visible: bool = data.get("map_overlay_visible", false)

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

	# Load GLB — resolve area folder from session
	var stage_id: String = str(_current_cell["stage_id"])
	var area_id: String = str(SessionManager.get_session().get("area_id", "gurhacia"))
	var area_cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, GridGenerator.AREA_CONFIG["gurhacia"])
	var map_path := "res://assets/environments/%s/%s.glb" % [area_cfg["folder"], stage_id]
	var packed_scene := load(map_path) as PackedScene
	if not packed_scene:
		push_error("[ValleyField] Failed to load map: %s" % map_path)
		_return_to_city()
		return

	_map_root = packed_scene.instantiate() as Node3D
	_map_root.name = "Map"

	# Apply grid rotation — positive Y rotation matches ROTATE_CW for the
	# model's coordinate convention (east=-X, west=+X, north=-Z, south=+Z).
	_rotation_deg = int(_current_cell.get("rotation", 0))
	_map_root.rotation.y = deg_to_rad(_rotation_deg)

	add_child(_map_root)
	_strip_embedded_lights(_map_root)
	_fix_materials(_map_root)
	await get_tree().process_frame

	# Setup collision from GLB -colonly meshes
	_setup_map_collision(_map_root)
	await get_tree().process_frame

	# Discover portal nodes (returns original GLB direction keys)
	_portal_data = _find_portal_data(_map_root)

	print("[ValleyField] ══════════════════════════════════════════")
	print("[ValleyField] CELL LOAD: %s  stage=%s" % [
		str(_current_cell.get("pos", "?")), stage_id])
	print("[ValleyField]   section: %d/%d (%s, area=%s)" % [
		section_idx + 1, sections.size(),
		str(section.get("type", "?")), str(section.get("area", "?"))])
	print("[ValleyField]   rotation_deg=%d  map_root.rotation.y=%.4f rad (%.1f°)" % [
		_rotation_deg, _map_root.rotation.y, rad_to_deg(_map_root.rotation.y)])
	print("[ValleyField]   spawn_edge='%s'" % spawn_edge)

	# Log raw portal data BEFORE remapping
	print("[ValleyField]   ── Raw portals (original GLB keys) ──")
	for key in _portal_data:
		var pd: Dictionary = _portal_data[key]
		print("[ValleyField]     '%s': spawn_global=%s  trigger_global=%s" % [
			key, pd["spawn_pos"], pd["trigger_pos"]])

	# Log portal node details (local vs global positions)
	var portals_node: Node3D = _find_child_by_name(_map_root, "portals")
	if portals_node:
		print("[ValleyField]   portals_node path: %s" % portals_node.get_path())
		print("[ValleyField]   portals_node global_pos=%s  local_pos=%s" % [
			portals_node.global_position, portals_node.position])
		for dir in ["north", "east", "south", "west"]:
			var sn: Node3D = _find_child_by_name(portals_node, "spawn_" + dir)
			if sn:
				print("[ValleyField]     spawn_%s: local=%s  global=%s  parent=%s" % [
					dir, sn.position, sn.global_position, sn.get_parent().name])

	# Remap portal keys from original GLB directions to grid directions
	if _rotation_deg != 0:
		print("[ValleyField]   ── Remapping (rotation=%d°) ──" % _rotation_deg)
		for dir in _portal_data:
			if dir != "default":
				var grid_dir := _original_to_grid_dir(dir, _rotation_deg)
				print("[ValleyField]     '%s' → '%s'" % [dir, grid_dir])
		_portal_data = _remap_portal_directions(_portal_data, _rotation_deg)

	# Log remapped portal data
	print("[ValleyField]   ── Final portals (grid keys) ──")
	for key in _portal_data:
		print("[ValleyField]     '%s': spawn=%s" % [key, _portal_data[key]["spawn_pos"]])

	# Determine warp_edge early (needed for spawn resolution)
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))

	# Spawn player
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	var spawn_reason := ""
	if not spawn_edge.is_empty() and _portal_data.has(spawn_edge):
		spawn_pos = _portal_data[spawn_edge]["spawn_pos"]
		spawn_rot = _dir_to_yaw(OPPOSITE[spawn_edge])
		spawn_reason = "entry from %s, facing %s" % [spawn_edge, OPPOSITE[spawn_edge]]
	elif _portal_data.has("default"):
		spawn_pos = _portal_data["default"]["spawn_pos"]
		var arrow: Node3D = _find_child_by_name(_map_root, "spawn_default_arrow")
		if arrow:
			spawn_rot = arrow.rotation.y
		spawn_reason = "default spawn"
	elif not warp_edge.is_empty() and _portal_data.has(OPPOSITE.get(warp_edge, "")):
		var entry_dir: String = OPPOSITE[warp_edge]
		spawn_pos = _portal_data[entry_dir]["spawn_pos"]
		spawn_rot = _dir_to_yaw(warp_edge)
		spawn_reason = "opposite of warp_edge=%s, spawn at %s facing %s" % [warp_edge, entry_dir, warp_edge]
	elif _portal_data.has("north"):
		spawn_pos = _portal_data["north"]["spawn_pos"]
		spawn_rot = _dir_to_yaw("south")
		spawn_reason = "fallback north portal, facing south"
	elif _portal_data.has("south"):
		spawn_pos = _portal_data["south"]["spawn_pos"]
		spawn_rot = _dir_to_yaw("north")
		spawn_reason = "fallback south portal, facing north"
	else:
		spawn_pos = Vector3(0, 1, 0)
		spawn_reason = "center fallback"

	print("[ValleyField]   ── Spawn Resolution ──")
	print("[ValleyField]     pos=%s  rot=%.2f rad (%.1f°)" % [
		spawn_pos, spawn_rot, rad_to_deg(spawn_rot)])
	print("[ValleyField]     reason: %s" % spawn_reason)
	print("[ValleyField]     _dir_to_yaw table: N=%.2f E=%.2f S=%.2f W=%.2f" % [
		_dir_to_yaw("north"), _dir_to_yaw("east"), _dir_to_yaw("south"), _dir_to_yaw("west")])

	var connections: Dictionary = _current_cell.get("connections", {})
	print("[ValleyField]   ── Grid Cell Data ──")
	print("[ValleyField]     connections: %s" % str(connections))
	print("[ValleyField]     warp_edge: '%s'" % warp_edge)
	print("[ValleyField]     cell keys: %s" % str(_current_cell.keys()))
	# Log the full cell dict (truncated for readability)
	for ck in _current_cell:
		if ck != "connections":
			print("[ValleyField]     cell.%s = %s" % [ck, str(_current_cell[ck])])
	print("[ValleyField] ══════════════════════════════════════════")

	_spawn_player(spawn_pos, spawn_rot)
	await get_tree().process_frame

	# Create gate triggers for each connection (entry edge gets delayed activation)
	for dir in connections:
		if not _portal_data.has(dir):
			continue

		# Check key-gate lock
		var is_locked := false
		if _current_cell.get("is_key_gate", false):
			var locked_dir: String = str(_current_cell.get("key_gate_direction", ""))
			if locked_dir == dir and not _keys_collected.has(_current_cell.get("pos", "")):
				is_locked = true

		if not is_locked:
			var is_entry: bool = (dir == spawn_edge)
			_create_gate_trigger(dir, str(connections[dir]), _portal_data[dir], is_entry)

	# Create exit trigger on end cell warp_edge
	if not warp_edge.is_empty() and _portal_data.has(warp_edge):
		_create_exit_trigger(warp_edge, _portal_data[warp_edge])

	# Place key pickup if this cell has one
	if _current_cell.get("has_key", false):
		var key_for: String = str(_current_cell.get("key_for_cell", ""))
		if not key_for.is_empty() and not _keys_collected.has(key_for):
			_create_key_pickup(key_for)

	# Map overlay (toggle with Tab, persists across cell transitions)
	_map_overlay = CanvasLayer.new()
	_map_overlay.layer = 100
	_map_overlay.visible = map_overlay_visible
	_map_overlay.name = "MapOverlay"
	add_child(_map_overlay)
	var map_panel := MapOverlayScript.new()
	map_panel.cells = cells
	map_panel.current_pos = str(_current_cell.get("pos", ""))
	map_panel.section_info = "Section %d (%s)" % [section_idx + 1, str(section.get("type", "?"))]
	_map_overlay.add_child(map_panel)

	# Hide debug marker meshes (disabled for testing portal visibility)
	#_hide_debug_markers(_map_root)


func _process(_delta: float) -> void:
	if _world_env and _sky_material and _dir_light:
		TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light)
	if _blob_shadow and player:
		_blob_shadow.global_position = Vector3(player.global_position.x, 0.05, player.global_position.z)


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


## Remap portal data keys from original GLB directions to grid (rotated) directions.
func _remap_portal_directions(portals: Dictionary, rotation_deg: int) -> Dictionary:
	var remapped := {}
	for dir in portals:
		if dir == "default":
			remapped["default"] = portals["default"]
		else:
			var grid_dir := _original_to_grid_dir(dir, rotation_deg)
			remapped[grid_dir] = portals[dir]
	return remapped


## Convert original GLB direction to grid direction (apply CW rotation).
func _original_to_grid_dir(original_dir: String, rotation_deg: int) -> String:
	var dir := original_dir
	var steps: int = int(rotation_deg / 90) % 4
	for _i in range(steps):
		dir = ROTATE_CW[dir]
	return dir


## Convert grid direction to original GLB direction (undo rotation = rotate CCW).
func _grid_to_original_dir(grid_dir: String, rotation_deg: int) -> String:
	var dir := grid_dir
	var steps: int = int(((360 - rotation_deg) % 360) / 90)
	for _i in range(steps):
		dir = ROTATE_CW[dir]
	return dir


func _find_child_by_name(node: Node, child_name: String) -> Node:
	for child in node.get_children():
		if child.name == child_name:
			return child
		var found := _find_child_by_name(child, child_name)
		if found:
			return found
	return null


func _dir_to_yaw(dir: String) -> float:
	# Model coordinate convention: east=-X, west=+X, north=-Z, south=+Z
	# Player movement: Vector3(sin(rot), 0, cos(rot))
	match dir:
		"north": return PI        # sin(PI)=0,  cos(PI)=-1  → -Z
		"south": return 0.0       # sin(0)=0,   cos(0)=1    → +Z
		"east": return -PI / 2.0  # sin(-PI/2)=-1, cos=0    → -X
		"west": return PI / 2.0   # sin(PI/2)=1,  cos=0     → +X
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

	# Blob shadow — dark circle under the player (unshaded, always visible)
	_blob_shadow = MeshInstance3D.new()
	var shadow_quad := QuadMesh.new()
	shadow_quad.size = Vector2(1.8, 1.8)
	shadow_quad.orientation = PlaneMesh.FACE_Y
	_blob_shadow.mesh = shadow_quad
	_blob_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow_shader := Shader.new()
	shadow_shader.code = \
		"shader_type spatial;\n" + \
		"render_mode unshaded, cull_disabled, depth_test_disabled;\n\n" + \
		"void fragment() {\n" + \
		"\tfloat dist = length(UV - vec2(0.5)) * 2.0;\n" + \
		"\tfloat alpha = (1.0 - smoothstep(0.5, 1.0, dist)) * 0.35;\n" + \
		"\tALBEDO = vec3(0.0);\n" + \
		"\tALPHA = alpha;\n" + \
		"}\n"
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = shadow_shader
	_blob_shadow.material_override = shadow_mat
	_blob_shadow.global_position = Vector3(pos.x, 0.05, pos.z)
	add_child(_blob_shadow)



func _setup_map_collision(root: Node) -> void:
	_configure_collision_nodes(root)


func _strip_embedded_lights(node: Node) -> void:
	## Remove any lights or environments baked into GLB models so the scene-level
	## WorldEnvironment + DirectionalLight3D (controlled by TimeManager) are the
	## sole authority on lighting.
	var to_remove: Array[Node] = []
	_collect_embedded_lights(node, to_remove)
	for n in to_remove:
		n.queue_free()


func _collect_embedded_lights(node: Node, out: Array[Node]) -> void:
	if node is DirectionalLight3D or node is OmniLight3D or node is SpotLight3D or node is WorldEnvironment:
		out.append(node)
		return
	for child in node.get_children():
		_collect_embedded_lights(child, out)


func _fix_materials(node: Node) -> void:
	## Make stage materials unshaded so pre-baked vertex colors display at full
	## brightness regardless of mesh normals or enclosure geometry.  TimeManager
	## applies a screen-space tint overlay for day/night atmosphere instead.
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				new_mat.texture_repeat = true
				mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_fix_materials(child)


func _configure_collision_nodes(node: Node) -> bool:
	var found_floor := false
	if node is StaticBody3D:
		if node.name == "collision_floor":
			found_floor = true
		# Skip trigger boxes and gate markers — not walls
		if str(node.name).begins_with("trigger_") or str(node.name).begins_with("gate_"):
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


func _create_gate_trigger(direction: String, target_cell_pos: String, _portal: Dictionary, delayed: bool = false) -> void:
	var entry_edge: String = OPPOSITE[direction]
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] ▶ TRIGGER: grid_dir=%s → cell %s (entry_edge=%s)" % [
				direction, target_cell_pos, entry_edge])
			_transition_to_cell(target_cell_pos, entry_edge)

	# Convert grid direction to original GLB direction for node lookup
	var original_dir := _grid_to_original_dir(direction, _rotation_deg)
	print("[ValleyField]   trigger: grid=%s → original=%s  target=%s  delayed=%s" % [
		direction, original_dir, target_cell_pos, delayed])
	var trigger_name := "trigger_" + original_dir + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + original_dir)
	if trigger_group:
		print("[ValleyField]     found '%s' at global=%s" % [trigger_name, trigger_group.global_position])
		var area := _convert_static_to_area(trigger_group)
		if area:
			area.name = "GateTrigger_%s" % direction
			if delayed:
				area.monitoring = false
			area.body_entered.connect(callback)
			if delayed:
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					if is_instance_valid(area):
						area.monitoring = true
				)
			return
	else:
		print("[ValleyField]     WARNING: no trigger node '%s' found!" % trigger_name)

	# Fallback: create programmatic trigger at portal position
	print("[ValleyField]     using fallback trigger at %s" % _portal["trigger_pos"])
	_create_fallback_trigger("GateTrigger_%s" % direction, _portal["trigger_pos"], callback, delayed)


func _create_exit_trigger(direction: String, _portal: Dictionary) -> void:
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] Player entered exit trigger")
			_on_end_reached()

	# Convert grid direction to original GLB direction for node lookup
	var original_dir := _grid_to_original_dir(direction, _rotation_deg)
	var trigger_name := "trigger_" + original_dir + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + original_dir)
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
##   - trigger_{dir}_box-colonly (StaticBody3D with CollisionShape3D)
##   - trigger_{dir}_vis / trigger_{dir}_wire (MeshInstance3D, visual)
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
func _create_fallback_trigger(trigger_name: String, pos: Vector3, callback: Callable, delayed: bool = false) -> void:
	var trigger := Area3D.new()
	trigger.name = trigger_name
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	if delayed:
		trigger.monitoring = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)

	trigger.body_entered.connect(callback)
	add_child(trigger)
	trigger.global_position = pos

	if delayed:
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(trigger):
				trigger.monitoring = true
		)


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
		"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
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
			"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
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
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if _map_overlay:
			_map_overlay.visible = not _map_overlay.visible
		get_viewport().set_input_as_handled()
