extends Node3D
## Valley Field 3D Controller — loads GLB models, reads portal nodes, handles
## grid cell transitions, key-gate mechanics, and section progression.

const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const MapOverlayScript := preload("res://scripts/3d/field/map_overlay.gd")
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")
const StartWarpScript := preload("res://scripts/3d/elements/start_warp.gd")
const AreaWarpScript := preload("res://scripts/3d/elements/area_warp.gd")
const GateScript := preload("res://scripts/3d/elements/gate.gd")
const KeyPickupScript := preload("res://scripts/3d/elements/key_pickup.gd")
const KeyGateScript := preload("res://scripts/3d/elements/key_gate.gd")
const WaypointScript := preload("res://scripts/3d/elements/waypoint.gd")
const RoomMinimapScript := preload("res://scripts/3d/field/room_minimap.gd")
const BoxScript := preload("res://scripts/3d/elements/box.gd")
const FenceScript := preload("res://scripts/3d/elements/fence.gd")
const StepSwitchScript := preload("res://scripts/3d/elements/step_switch.gd")
const EnemySpawnScript := preload("res://scripts/3d/elements/enemy_spawn.gd")
const DropMesetaScript := preload("res://scripts/3d/elements/drop_meseta.gd")
const DropItemScript := preload("res://scripts/3d/elements/drop_item.gd")

const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const DIRECTIONS := ["north", "east", "south", "west"]

var player: CharacterBody3D
var orbit_camera: Node3D
var _map_root: Node3D
var _world_env: WorldEnvironment
var _dir_light: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _transitioning := false
var _keys_collected: Dictionary = {}  # cell_pos → true (key pickup, prevents respawn)
var _gates_opened: Dictionary = {}   # cell_pos → true (gate opened by player, stays open on re-entry)
var _current_cell: Dictionary = {}
var _portal_data: Dictionary = {}
var _map_overlay: CanvasLayer
var _room_minimap: Control
var _blob_shadow: MeshInstance3D
var _texture_fixes: Array = []
var _spawn_edge: String = ""
var _rotation_deg: int = 0
var _visited_cells: Dictionary = {}  # cell_pos → true
var _key_hud_label: Label
var _key_hud_icon: Label
var _key_hud_panel: PanelContainer
var _total_keys_in_field: int = 0

# Room objects
var _room_enemies: Array = []  # EnemySpawn nodes in current room
var _fence_links: Dictionary = {}  # link_id → { "fences": [], "switches": [] }
var _room_gates_locked: Array = []  # Gate elements locked until enemies cleared

# Debug toggle state
var _show_triggers := false
var _show_gate_markers := false
var _show_floor_collision := false
var _show_spawn_points := false
var _debug_trigger_meshes: Array = []
var _debug_gate_meshes: Array = []
var _debug_collision_meshes: Array = []
var _debug_spawn_meshes: Array = []
var _debug_panel: PanelContainer


func _ready() -> void:
	# Grab lighting nodes immediately so _process() applies TimeManager from frame 1
	_world_env = $WorldEnvironment
	_dir_light = $DirectionalLight3D
	_sky_material = _world_env.environment.sky.sky_material as ProceduralSkyMaterial
	TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light)

	var data: Dictionary = SceneManager.get_transition_data()
	var current_cell_pos: String = str(data.get("current_cell_pos", ""))
	_spawn_edge = str(data.get("spawn_edge", ""))
	var spawn_edge: String = _spawn_edge
	_keys_collected = data.get("keys_collected", {})
	_visited_cells = data.get("visited_cells", {})
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

	# Track visited cells
	_visited_cells[current_cell_pos] = true

	# Load GLB — resolve area folder from session
	var stage_id: String = str(_current_cell["stage_id"])
	TimeManager.stage_label = stage_id
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

	# Apply cell rotation to the GLB model
	_rotation_deg = int(_current_cell.get("rotation", 0))
	if _rotation_deg != 0:
		_map_root.rotation.y = deg_to_rad(_rotation_deg)

	# Load texture fixes from config JSON
	_texture_fixes = _load_texture_fixes(area_cfg["folder"], stage_id)

	add_child(_map_root)
	_strip_embedded_lights(_map_root)
	_fix_materials(_map_root)
	await get_tree().process_frame

	# Setup collision from GLB -colonly meshes
	_setup_map_collision(_map_root)
	await get_tree().process_frame

	# Discover portal nodes (returns original GLB direction keys)
	var original_portal_data: Dictionary = _find_portal_data(_map_root)

	# Remap portal keys from original GLB directions to grid-space directions.
	# Portal positions are already correct (global_position reflects the rotated model).
	if _rotation_deg != 0:
		_portal_data = {}
		for orig_dir in original_portal_data:
			if orig_dir == "default":
				_portal_data["default"] = original_portal_data["default"]
			else:
				var grid_dir: String = _rotate_dir(orig_dir, _rotation_deg)
				_portal_data[grid_dir] = original_portal_data[orig_dir]
	else:
		_portal_data = original_portal_data

	# Quest editor uses mirrored east/west convention (east=+X) while GLB nodes
	# use standard convention (west=+X). Remap cell connections and key_gate_direction
	# to match actual portal data keys so gates/triggers are placed correctly.
	_remap_quest_directions(stage_id, area_id)

	# For quest mode: derive spawn_edge from target cell's own connections.
	# The source cell's OPPOSITE[exit_dir] may not match target portal data keys
	# due to rotation-dependent direction conventions.
	var from_cell_pos: String = str(data.get("from_cell_pos", ""))
	if not from_cell_pos.is_empty() and str(SessionManager.get_session().get("type", "")) == "quest":
		var connections: Dictionary = _current_cell.get("connections", {})
		for dir in connections:
			if str(connections[dir]) == from_cell_pos:
				spawn_edge = dir
				_spawn_edge = dir
				break

	print("[ValleyField] ══════════════════════════════════════════")
	print("[ValleyField] CELL LOAD: %s  stage=%s" % [
		str(_current_cell.get("pos", "?")), stage_id])
	print("[ValleyField]   section: %d/%d (%s, area=%s)" % [
		section_idx + 1, sections.size(),
		str(section.get("type", "?")), str(section.get("area", "?"))])
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

	# Log portal data
	print("[ValleyField]   ── Final portals ──")
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
	# Key-gate direction trigger starts disabled — enabled when gate opens
	var is_key_gate: bool = _current_cell.get("is_key_gate", false)
	var key_gate_dir: String = str(_current_cell.get("key_gate_direction", ""))
	for dir in connections:
		if not _portal_data.has(dir):
			continue
		var is_entry: bool = (dir == spawn_edge)
		var is_locked_gate: bool = is_key_gate and dir == key_gate_dir and not _gates_opened.has(str(_current_cell.get("pos", "")))
		_create_gate_trigger(dir, str(connections[dir]), _portal_data[dir], is_entry, is_locked_gate)

	# Create exit trigger on end cell warp_edge
	if not warp_edge.is_empty() and _portal_data.has(warp_edge):
		_create_exit_trigger(warp_edge, _portal_data[warp_edge])

	# Place key pickup if this cell has one
	if _current_cell.get("has_key", false):
		var key_for: String = str(_current_cell.get("key_for_cell", ""))
		if not key_for.is_empty() and not _keys_collected.has(key_for):
			_create_key_pickup(key_for)

	_spawn_field_elements()
	_spawn_cell_objects()
	_setup_debug_panel()
	_setup_key_hud(cells)

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

	_room_minimap = RoomMinimapScript.new()
	_room_minimap.setup(stage_id, area_cfg["folder"], _portal_data,
		_current_cell.get("connections", {}),
		str(_current_cell.get("warp_edge", "")), _map_root, _rotation_deg)
	_map_overlay.add_child(_room_minimap)
	map_panel.top_offset = 200.0

	# Hide debug marker meshes (disabled for testing portal visibility)
	#_hide_debug_markers(_map_root)


func _process(_delta: float) -> void:
	if _world_env and _sky_material and _dir_light:
		TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light)
	if _blob_shadow and player:
		_blob_shadow.global_position = Vector3(player.global_position.x, 0.05, player.global_position.z)
	if _room_minimap and player and _map_root:
		_room_minimap.update_player(player.global_position, player.player_rotation, _map_root)


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
			# Find gate marker node (gate_{dir} or gate_{dir}-colonly)
			var gate_node: Node3D = _find_child_by_name(map_root, "gate_" + dir)
			var gate_pos: Vector3 = gate_node.global_position if gate_node else trigger_pos
			var gate_rot: Vector3 = gate_node.global_rotation if gate_node else Vector3.ZERO
			# Find gate_box mesh for collision generation
			var gate_box_node: MeshInstance3D = null
			if gate_node:
				var box_child: Node = _find_child_by_name(gate_node, "gate_" + dir + "_box")
				if box_child is MeshInstance3D:
					gate_box_node = box_child as MeshInstance3D
			portals[dir] = {
				"spawn_pos": spawn_node.global_position,
				"trigger_pos": trigger_pos,
				"gate_pos": gate_pos,
				"gate_rot": gate_rot,
				"gate_box_node": gate_box_node,
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
	# Model coordinate convention: east=-X, west=+X, north=-Z, south=+Z
	# Player movement: Vector3(sin(rot), 0, cos(rot))
	match dir:
		"north": return PI        # sin(PI)=0,  cos(PI)=-1  → -Z
		"south": return 0.0       # sin(0)=0,   cos(0)=1    → +Z
		"east": return -PI / 2.0  # sin(-PI/2)=-1, cos=0    → -X
		"west": return PI / 2.0   # sin(PI/2)=1,  cos=0     → +X
	return 0.0


## Rotate a direction CW by degrees (0/90/180/270).
func _rotate_dir(dir: String, rotation: int) -> String:
	if rotation == 0:
		return dir
	var idx: int = DIRECTIONS.find(dir)
	if idx < 0:
		return dir
	var steps: int = (rotation / 90) % 4
	return DIRECTIONS[(idx + steps) % 4]


## Convert a grid-space direction back to the original GLB direction.
## Reverse rotation: apply (360 - rotation) CW.
func _grid_to_original_dir(grid_dir: String, rotation: int) -> String:
	if rotation == 0:
		return grid_dir
	return _rotate_dir(grid_dir, (360 - rotation) % 360)


## Remap quest cell directions from psz-sketch convention to GLB convention.
## The quest editor uses mirrored east/west (east=+X, west=-X) while GLB portal
## nodes use standard convention (east=-X, west=+X). North/south are the same.
## Only applies to quest sessions — generated fields already use GLB directions.
func _remap_quest_directions(_stage_id: String, _area_id: String) -> void:
	if str(SessionManager.get_session().get("type", "")) != "quest":
		return

	var connections: Dictionary = _current_cell.get("connections", {})
	if connections.is_empty():
		return

	# psz-sketch uses east=+X, GLB uses west=+X (E↔W mirrored).
	# The effective swap after rotation R is:
	#   R=0°/180° (even 90° steps): swap east↔west
	#   R=90°/270° (odd 90° steps): swap north↔south
	var rotation_steps: int = (_rotation_deg / 90) % 4
	var swap_ns: bool = (rotation_steps % 2 == 1)

	var new_connections: Dictionary = {}
	for dir in connections:
		new_connections[_psz_to_glb_dir(dir, swap_ns)] = connections[dir]
	_current_cell["connections"] = new_connections

	var kgd: String = str(_current_cell.get("key_gate_direction", ""))
	if not kgd.is_empty():
		_current_cell["key_gate_direction"] = _psz_to_glb_dir(kgd, swap_ns)

	print("[ValleyField] Quest remap (rot=%d°, swap_%s): connections=%s  key_gate_dir=%s" % [
		_rotation_deg, "ns" if swap_ns else "ew",
		str(new_connections), str(_current_cell.get("key_gate_direction", ""))])


## Convert a psz-sketch direction label to GLB portal data convention.
func _psz_to_glb_dir(dir: String, swap_ns: bool) -> String:
	if swap_ns:
		if dir == "north": return "south"
		elif dir == "south": return "north"
	else:
		if dir == "east": return "west"
		elif dir == "west": return "east"
	return dir


## Rotate a point around Y axis by degrees (CW when viewed from above).
func _rotate_point(point: Vector3, degrees: int) -> Vector3:
	var rad := deg_to_rad(float(degrees))
	var cos_a := cos(rad)
	var sin_a := sin(rad)
	return Vector3(
		point.x * cos_a - point.z * sin_a,
		point.y,
		point.x * sin_a + point.z * cos_a
	)


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


func _load_texture_fixes(folder: String, stage_id: String) -> Array:
	var config_path := "res://assets/environments/%s/%s_config.json" % [folder, stage_id]
	if not FileAccess.file_exists(config_path):
		return []
	var file := FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return []
	var data: Dictionary = json.data
	var fixes: Array = data.get("textureFixes", [])
	if fixes.size() > 0:
		print("[ValleyField] Loaded %d texture fixes from %s" % [fixes.size(), config_path])
	return fixes


func _find_texture_fix_for_mesh(mesh_name: String) -> Dictionary:
	for fix in _texture_fixes:
		var mesh_names: Array = fix.get("meshNames", [])
		for mn in mesh_names:
			if str(mn) == mesh_name:
				return fix
	return {}


static func _wrap_mode_int(mode: String) -> int:
	match mode:
		"mirror": return 1
		"clamp": return 2
	return 0  # repeat


func _load_fix_texture(tex_file: String) -> Texture2D:
	if tex_file.is_empty():
		return null
	var area_id_local: String = str(SessionManager.get_session().get("area_id", "gurhacia"))
	var area_cfg_local: Dictionary = GridGenerator.AREA_CONFIG.get(area_id_local, GridGenerator.AREA_CONFIG["gurhacia"])
	var tex_path := "res://assets/environments/%s/%s" % [area_cfg_local["folder"], tex_file]
	if ResourceLoader.exists(tex_path):
		return load(tex_path) as Texture2D
	return null


func _fix_materials(node: Node) -> void:
	## Make stage materials unshaded so pre-baked vertex colors display at full
	## brightness regardless of mesh normals or enclosure geometry.  TimeManager
	## applies a screen-space tint overlay for day/night atmosphere instead.
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fix := _find_texture_fix_for_mesh(mesh_inst.name)
		var tex_file: String = str(fix.get("textureFile", ""))
		var is_waterfall := "_fall" in tex_file
		var needs_shader := not fix.is_empty() and (
			is_waterfall or
			str(fix.get("wrapS", "repeat")) == "mirror" or
			str(fix.get("wrapT", "repeat")) == "mirror")
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				if is_waterfall:
					# Waterfall: additive blend + scrolling UV + replacement texture
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = WATERFALL_SHADER
					var fix_tex: Texture2D = _load_fix_texture(tex_file)
					if fix_tex:
						print("[FixMat] Waterfall texture: %s (%dx%d)" % [
							tex_file, fix_tex.get_width(), fix_tex.get_height()])
						shader_mat.set_shader_parameter("albedo_texture", fix_tex)
					elif std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					shader_mat.set_shader_parameter("uv_scroll", Vector2(0.0, -0.25))
					shader_mat.render_priority = 1
					mesh_inst.set_surface_override_material(i, shader_mat)
				elif needs_shader:
					# Mirror wrap: custom shader with wrap modes
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = TEXTURE_FIX_SHADER
					var fix_tex: Texture2D = _load_fix_texture(tex_file)
					if fix_tex:
						shader_mat.set_shader_parameter("albedo_texture", fix_tex)
					elif std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					shader_mat.set_shader_parameter("wrap_s", _wrap_mode_int(str(fix.get("wrapS", "repeat"))))
					shader_mat.set_shader_parameter("wrap_t", _wrap_mode_int(str(fix.get("wrapT", "repeat"))))
					mesh_inst.set_surface_override_material(i, shader_mat)
				else:
					var new_mat := std_mat.duplicate() as StandardMaterial3D
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					new_mat.alpha_scissor_threshold = 0.1
					new_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
					new_mat.texture_repeat = true
					if not fix.is_empty():
						new_mat.uv1_scale = Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0)
						new_mat.uv1_offset = Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0)
						if str(fix.get("wrapS", "repeat")) == "clamp" or str(fix.get("wrapT", "repeat")) == "clamp":
							new_mat.texture_repeat = false
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


func _create_gate_trigger(direction: String, target_cell_pos: String, _portal: Dictionary, delayed: bool = false, locked: bool = false) -> void:
	var entry_edge: String = OPPOSITE[direction]
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] ▶ TRIGGER: grid_dir=%s → cell %s (entry_edge=%s)" % [
				direction, target_cell_pos, entry_edge])
			_transition_to_cell(target_cell_pos, entry_edge)

	# Convert grid direction to original GLB direction for node name lookup
	var orig_dir: String = _grid_to_original_dir(direction, _rotation_deg)
	print("[ValleyField]   trigger: dir=%s  orig=%s  target=%s  delayed=%s  locked=%s" % [
		direction, orig_dir, target_cell_pos, delayed, locked])
	var trigger_name := "trigger_" + orig_dir + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + orig_dir)
	if trigger_group:
		print("[ValleyField]     found '%s' at global=%s" % [trigger_name, trigger_group.global_position])
		var area := _convert_static_to_area(trigger_group)
		if area:
			area.name = "GateTrigger_%s" % direction
			if delayed or locked:
				area.monitoring = false
			area.body_entered.connect(callback)
			if delayed and not locked:
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

	# Convert grid direction to original GLB direction for node name lookup
	var orig_dir: String = _grid_to_original_dir(direction, _rotation_deg)
	var trigger_name := "trigger_" + orig_dir + "-area"
	var trigger_group: Node3D = _find_child_by_name(_map_root, trigger_name)
	if not trigger_group:
		trigger_group = _find_child_by_name(_map_root, "trigger_" + orig_dir)
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
	# Use proper KeyPickup element with o0c_key.glb model
	var key_item_id := "key_%s" % key_for_cell.replace(",", "_")
	var key := KeyPickupScript.new()
	key.key_id = key_item_id
	key.name = "KeyPickup_%s" % key_for_cell

	# Place key at authored position from quest editor, or fall back to heuristic
	var key_pos := Vector3.ZERO
	var authored_pos: Array = _current_cell.get("key_position", [])
	if authored_pos.size() == 3:
		# Use authored position from quest editor (stage-local coordinates)
		key_pos = Vector3(float(authored_pos[0]), float(authored_pos[1]), float(authored_pos[2]))
		# Apply cell rotation if the stage is rotated
		if _rotation_deg != 0:
			key_pos = _rotate_point(key_pos, _rotation_deg)
		print("[ValleyField] Key using authored position: %s (rotated %d°)" % [key_pos, _rotation_deg])
	else:
		# Fallback: midpoint between portal spawns
		var portal_positions: Array[Vector3] = []
		for dir in _portal_data:
			if dir != "default":
				portal_positions.append(_portal_data[dir]["spawn_pos"])
		if portal_positions.size() >= 2:
			var sum := Vector3.ZERO
			for p in portal_positions:
				sum += p
			key_pos = sum / float(portal_positions.size())
		elif portal_positions.size() == 1:
			key_pos = portal_positions[0]
		key_pos.y = 0.5
		print("[ValleyField] Key using fallback midpoint: %s" % key_pos)

	add_child(key)
	key.global_position = key_pos

	# Track collection for grid state and update HUD
	key.interacted.connect(func(_player: Node3D) -> void:
		_keys_collected[key_for_cell] = true
		_update_key_hud()
	)
	print("[ValleyField] Key pickup spawned for cell %s at %s (id=%s)" % [
		key_for_cell, key_pos, key_item_id])


func _setup_key_hud(cells: Array) -> void:
	# Count total keys in this field section
	_total_keys_in_field = 0
	for cell in cells:
		if cell.get("has_key", false):
			_total_keys_in_field += 1

	if _total_keys_in_field == 0:
		return

	var canvas := CanvasLayer.new()
	canvas.layer = 98
	canvas.name = "KeyHUD"
	add_child(canvas)

	# Panel in top-right, below meseta
	_key_hud_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.08, 0.08, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.9, 0.3, 0.3, 0.6)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 10.0
	style.content_margin_top = 6.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 6.0
	_key_hud_panel.add_theme_stylebox_override("panel", style)
	_key_hud_panel.anchor_left = 1.0
	_key_hud_panel.anchor_right = 1.0
	_key_hud_panel.offset_left = -120
	_key_hud_panel.offset_right = -12
	_key_hud_panel.offset_top = 56

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_key_hud_panel.add_child(hbox)

	_key_hud_icon = Label.new()
	_key_hud_icon.text = "KEY"
	var icon_settings := LabelSettings.new()
	icon_settings.font_color = Color(1.0, 0.3, 0.3)
	icon_settings.font_size = 13
	_key_hud_icon.label_settings = icon_settings
	hbox.add_child(_key_hud_icon)

	_key_hud_label = Label.new()
	_key_hud_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var label_settings := LabelSettings.new()
	label_settings.font_color = Color(1.0, 1.0, 1.0)
	label_settings.font_size = 14
	_key_hud_label.label_settings = label_settings
	hbox.add_child(_key_hud_label)

	canvas.add_child(_key_hud_panel)
	_update_key_hud()


func _update_key_hud() -> void:
	if not _key_hud_label or _total_keys_in_field == 0:
		return
	var collected: int = _keys_collected.size()
	_key_hud_label.text = "%d / %d" % [collected, _total_keys_in_field]


func _unlock_key_gates(_key_item_id: String) -> void:
	# KeyGates are opened by player interaction (E key), not automatically.
	# This is kept as a no-op for potential future use.
	pass


## Apply storybook-style material fixup to gate elements.
## Duplicates all materials (prevents shared-resource mutation) and applies
## UV scale/offset correction for the o0c_0_gatet frame texture.
func _fixup_gate_materials(element: GameElement) -> void:
	if not element.model:
		return
	_fixup_gate_recursive(element.model)


func _fixup_gate_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std_mat := mat as StandardMaterial3D
			var dup := std_mat.duplicate() as StandardMaterial3D
			mesh_inst.set_surface_override_material(i, dup)
			# UV fixup for gate frame texture (matches storybook TEXTURE_FIXUPS)
			if dup.albedo_texture and "o0c_0_gatet" in dup.albedo_texture.resource_path:
				dup.uv1_scale = Vector3(1, 2, 1)
				dup.uv1_offset = Vector3(0.56, 0.8, 0)
	for child in node.get_children():
		_fixup_gate_recursive(child)


## Force all materials on a gate element to opaque depth draw so they don't
## break depth buffer for geometry behind/below them (e.g. water plane).
## GLB textures often have alpha channels causing auto-imported transparency.
func _fix_gate_depth(gate: Node3D) -> void:
	if not gate is GameElement:
		return
	var ge: GameElement = gate as GameElement
	ge.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			# Skip the laser material (identified by texture name)
			if std_mat.albedo_texture and "o0c_1_gate" in std_mat.albedo_texture.resource_path:
				return
			# Force fully opaque rendering
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	)


func _spawn_field_elements() -> void:
	var connections: Dictionary = _current_cell.get("connections", {})
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))
	var is_key_gate: bool = _current_cell.get("is_key_gate", false)
	var key_gate_dir: String = str(_current_cell.get("key_gate_direction", ""))

	# StartWarp on is_start cells at the entry portal
	if _current_cell.get("is_start", false):
		var start_warp := StartWarpScript.new()
		start_warp.auto_collect = false
		var start_pos := Vector3.ZERO
		var start_rot := 0.0
		if _portal_data.has("default"):
			start_pos = _portal_data["default"]["spawn_pos"]
			var arrow: Node3D = _find_child_by_name(_map_root, "spawn_default_arrow")
			if arrow:
				start_rot = arrow.rotation.y
		else:
			var entry_dir: String = str(OPPOSITE.get(warp_edge, ""))
			if not entry_dir.is_empty() and _portal_data.has(entry_dir):
				start_pos = _portal_data[entry_dir]["spawn_pos"]
				start_rot = _dir_to_yaw(warp_edge)
			else:
				for dir in _portal_data:
					if dir != "default":
						start_pos = _portal_data[dir]["spawn_pos"]
						start_rot = _dir_to_yaw(str(OPPOSITE.get(dir, "south")))
						break
		add_child(start_warp)
		start_warp.global_position = Vector3(start_pos.x, 0.0, start_pos.z)
		start_warp.rotation.y = start_rot

	# AreaWarp on end cells at warp_edge exit
	if not warp_edge.is_empty() and _portal_data.has(warp_edge):
		var area_warp := AreaWarpScript.new()
		area_warp.auto_collect = false
		area_warp.element_state = "open"
		add_child(area_warp)
		area_warp.global_position = _portal_data[warp_edge].get("gate_pos", _portal_data[warp_edge]["trigger_pos"])
		area_warp.rotation.y = _dir_to_yaw(warp_edge) + PI

	# Exit warp on end cells WITHOUT warp_edge (quest dead-end rooms)
	if _current_cell.get("is_end", false) and warp_edge.is_empty():
		_spawn_end_cell_exit(connections)

	# Gates and Waypoints at each connection trigger (skip warp_edge)
	print("[FieldElements] spawn_edge='%s' warp_edge='%s' connections=%s" % [
		_spawn_edge, warp_edge, str(connections)])
	for dir in connections:
		if dir == warp_edge:
			print("[FieldElements]   skip %s (warp_edge)" % dir)
			continue
		if not _portal_data.has(dir):
			print("[FieldElements]   skip %s (no portal data)" % dir)
			continue
		var trigger_pos: Vector3 = _portal_data[dir]["trigger_pos"]
		var gate_pos: Vector3 = _portal_data[dir].get("gate_pos", trigger_pos)

		# Key-gate — use KeyGate element (o0c_gatet.glb) with collision from GLB gate_box
		if is_key_gate and dir == key_gate_dir:
			var key_for_cell: String = str(_current_cell.get("pos", ""))
			var key_item_id := "key_%s" % key_for_cell.replace(",", "_")
			var gate_rot: Vector3 = _portal_data[dir].get("gate_rot", Vector3.ZERO)
			var kg := KeyGateScript.new()
			kg.required_key_id = key_item_id
			kg.name = "KeyGate_%s" % dir
			add_child(kg)
			kg.global_position = gate_pos
			# Use GLB gate node's rotation (not hardcoded)
			kg.rotation = gate_rot
			# Create collision from GLB gate_box mesh
			var gate_box_node: MeshInstance3D = _portal_data[dir].get("gate_box_node", null) as MeshInstance3D
			if gate_box_node and gate_box_node.mesh:
				var collision := StaticBody3D.new()
				collision.name = "KeyGateCollision_%s" % dir
				collision.collision_layer = 1
				collision.collision_mask = 0
				var trimesh_shape := gate_box_node.mesh.create_trimesh_shape()
				var shape_node := CollisionShape3D.new()
				shape_node.shape = trimesh_shape
				collision.add_child(shape_node)
				# Position collision at the gate_box's global transform
				gate_box_node.get_parent().add_child(collision)
				collision.global_transform = gate_box_node.global_transform
				kg.collision_body = collision
				print("[FieldElements]   GLB gate_box collision created at %s" % collision.global_position)
			# Apply storybook-style material fixup (duplicate + UV fix for frame texture)
			_fixup_gate_materials(kg)
			kg._setup_laser_material()
			kg._apply_state()
			_fix_gate_depth(kg)
			# Only auto-open if gate was previously opened by player (re-entry)
			if _gates_opened.has(key_for_cell):
				kg.open()
			# Enable the locked gate trigger when the key gate opens
			var gate_trigger_name := "GateTrigger_%s" % dir
			var cell_pos_for_gate := key_for_cell
			kg.state_changed.connect(func(_old: String, new_state: String) -> void:
				if new_state == "open":
					_gates_opened[cell_pos_for_gate] = true
					var trigger := _find_child_by_name(self, gate_trigger_name) as Area3D
					if trigger:
						trigger.monitoring = true
						print("[ValleyField] KeyGate opened → trigger '%s' enabled, gate tracked" % gate_trigger_name)
			)
			print("[FieldElements] ── KEY GATE DONE ──")
		else:
			# Regular gate — open if entry direction or target cell already visited
			var target_visited: bool = _visited_cells.has(str(connections[dir]))
			var is_open: bool = (dir == _spawn_edge) or target_visited
			var gate := GateScript.new()
			add_child(gate)
			gate.global_position = gate_pos
			gate.rotation = _portal_data[dir].get("gate_rot", Vector3.ZERO)
			_fixup_gate_materials(gate)
			gate._setup_laser_material()
			if is_open:
				gate.open()
			else:
				gate.collision_body.collision_layer = 0
			_fix_gate_depth(gate)

		# Waypoint — navigation marker inside the load trigger area
		var wp_pos := Vector3(trigger_pos.x, 1.5, trigger_pos.z)
		var waypoint := WaypointScript.new()
		add_child(waypoint)
		waypoint.global_position = wp_pos
		waypoint._base_y = waypoint.position.y  # Re-capture after repositioning
		# Face into the room (opposite of exit direction) so front faces the player
		var opp_dir: String = OPPOSITE[dir]
		waypoint.rotation.y = _dir_to_yaw(opp_dir)
		# Disable backface culling so it's visible from any angle
		waypoint.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		)
		# Determine waypoint state from visited history
		var target_cell_pos: String = str(connections[dir])
		var wp_state: String
		if dir == _spawn_edge:
			waypoint.mark_unvisited()
			wp_state = "came_from"
		elif _visited_cells.has(target_cell_pos):
			waypoint.mark_visited()
			wp_state = "visited_prior"
		else:
			waypoint.mark_new()
			wp_state = "unvisited"
		print("[Waypoint] dir=%s → target_cell=%s  state=%s" % [dir, target_cell_pos, wp_state])


func _spawn_end_cell_exit(connections: Dictionary) -> void:
	## Spawn an AreaWarp + exit trigger on quest end cells that have no warp_edge.
	## Finds a dead-end portal direction (not used by connections) for placement,
	## or falls back to default spawn / room center.
	var exit_pos := Vector3.ZERO
	var exit_rot := 0.0
	var exit_dir := ""

	# Try to find a portal direction that isn't a connection (dead-end side)
	for dir in ["south", "east", "west", "north"]:
		if not connections.has(dir) and _portal_data.has(dir):
			exit_dir = dir
			exit_pos = _portal_data[dir].get("gate_pos", _portal_data[dir]["trigger_pos"])
			exit_rot = _dir_to_yaw(dir) + PI
			break

	# Fallback to default spawn
	if exit_dir.is_empty() and _portal_data.has("default"):
		exit_pos = _portal_data["default"]["spawn_pos"]
		var arrow: Node3D = _find_child_by_name(_map_root, "spawn_default_arrow")
		if arrow:
			exit_rot = arrow.rotation.y

	# Fallback to room center
	if exit_dir.is_empty() and not _portal_data.has("default"):
		exit_pos = Vector3(0, 0, 0)

	# Spawn AreaWarp
	var area_warp := AreaWarpScript.new()
	area_warp.auto_collect = false
	area_warp.element_state = "open"
	add_child(area_warp)
	area_warp.global_position = exit_pos
	area_warp.rotation.y = exit_rot

	# Create exit trigger at same position
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] Player entered end-cell exit warp")
			_on_end_reached()

	_create_fallback_trigger("EndCellExit", exit_pos, callback, true)
	print("[FieldElements] End cell exit warp at %s (dir=%s)" % [exit_pos, exit_dir])


## Spawn placed objects (boxes, enemies, fences, switches) from quest cell data.
func _spawn_cell_objects() -> void:
	var objects: Array = _current_cell.get("objects", [])
	if objects.is_empty():
		return

	print("[CellObjects] Spawning %d objects" % objects.size())
	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		var pos_arr: Array = obj.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

		# Apply cell rotation to object position
		if _rotation_deg != 0:
			pos = _rotate_point(pos, _rotation_deg)

		var obj_rot: float = float(obj.get("rotation", 0))
		# Add cell rotation to object rotation
		if _rotation_deg != 0:
			obj_rot += _rotation_deg

		match obj_type:
			"box", "rare_box":
				_spawn_box(pos, obj_type == "rare_box")
			"enemy":
				var enemy_id: String = str(obj.get("enemy_id", "lizard"))
				_spawn_enemy(pos, enemy_id)
			"fence":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_fence(pos, obj_rot, link_id)
			"step_switch":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_switch(pos, link_id)

	# Wire fence↔switch links
	_wire_fence_links()

	# If room has enemies, lock non-entry gates until cleared
	if _room_enemies.size() > 0:
		_lock_gates_for_enemies()


func _spawn_box(pos: Vector3, is_rare: bool) -> void:
	var box := BoxScript.new()
	box.is_rare = is_rare
	box.drop_type = "meseta"
	box.drop_value = str(randi_range(10, 50)) if not is_rare else str(randi_range(50, 200))
	add_child(box)
	box.global_position = pos
	_fixup_element_materials(box)
	print("[CellObjects] Box at %s (rare=%s)" % [pos, is_rare])


func _spawn_enemy(pos: Vector3, enemy_id: String) -> void:
	var enemy := EnemySpawnScript.new()
	enemy.enemy_id = enemy_id
	add_child(enemy)
	enemy.global_position = pos
	_room_enemies.append(enemy)
	enemy.defeated.connect(func() -> void:
		_check_room_clear()
	)
	print("[CellObjects] Enemy '%s' at %s" % [enemy_id, pos])


func _spawn_fence(pos: Vector3, rotation_deg: float, link_id: String) -> void:
	var fence := FenceScript.new()
	add_child(fence)
	fence.global_position = pos
	fence.rotation.y = deg_to_rad(rotation_deg)
	_fixup_element_materials(fence)
	if not link_id.is_empty():
		if not _fence_links.has(link_id):
			_fence_links[link_id] = {"fences": [], "switches": []}
		_fence_links[link_id]["fences"].append(fence)
	print("[CellObjects] Fence at %s rot=%.0f° link='%s'" % [pos, rotation_deg, link_id])


func _spawn_switch(pos: Vector3, link_id: String) -> void:
	var sw := StepSwitchScript.new()
	add_child(sw)
	sw.global_position = pos
	_fixup_element_materials(sw)
	if not link_id.is_empty():
		if not _fence_links.has(link_id):
			_fence_links[link_id] = {"fences": [], "switches": []}
		_fence_links[link_id]["switches"].append(sw)
	print("[CellObjects] Switch at %s link='%s'" % [pos, link_id])


## Wire switch.activated → linked fences.disable()
func _wire_fence_links() -> void:
	for link_id in _fence_links:
		var link: Dictionary = _fence_links[link_id]
		var fences: Array = link["fences"]
		var switches: Array = link["switches"]
		for sw in switches:
			var step_sw: StepSwitch = sw as StepSwitch
			for fence in fences:
				var fence_ref: Fence = fence as Fence
				step_sw.activated.connect(func() -> void:
					fence_ref.disable()
				)
		if fences.size() > 0 and switches.size() > 0:
			print("[CellObjects] Wired link '%s': %d switches → %d fences" % [
				link_id, switches.size(), fences.size()])


## Lock non-entry/non-visited gates when room has enemies.
func _lock_gates_for_enemies() -> void:
	var connections: Dictionary = _current_cell.get("connections", {})
	for dir in connections:
		if dir == _spawn_edge:
			continue  # Don't lock entry gate
		if _visited_cells.has(str(connections[dir])):
			continue  # Don't lock gates to visited cells
		# Find the gate element for this direction
		var gate_name := "Gate"  # Gates are children of self
		for child in get_children():
			if child is Gate and child.global_position.distance_to(
				_portal_data.get(dir, {}).get("gate_pos", Vector3.INF)) < 2.0:
				var gate: Gate = child as Gate
				if gate.element_state != "open":
					gate.lock()
					_room_gates_locked.append(gate)
					print("[CellObjects] Gate %s locked (enemies present)" % dir)
					break


## Called when an enemy is defeated — check if all cleared.
func _check_room_clear() -> void:
	for enemy in _room_enemies:
		if is_instance_valid(enemy) and enemy.element_state != "dead":
			return  # Still alive enemies

	print("[CellObjects] Room cleared! Opening %d locked gates" % _room_gates_locked.size())
	for gate in _room_gates_locked:
		if is_instance_valid(gate):
			gate.open()
			# Enable the gate's trigger
			var trigger := _find_child_by_name(self, "GateTrigger_%s" % _gate_direction(gate)) as Area3D
			if trigger:
				trigger.monitoring = true
	_room_gates_locked.clear()


## Guess gate direction from position (for gate unlock)
func _gate_direction(gate: Node3D) -> String:
	for dir in _portal_data:
		if dir == "default":
			continue
		var gp: Vector3 = _portal_data[dir].get("gate_pos", Vector3.INF)
		if gate.global_position.distance_to(gp) < 2.0:
			return dir
	return ""


## Apply storybook-style material fixup to any placed element.
func _fixup_element_materials(element: GameElement) -> void:
	if not element.model:
		return
	element.apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			var dup := std_mat.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, dup)
	)


func _setup_debug_panel() -> void:
	# Collect GLB debug meshes by category
	_collect_debug_meshes(_map_root)
	# Build collision debug visualizations (hidden by default)
	_build_collision_debug_meshes(_map_root)

	# Debug HUD panel (top-right corner)
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	canvas.name = "DebugOverlay"
	add_child(canvas)

	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_debug_panel.add_theme_stylebox_override("panel", style)
	_debug_panel.anchor_left = 1.0
	_debug_panel.anchor_right = 1.0
	_debug_panel.anchor_top = 0.0
	_debug_panel.anchor_bottom = 0.0
	_debug_panel.offset_left = -220
	_debug_panel.offset_right = -8
	_debug_panel.offset_top = 8

	var label := Label.new()
	label.name = "DebugLabel"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	_debug_panel.add_child(label)
	canvas.add_child(_debug_panel)
	_update_debug_label()


func _collect_debug_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var n: String = node.name
		if n.begins_with("trigger_"):
			_debug_trigger_meshes.append(node)
			node.visible = _show_triggers
		elif n.begins_with("gate_"):
			_debug_gate_meshes.append(node)
			node.visible = _show_gate_markers
		elif n.begins_with("spawn_"):
			_debug_spawn_meshes.append(node)
			node.visible = _show_spawn_points
	for child in node.get_children():
		_collect_debug_meshes(child)


func _build_collision_debug_meshes(node: Node) -> void:
	if node is StaticBody3D:
		if not str(node.name).begins_with("trigger_") and not str(node.name).begins_with("gate_"):
			for child in node.get_children():
				if child is CollisionShape3D and child.shape:
					var debug_mesh := _collision_shape_to_debug_mesh(child)
					if debug_mesh:
						debug_mesh.visible = _show_floor_collision
						add_child(debug_mesh)
						_debug_collision_meshes.append(debug_mesh)
	for child in node.get_children():
		_build_collision_debug_meshes(child)


func _collision_shape_to_debug_mesh(col_shape: CollisionShape3D) -> MeshInstance3D:
	var shape := col_shape.shape
	var mesh_inst := MeshInstance3D.new()

	if shape is BoxShape3D:
		var box_mesh := BoxMesh.new()
		box_mesh.size = shape.size
		mesh_inst.mesh = box_mesh
	elif shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = shape.get_faces()
		if faces.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces
		var normals := PackedVector3Array()
		normals.resize(faces.size())
		for i in range(0, faces.size(), 3):
			if i + 2 < faces.size():
				var normal := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).normalized()
				normals[i] = normal
				normals[i + 1] = normal
				normals[i + 2] = normal
		arrays[Mesh.ARRAY_NORMAL] = normals
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh_inst.mesh = array_mesh
	else:
		return null

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.3, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.global_transform = col_shape.global_transform
	return mesh_inst


func _toggle_debug_panel() -> void:
	if _debug_panel:
		_debug_panel.visible = not _debug_panel.visible


func _toggle_triggers() -> void:
	_show_triggers = not _show_triggers
	for m in _debug_trigger_meshes:
		if is_instance_valid(m):
			m.visible = _show_triggers
	_update_debug_label()


func _toggle_gate_markers() -> void:
	_show_gate_markers = not _show_gate_markers
	for m in _debug_gate_meshes:
		if is_instance_valid(m):
			m.visible = _show_gate_markers
	_update_debug_label()


func _toggle_floor_collision() -> void:
	_show_floor_collision = not _show_floor_collision
	for m in _debug_collision_meshes:
		if is_instance_valid(m):
			m.visible = _show_floor_collision
	_update_debug_label()


func _toggle_spawn_points() -> void:
	_show_spawn_points = not _show_spawn_points
	for m in _debug_spawn_meshes:
		if is_instance_valid(m):
			m.visible = _show_spawn_points
	_update_debug_label()


func _update_debug_label() -> void:
	if not _debug_panel:
		return
	var label: Label = _debug_panel.get_node_or_null("DebugLabel")
	if not label:
		return
	var on := "[ON]"
	var off := "[OFF]"
	label.text = "Debug (F3)\n" \
		+ "F5  Triggers  %s\n" % (on if _show_triggers else off) \
		+ "F6  Gate cols  %s\n" % (on if _show_gate_markers else off) \
		+ "F7  Floor col  %s\n" % (on if _show_floor_collision else off) \
		+ "F8  Spawns     %s" % (on if _show_spawn_points else off)


func _transition_to_cell(target_pos: String, spawn_edge: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": target_pos,
		"spawn_edge": spawn_edge,
		"from_cell_pos": str(_current_cell.get("pos", "")),
		"keys_collected": _keys_collected,
		"visited_cells": _visited_cells,
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
			"visited_cells": {},
			"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
		})
	else:
		# All sections complete
		if SessionManager.get_session().get("type") == "quest":
			SessionManager.complete_quest()
		else:
			SessionManager.return_to_city()
		SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")


func _return_to_city() -> void:
	SessionManager.return_to_city()
	SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_city()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				if _map_overlay:
					_map_overlay.visible = not _map_overlay.visible
				get_viewport().set_input_as_handled()
			KEY_F3:
				_toggle_debug_panel()
				get_viewport().set_input_as_handled()
			KEY_F5:
				_toggle_triggers()
				get_viewport().set_input_as_handled()
			KEY_F6:
				_toggle_gate_markers()
				get_viewport().set_input_as_handled()
			KEY_F7:
				_toggle_floor_collision()
				get_viewport().set_input_as_handled()
			KEY_F8:
				_toggle_spawn_points()
				get_viewport().set_input_as_handled()
