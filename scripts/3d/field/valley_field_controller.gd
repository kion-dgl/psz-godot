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
const FieldHudScript := preload("res://scripts/3d/field/field_hud.gd")
const BoxScript := preload("res://scripts/3d/elements/box.gd")
const FenceScript := preload("res://scripts/3d/elements/fence.gd")
const StepSwitchScript := preload("res://scripts/3d/elements/step_switch.gd")
const EnemySpawnScript := preload("res://scripts/3d/elements/enemy_spawn.gd")
const DropMesetaScript := preload("res://scripts/3d/elements/drop_meseta.gd")
const DropItemScript := preload("res://scripts/3d/elements/drop_item.gd")
const MessagePackScript := preload("res://scripts/3d/elements/message_pack.gd")
const StoryPropScript := preload("res://scripts/3d/elements/story_prop.gd")
const DialogTriggerScript := preload("res://scripts/3d/elements/dialog_trigger.gd")
const FieldNpcScript := preload("res://scripts/3d/elements/field_npc.gd")
const TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")
const WarpPointScript := preload("res://scripts/3d/elements/warp_point.gd")
const QuestItemPickupScript := preload("res://scripts/3d/elements/quest_item_pickup.gd")
const CompanionNpcScript := preload("res://scripts/3d/elements/companion_npc.gd")
const FieldPauseMenuScript := preload("res://scripts/3d/field/field_pause_menu.gd")

const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const DIRECTIONS := ["north", "east", "south", "west"]

## Maps session area_id → DropRegistry area key for enemy drop lookups
const AREA_DROP_KEYS := {
	"gurhacia": "gurhacia-valley",
	"ozette": "ozette-wetland",
	"rioh": "rioh-snowfield",
	"makara": "makara-ruins",
	"paru": "oblivion-city-paru",
	"arca": "arca-plant",
	"dark": "dark-shrine",
	"tower": "eternal-tower",
}

var player: CharacterBody3D
var orbit_camera: Node3D
var _map_root: Node3D
var _world_env: WorldEnvironment
var _dir_light: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _transitioning := false
var _keys_collected: Dictionary = {}  # cell_pos → true (key pickup, prevents respawn)
var _gates_opened: Dictionary = {}   # cell_pos → true (gate opened by player, stays open on re-entry)
var _cell_states: Dictionary = {}    # cell_pos → { objects: [{state, ...}], drops: [{type, pos, ...}] }
var _current_cell: Dictionary = {}
var _portal_data: Dictionary = {}
var _map_overlay: CanvasLayer
var _room_minimap: Control
var _field_hud: CanvasLayer
var _blob_shadow: MeshInstance3D
var _stage_config: Dictionary = {}
var _spawn_edge: String = ""
var _rotation_deg: int = 0
var _visited_cells: Dictionary = {}  # cell_pos → true
var _key_hud_label: Label
var _key_hud_icon: Label
var _key_hud_panel: PanelContainer
var _total_keys_in_field: int = 0

# Room objects
var _room_enemies: Array = []  # EnemySpawn nodes in current room
var _room_boxes: Array = []    # Box nodes in current room
var _room_drops: Array = []    # Drop nodes spawned from boxes
var _room_messages: Array = [] # MessagePack nodes in current room
var _room_props: Array = []    # StoryProp nodes in current room
var _room_triggers: Array = [] # DialogTrigger nodes in current room
var _room_npcs: Array = []     # FieldNpc nodes in current room
var _room_quest_items: Array = [] # QuestItemPickup nodes in current room
var _fence_links: Dictionary = {}  # link_id → { "fences": [], "switches": [] }
var _room_gates_locked: Array = []  # Gate elements locked until enemies cleared
var _warp_edge_locked: Array = []  # AreaWarp + exit trigger locked until enemies cleared
var _needs_telepipe: bool = false      # End cell without warp_edge — spawn telepipe on room clear
var _companion: CharacterBody3D = null  # CompanionNpc following the player
var _deferred_telepipe: Dictionary = {} # Telepipe data deferred until room_clear
var _objective_locked_exits: Array = [] # Exit triggers locked until quest objectives complete
var _pause_menu: Node = null

# Wave spawning
var _current_wave: int = 1
var _max_wave: int = 1
var _wave_enemy_data: Dictionary = {}  # wave_num → [obj data]

# Debug toggle state
var _show_triggers := false
var _show_gate_markers := false
var _show_floor_collision := false
var _show_spawn_points := false
var _show_all_collision := false
var _debug_trigger_meshes: Array = []
var _debug_gate_meshes: Array = []
var _debug_collision_meshes: Array = []
var _debug_spawn_meshes: Array = []
var _debug_all_collision_meshes: Array = []
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
	_gates_opened = data.get("gates_opened", {})
	_visited_cells = data.get("visited_cells", {})
	_cell_states = data.get("cell_states", {})
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

	# Find current cell (deep copy so remap mutations don't affect session data)
	var found_cell: Dictionary = _find_cell(cells, current_cell_pos)
	_current_cell = found_cell.duplicate(true)
	if _current_cell.is_empty():
		push_error("[ValleyField] Cell not found: %s" % current_cell_pos)
		_return_to_city()
		return

	# Track visited cells
	_visited_cells[current_cell_pos] = true

	# Load GLB — resolve area folder from session
	var stage_id: String = str(_current_cell["stage_id"])
	TimeManager.stage_label = stage_id
	var area_id: String = SessionManager.get_current_area_id()
	var area_cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, GridGenerator.AREA_CONFIG["gurhacia"])

	# Load visual mesh from raw stage
	var subfolder: String = _get_stage_subfolder(stage_id, area_cfg["folder"])
	var scene_path := "res://assets/stages/%s/%s/lndmd/%s_m.glb" % [subfolder, stage_id, stage_id]
	var floor_path := "res://assets/stages/%s/%s/lndmd/%s-floor.glb" % [subfolder, stage_id, stage_id]

	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		push_error("[ValleyField] Failed to load map: %s" % scene_path)
		_return_to_city()
		return

	_map_root = packed_scene.instantiate() as Node3D
	_map_root.name = "Map"

	# Stage geometry is NOT rotated. Rotation only affects direction label mapping
	# (grid direction ↔ config direction) and minimap display. The 3D corridors
	# stay at their original GLB positions; triggers are placed at config positions.
	_rotation_deg = int(_current_cell.get("rotation", 0))

	# Load stage config from unified config
	_stage_config = _load_stage_config(area_cfg["folder"], stage_id)
	add_child(_map_root)
	_strip_embedded_lights(_map_root)
	_fix_materials(_map_root)
	await get_tree().process_frame

	# Load floor collision from separate floor GLB, fall back to embedded -colonly meshes
	if FileAccess.file_exists(floor_path):
		var floor_scene := load(floor_path) as PackedScene
		if floor_scene:
			var floor_root := floor_scene.instantiate() as Node3D
			floor_root.name = "FloorCollision"
			add_child(floor_root)
			# Check if Godot's -colonly suffix import created StaticBody3D nodes
			var has_static := _has_static_body(floor_root)
			if has_static:
				_setup_map_collision(floor_root)
				print("[ValleyField] Floor collision from GLB import suffix: %s" % floor_path)
			else:
				# Suffix import didn't create collision — build manually from meshes
				_create_collision_from_meshes(floor_root)
				print("[ValleyField] Floor collision built manually from mesh: %s" % floor_path)
		else:
			_setup_map_collision(_map_root)
	else:
		_setup_map_collision(_map_root)

	# DEBUG: Visualize floor collision mesh as semi-transparent green overlay
	_debug_show_floor_collision()

	await get_tree().process_frame

	# Read baked portal data from quest JSON (pre-computed by quest editor)
	var baked_portals: Dictionary = _current_cell.get("portals", {})
	if not baked_portals.is_empty():
		_portal_data = _parse_baked_portals(baked_portals)
	else:
		# Fallback: build from config (for non-quest or old quest JSON without baked portals)
		_portal_data = _build_portal_data_from_config(_stage_config)
		if _rotation_deg != 0:
			var remapped := {}
			for orig_dir in _portal_data:
				if orig_dir == "default":
					remapped["default"] = _portal_data["default"]
				else:
					remapped[_rotate_dir(orig_dir, _rotation_deg)] = _portal_data[orig_dir].duplicate()
			_portal_data = remapped

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

	# Log portal data
	print("[ValleyField]   ── Portal data ──")
	for key in _portal_data:
		var pd: Dictionary = _portal_data[key]
		print("[ValleyField]     '%s': spawn=%s  trigger=%s" % [
			key, pd["spawn_pos"], pd["trigger_pos"]])

	# Determine warp_edge early (needed for spawn resolution)
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))

	# Spawn player
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	var spawn_reason := ""
	var raw_spawn_pos: Array = data.get("spawn_position", [])
	if raw_spawn_pos.size() == 3:
		var sp := Vector3(raw_spawn_pos[0], raw_spawn_pos[1], raw_spawn_pos[2])
		if sp != Vector3.ZERO:
			spawn_pos = _map_root.to_global(sp)
			spawn_reason = "warp spawn_position %s" % sp
			# Infer spawn_edge from closest portal when not explicitly set
			if _spawn_edge.is_empty():
				var best_dist := INF
				for dir in _portal_data:
					if dir == "default":
						continue
					var pd: Dictionary = _portal_data[dir]
					var d: float = sp.distance_to(pd.get("spawn_pos", Vector3.INF))
					if d < best_dist:
						best_dist = d
						_spawn_edge = dir
				if not _spawn_edge.is_empty():
					spawn_edge = _spawn_edge
					print("[ValleyField] Inferred spawn_edge='%s' from spawn_position proximity (dist=%.2f)" % [_spawn_edge, best_dist])
	if not spawn_reason.is_empty():
		pass  # spawn_position already resolved above
	elif not spawn_edge.is_empty() and _portal_data.has(spawn_edge):
		spawn_pos = _portal_data[spawn_edge]["spawn_pos"]
		var gate_pos: Vector3 = _portal_data[spawn_edge].get("gate_pos", spawn_pos)
		spawn_rot = _facing_yaw(spawn_pos, gate_pos)
		spawn_reason = "entry from %s, facing gate (yaw=%.2f)" % [spawn_edge, spawn_rot]
	elif _portal_data.has("default"):
		spawn_pos = _portal_data["default"]["spawn_pos"]
		if _portal_data["default"].has("default_rotation"):
			spawn_rot = _portal_data["default"]["default_rotation"]
		spawn_reason = "default spawn"
	elif not warp_edge.is_empty() and _portal_data.has(OPPOSITE.get(warp_edge, "")):
		var entry_dir: String = OPPOSITE[warp_edge]
		spawn_pos = _portal_data[entry_dir]["spawn_pos"]
		var gp: Vector3 = _portal_data[entry_dir].get("gate_pos", spawn_pos)
		spawn_rot = _facing_yaw(spawn_pos, gp)
		spawn_reason = "opposite of warp_edge=%s, spawn at %s facing gate" % [warp_edge, entry_dir]
		if _spawn_edge.is_empty():
			_spawn_edge = entry_dir
			spawn_edge = entry_dir
	elif _portal_data.has("north"):
		spawn_pos = _portal_data["north"]["spawn_pos"]
		var gp: Vector3 = _portal_data["north"].get("gate_pos", spawn_pos)
		spawn_rot = _facing_yaw(spawn_pos, gp)
		spawn_reason = "fallback north portal, facing gate"
	elif _portal_data.has("south"):
		spawn_pos = _portal_data["south"]["spawn_pos"]
		var gp: Vector3 = _portal_data["south"].get("gate_pos", spawn_pos)
		spawn_rot = _facing_yaw(spawn_pos, gp)
		spawn_reason = "fallback south portal, facing gate"
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

	# (warp_edge exit is handled by area warp auto-generation in _spawn_field_elements)

	# Place key pickup if this cell has one
	if _current_cell.get("has_key", false):
		var key_for: String = str(_current_cell.get("key_for_cell", ""))
		if not key_for.is_empty() and not _keys_collected.has(key_for):
			_create_key_pickup(key_for)

	_spawn_field_elements()
	_spawn_companion()
	_spawn_cell_objects()
	_setup_debug_panel()

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

	# Field HUD (always visible — stats panel + meseta + minimap)
	_field_hud = FieldHudScript.new()
	add_child(_field_hud)

	# Pause menu (hidden by default)
	_pause_menu = FieldPauseMenuScript.new()
	_pause_menu.visible = false
	add_child(_pause_menu)

	_room_minimap = RoomMinimapScript.new()
	_room_minimap.setup(stage_id, area_cfg["folder"], _portal_data,
		_current_cell.get("connections", {}),
		str(_current_cell.get("warp_edge", "")), _map_root, _rotation_deg, _spawn_edge)
	_field_hud.add_child(_room_minimap)
	map_panel.top_offset = 200.0

	# Key HUD (drawn below minimap)
	_setup_key_hud(cells)

	# Sync initial gate lock states to minimap (gates were created before minimap)
	for gate in _room_gates_locked:
		if is_instance_valid(gate):
			var dir := _gate_direction(gate)
			if not dir.is_empty():
				_room_minimap.set_gate_locked(dir, true)
	# Key-gate starts locked unless previously opened
	var is_key_gate_cell: bool = _current_cell.get("is_key_gate", false)
	var kg_dir: String = str(_current_cell.get("key_gate_direction", ""))
	if is_key_gate_cell and not kg_dir.is_empty() and not _gates_opened.has(str(_current_cell.get("pos", ""))):
		_room_minimap.set_gate_locked(kg_dir, true)

	# Lock warp_edge on minimap if objectives are pending
	var warp_e: String = str(_current_cell.get("warp_edge", ""))
	if not warp_e.is_empty() and _has_pending_objectives():
		_room_minimap.set_gate_locked(warp_e, true)

	# Connect quest completion signal
	if not SessionManager.quest_completed.is_connected(_on_quest_completed):
		SessionManager.quest_completed.connect(_on_quest_completed)
	# Connect item collected signal for section-level warp_requires unlocking
	if not SessionManager.quest_item_collected.is_connected(_on_quest_item_collected_check_exit):
		SessionManager.quest_item_collected.connect(_on_quest_item_collected_check_exit)


func _on_quest_item_collected_check_exit(_item_id: String, _new_count: int, _target: int) -> void:
	# Check if section-level warp_requires are now satisfied
	if _objective_locked_exits.is_empty():
		return
	if _has_pending_section_requirements():
		return
	# Section requirements met — unlock exits
	print("[ValleyField] Section warp requirements met — unlocking exits")
	_unlock_objective_exits()


func _on_quest_completed() -> void:
	print("[ValleyField] Quest objectives complete — unlocking exits")
	_unlock_objective_exits()


func _unlock_objective_exits() -> void:
	# Unlock objective-locked AreaWarps (red beam → blue beam)
	for warp in _objective_locked_exits:
		if is_instance_valid(warp):
			warp.set_state("open")
	_objective_locked_exits.clear()

	# Update minimap
	var we: String = str(_current_cell.get("warp_edge", ""))
	if not we.is_empty() and _room_minimap:
		_room_minimap.set_gate_locked(we, false)


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


## Compute yaw angle for facing from position `from_pos` toward `to_pos` (XZ plane).
func _facing_yaw(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	if dx * dx + dz * dz < 0.001:
		return 0.0
	return atan2(dx, dz)


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
	add_child(_blob_shadow)
	_blob_shadow.global_position = Vector3(pos.x, 0.05, pos.z)



func _setup_map_collision(root: Node) -> void:
	_filter_floor_collision(root)
	_configure_collision_nodes(root)


func _filter_floor_collision(node: Node) -> void:
	## Strip downward/sideways-facing triangles from ConcavePolygonShape3D so the
	## player doesn't get trapped between top and bottom faces of the floor slab.
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D:
			var trimesh := cs.shape as ConcavePolygonShape3D
			var faces := trimesh.get_faces()
			var filtered := PackedVector3Array()
			var kept := 0
			var dropped := 0
			for i in range(0, faces.size(), 3):
				var a := faces[i]
				var b := faces[i + 1]
				var c := faces[i + 2]
				var normal := (b - a).cross(c - a).normalized()
				if normal.y < -0.3:  # Keep top-surface triangles (GLTF winding convention)
					filtered.append(a)
					filtered.append(b)
					filtered.append(c)
					kept += 1
				else:
					dropped += 1
			if dropped > 0:
				var new_shape := ConcavePolygonShape3D.new()
				new_shape.set_faces(filtered)
				cs.shape = new_shape
				print("[ValleyField] Floor collision filtered: kept %d, dropped %d triangles" % [kept, dropped])
	for child in node.get_children():
		_filter_floor_collision(child)


func _debug_show_floor_collision() -> void:
	## Visualize all floor collision shapes as a semi-transparent green mesh overlay.
	var faces := PackedVector3Array()
	_collect_collision_faces(self, faces)
	if faces.is_empty():
		print("[ValleyField] DEBUG: No collision faces found to visualize")
		return

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	# Compute normals (all pointing up for flat shading)
	var normals := PackedVector3Array()
	normals.resize(faces.size())
	for i in range(faces.size()):
		normals[i] = Vector3(0, 1, 0)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arr_mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "DebugFloorViz"
	mi.mesh = arr_mesh
	mi.position.y = 0.05  # Slight offset to avoid z-fighting
	add_child(mi)
	print("[ValleyField] DEBUG: Floor collision visualized — %d triangles" % (faces.size() / 3))


func _collect_collision_faces(node: Node, out: PackedVector3Array) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D:
			var trimesh := cs.shape as ConcavePolygonShape3D
			var local_faces := trimesh.get_faces()
			# Transform faces to global space
			var xform := cs.global_transform
			for i in range(local_faces.size()):
				out.append(xform * local_faces[i])
	for child in node.get_children():
		_collect_collision_faces(child, out)


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


## Derive the assets/stages/ subfolder from a stage_id and area folder name.
## e.g. stage_id="s01a_ga1", folder="valley" → "valley_a"
##      stage_id="s080_sa0", folder="tower"  → "tower_0"
static func _get_stage_subfolder(stage_id: String, folder: String) -> String:
	# The variant character is at index 3 in the stage_id (e.g. "s01a_ga1" → "a")
	if stage_id.length() >= 4:
		var variant: String = stage_id[3]
		return "%s_%s" % [folder, variant]
	return folder


## Static cache for unified stage config (loaded once, shared across cell transitions).
static var _unified_config_cache: Dictionary = {}
## Static cache for global texture fixes (keyed by texture filename, e.g. "s01_2_fall.png#1").
static var _global_texture_fixes: Dictionary = {}


func _load_stage_config(_folder: String, stage_id: String) -> Dictionary:
	# Load unified config on first access
	if _unified_config_cache.is_empty():
		var unified_path := "res://data/stage_configs/unified-stage-configs.json"
		if FileAccess.file_exists(unified_path):
			var file := FileAccess.open(unified_path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					_unified_config_cache = json.data as Dictionary
					print("[ValleyField] Loaded unified config: %d stages" % _unified_config_cache.size())
				file.close()

	# Load global texture fixes on first access
	if _global_texture_fixes.is_empty():
		var gtf_path := "res://data/stage_configs/global-texture-fixes.json"
		if FileAccess.file_exists(gtf_path):
			var gtf_file := FileAccess.open(gtf_path, FileAccess.READ)
			if gtf_file:
				var gtf_json := JSON.new()
				if gtf_json.parse(gtf_file.get_as_text()) == OK:
					_global_texture_fixes = gtf_json.data as Dictionary
					print("[ValleyField] Loaded global texture fixes: %d entries" % _global_texture_fixes.size())
				gtf_file.close()

	# Look up by stage_id
	if _unified_config_cache.has(stage_id):
		return _unified_config_cache[stage_id] as Dictionary

	return {}


## Direction base rotations for portal position math (matches quest-io.ts DIRECTION_ROTATIONS).
## north=0, south=PI, east=-PI/2, west=PI/2.
const DIRECTION_ROTATIONS := {
	"north": 0.0,
	"south": PI,
	"east": -PI / 2.0,
	"west": PI / 2.0,
}


## Parse portal data from quest JSON cell["portals"].
## Supports two formats:
##   v1 (reference): { "south": "portal_id_xxx" } — looks up position from stage config
##   legacy (baked): { "south": { "gate": [...], "spawn": [...], ... } } — uses inline positions
func _parse_baked_portals(baked: Dictionary) -> Dictionary:
	var result := {}
	# Build a lookup from portal_id → config portal for v1 references
	var config_portals_by_id := {}
	for cp in _stage_config.get("portals", []):
		config_portals_by_id[str(cp.get("id", ""))] = cp

	for dir_key in baked:
		var value = baked[dir_key]

		# v1 format: value is a portal_id string
		if value is String:
			var portal_id: String = value
			if dir_key == "default":
				# "default" references the defaultSpawn in stage config
				var ds: Dictionary = _stage_config.get("defaultSpawn", {})
				if not ds.is_empty():
					var ds_pos_arr: Array = ds.get("position", [0, 0, 0])
					var ds_pos := Vector3(float(ds_pos_arr[0]), 1.0, float(ds_pos_arr[2]))
					var ds_dir: String = str(ds.get("direction", "north"))
					var ds_rot: float = DIRECTION_ROTATIONS.get(ds_dir, 0.0)
					result["default"] = {
						"spawn_pos": ds_pos,
						"trigger_pos": ds_pos,
						"default_rotation": ds_rot,
					}
			elif config_portals_by_id.has(portal_id):
				result[dir_key] = _compute_portal_from_config(config_portals_by_id[portal_id], dir_key)
			else:
				push_warning("[ValleyField] Portal ID '%s' not found in stage config for dir '%s'" % [portal_id, dir_key])
			if result.has(dir_key):
				print("[ValleyField]   v1 portal: '%s' (id=%s) → gate=%s spawn=%s trigger=%s" % [
					dir_key, portal_id,
					result[dir_key].get("gate_pos", "n/a"),
					result[dir_key]["spawn_pos"],
					result[dir_key]["trigger_pos"]])
			continue

		# Legacy format: value is a dictionary with baked positions
		var pd: Dictionary = value
		if dir_key == "default":
			var sp: Array = pd.get("spawn", [0, 1, 0])
			result["default"] = {
				"spawn_pos": Vector3(float(sp[0]), float(sp[1]), float(sp[2])),
				"trigger_pos": Vector3(float(sp[0]), float(sp[1]), float(sp[2])),
			}
			if pd.has("default_rotation"):
				result["default"]["default_rotation"] = float(pd["default_rotation"])
		else:
			var gate: Array = pd.get("gate", [0, 0, 0])
			var spawn: Array = pd.get("spawn", [0, 1, 0])
			var trigger: Array = pd.get("trigger", [0, 0, 0])
			var gr: Array = pd.get("gate_rot", [0, 0, 0])
			result[dir_key] = {
				"gate_pos": Vector3(float(gate[0]), float(gate[1]), float(gate[2])),
				"spawn_pos": Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2])),
				"trigger_pos": Vector3(float(trigger[0]), float(trigger[1]), float(trigger[2])),
				"gate_rot": Vector3(float(gr[0]), float(gr[1]), float(gr[2])),
				"compass_label": pd.get("compass_label", dir_key.substr(0, 1).to_upper()),
			}
		print("[ValleyField]   baked portal: '%s' → gate=%s spawn=%s trigger=%s" % [
			dir_key,
			result[dir_key].get("gate_pos", "n/a"),
			result[dir_key]["spawn_pos"],
			result[dir_key]["trigger_pos"]])
	return result


## Compute portal positions from a config portal entry.
## Gate rotation and spawn/trigger offsets use the config direction (physical orientation).
## Only the compass label uses the game direction (rotated label).
func _compute_portal_from_config(portal: Dictionary, game_dir: String) -> Dictionary:
	var pos_arr: Array = portal.get("position", [0, 0, 0])
	var gate_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

	# Use the config direction for gate rotation and outward vector
	var config_dir: String = str(portal.get("direction", "north"))
	var base_rot: float = DIRECTION_ROTATIONS.get(config_dir, 0.0)
	var gate_rot := Vector3(0.0, base_rot, 0.0)
	var outward := Vector2(-sin(base_rot), -cos(base_rot))

	var spawn_pos := Vector3(gate_pos.x + outward.x * 3.0, 1.0, gate_pos.z + outward.y * 3.0)
	var trigger_pos := Vector3(gate_pos.x + outward.x * 7.0, 0.0, gate_pos.z + outward.y * 7.0)

	return {
		"gate_pos": gate_pos,
		"spawn_pos": spawn_pos,
		"trigger_pos": trigger_pos,
		"gate_rot": gate_rot,
		"compass_label": game_dir.substr(0, 1).to_upper(),
	}


## Build portal data from config JSON portals[] and defaultSpawn (fallback for non-quest sessions).
## Computes spawn/trigger/gate positions using the same math as ExportTab.tsx computePortalPositions.
## Positions are in stage-local space — caller transforms via _map_root.to_global() after add_child.
func _build_portal_data_from_config(config: Dictionary) -> Dictionary:
	var portals_arr: Array = config.get("portals", [])
	if portals_arr.is_empty() and not config.has("defaultSpawn"):
		return {}

	var result := {}
	for portal in portals_arr:
		var dir: String = str(portal.get("direction", ""))
		if dir.is_empty():
			continue
		var pos_arr: Array = portal.get("position", [0, 0, 0])
		# Positions match GLB geometry directly — no mirroring or rotation needed.
		var gate_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

		# Gate rotation for visual placement (Y-axis only)
		var base_rot: float = DIRECTION_ROTATIONS.get(dir, 0.0)
		var offset_deg: float = float(portal.get("rotationOffset", 0))
		var rotation: float = base_rot + deg_to_rad(offset_deg)
		var gate_rot := Vector3(0.0, rotation, 0.0)

		# Outward direction: cardinal axis based on portal direction label
		# Matches computePortalPositions() in quest-io.ts: offset = [-sin(rot), -cos(rot)]
		var outward := Vector2(-sin(rotation), -cos(rotation))

		# Spawn = 3 units outside gate (in corridor), y=1.0
		var spawn_pos := Vector3(gate_pos.x + outward.x * 3.0, 1.0, gate_pos.z + outward.y * 3.0)
		# Trigger = 7 units outside gate (deeper in corridor), y=0.0
		var trigger_pos := Vector3(gate_pos.x + outward.x * 7.0, 0.0, gate_pos.z + outward.y * 7.0)

		# Key by config direction — rotation remapping happens in the caller
		result[dir] = {
			"spawn_pos": spawn_pos,
			"trigger_pos": trigger_pos,
			"gate_pos": gate_pos,
			"gate_rot": gate_rot,
		}
		print("[ValleyField]   portal: config dir='%s' gate=%s spawn=%s trigger=%s" % [
			dir, gate_pos, spawn_pos, trigger_pos])

	# Default spawn point (boss rooms / gateless areas)
	if config.has("defaultSpawn"):
		var ds: Dictionary = config["defaultSpawn"]
		var ds_pos_arr: Array = ds.get("position", [0, 0, 0])
		var ds_pos := Vector3(float(ds_pos_arr[0]), 1.0, float(ds_pos_arr[2]))
		var ds_dir: String = str(ds.get("direction", "north"))
		var ds_rot: float = DIRECTION_ROTATIONS.get(ds_dir, 0.0)
		result["default"] = {
			"spawn_pos": ds_pos,
			"trigger_pos": ds_pos,
			"default_rotation": ds_rot,
		}

	print("[ValleyField] Built portal data from config: %d portals, default=%s" % [
		portals_arr.size(), str(config.has("defaultSpawn"))])
	return result


func _find_global_fix_for_material(mat: StandardMaterial3D) -> Dictionary:
	## Look up texture fix from global-texture-fixes.json by the material's albedo texture filename.
	## Keys in global fixes use "filename.png#1" format (the #1 suffix is from GLTF material index).
	if not mat.albedo_texture or _global_texture_fixes.is_empty():
		return {}
	var tex_path: String = mat.albedo_texture.resource_path
	var tex_basename: String = tex_path.get_file()  # e.g. "s01_2_fall.png"
	# Try with common suffixes (#0, #1) since GLTF keys include material index
	for suffix in ["#1", "#0", ""]:
		var key: String = tex_basename + suffix
		if _global_texture_fixes.has(key):
			return _global_texture_fixes[key] as Dictionary
	return {}


static func _wrap_mode_int(mode: String) -> int:
	match mode:
		"mirror": return 1
		"clamp": return 2
	return 0  # repeat


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
				var std_mat := mat as StandardMaterial3D
				# Look up global texture fix from material's albedo texture filename
				var fix := _find_global_fix_for_material(std_mat)
				var has_scroll := fix.has("scrollX") or fix.has("scrollY")
				var is_waterfall := has_scroll or (std_mat.albedo_texture and "_fall" in std_mat.albedo_texture.resource_path)
				var needs_shader := not fix.is_empty() and (
					is_waterfall or
					str(fix.get("wrapS", "repeat")) == "mirror" or
					str(fix.get("wrapT", "repeat")) == "mirror")
				if is_waterfall:
					# Waterfall / scrolling texture: additive blend + scrolling UV
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = WATERFALL_SHADER
					if std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					var scroll_x: float = fix.get("scrollX", 0.0)
					var scroll_y: float = fix.get("scrollY", -0.35)
					shader_mat.set_shader_parameter("uv_scroll", Vector2(scroll_x, scroll_y))
					shader_mat.render_priority = 1
					mesh_inst.set_surface_override_material(i, shader_mat)
				elif needs_shader:
					# Mirror wrap: custom shader with wrap modes
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = TEXTURE_FIX_SHADER
					if std_mat.albedo_texture:
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


func _has_static_body(node: Node) -> bool:
	if node is StaticBody3D:
		return true
	for child in node.get_children():
		if _has_static_body(child):
			return true
	return false


func _create_collision_from_meshes(root: Node) -> void:
	## Find MeshInstance3D nodes in the floor GLB and create StaticBody3D + trimesh collision.
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	print("[ValleyField] Found %d mesh instances in floor GLB for manual collision" % meshes.size())
	for mi in meshes:
		var mesh := mi.mesh
		if not mesh:
			continue
		var shape := mesh.create_trimesh_shape()
		if not shape:
			continue
		var static_body := StaticBody3D.new()
		static_body.name = "collision_floor"
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		var col_shape := CollisionShape3D.new()
		col_shape.shape = shape
		static_body.add_child(col_shape)
		# Preserve the mesh's global transform
		static_body.global_transform = mi.global_transform
		root.add_child(static_body)
		# Hide the visual mesh (collision only)
		mi.visible = false
		print("[ValleyField] Created trimesh collision from mesh '%s' (%d faces)" % [
			mi.name, mesh.get_faces().size() / 3])


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


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




func _create_gate_trigger(direction: String, target_cell_pos: String, _portal: Dictionary, delayed: bool = false, locked: bool = false) -> void:
	var entry_edge: String = OPPOSITE[direction]
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] ▶ TRIGGER: grid_dir=%s → cell %s (entry_edge=%s)" % [
				direction, target_cell_pos, entry_edge])
			_transition_to_cell(target_cell_pos, entry_edge)

	print("[ValleyField]   trigger: dir=%s  target=%s  delayed=%s  locked=%s  pos=%s" % [
		direction, target_cell_pos, delayed, locked, _portal["trigger_pos"]])
	# Locked triggers stay disabled until key gate opens; delayed triggers auto-enable after 1s
	_create_fallback_trigger("GateTrigger_%s" % direction, _portal["trigger_pos"], callback, delayed and not locked, locked)

	# DEBUG: Add floating direction label at gate position
	_add_gate_label(direction, _portal["gate_pos"] if _portal.has("gate_pos") else _portal["trigger_pos"], target_cell_pos)


func _create_exit_trigger(_direction: String, _portal: Dictionary) -> void:
	var objectives_pending := _has_pending_objectives()
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] Player entered exit trigger")
			_on_end_reached()
	_create_fallback_trigger("ExitTrigger", _portal["trigger_pos"], callback, false, objectives_pending)
	if objectives_pending:
		# Track for unlocking when objectives complete
		print("[FieldElements] Exit trigger locked (quest objectives incomplete)")


func _has_pending_objectives() -> bool:
	# Check section-level warp_requires first (locks exit until specific items collected)
	if _has_pending_section_requirements():
		return true
	# Fall back to global objectives check on the final section
	var objectives: Array = SessionManager.get_quest_objectives()
	if objectives.is_empty() or SessionManager.are_objectives_complete():
		return false
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()
	return section_idx >= sections.size() - 1


func _has_pending_section_requirements() -> bool:
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()
	if section_idx < 0 or section_idx >= sections.size():
		return false
	var section: Dictionary = sections[section_idx]
	var warp_requires: Array = section.get("warp_requires", [])
	if warp_requires.is_empty():
		return false
	for req in warp_requires:
		var item_id: String = str(req.get("item_id", ""))
		var target: int = int(req.get("target", 1))
		if SessionManager.get_quest_item_count(item_id) < target:
			return true
	return false



## Create a programmatic Area3D trigger at the given position.
func _create_fallback_trigger(trigger_name: String, pos: Vector3, callback: Callable, delayed: bool = false, locked: bool = false) -> void:
	var trigger := Area3D.new()
	trigger.name = trigger_name
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	if delayed or locked:
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

	if delayed and not locked:
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(trigger):
				trigger.monitoring = true
		)


## DEBUG: Add a floating 3D text label at gate position showing compass label + target cell.
## Also adds colored sphere markers for gate (yellow), spawn (green), and trigger (red).
func _add_gate_label(direction: String, pos: Vector3, target_cell: String) -> void:
	var label := Label3D.new()
	label.name = "GateLabel_%s" % direction
	# Show grid direction (matches minimap labels)
	var compass: String = direction.substr(0, 1).to_upper()
	label.text = "%s\n→ %s" % [compass, target_cell]
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 1, 0, 1)  # Bright yellow
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 8
	add_child(label)
	label.global_position = Vector3(pos.x, 3.5, pos.z)

	# DEBUG: Sphere markers — gate=yellow, spawn=green, trigger=red
	var clean_dir: String = direction.split(" ")[0]  # Strip "(EXIT)" suffix
	if _portal_data.has(clean_dir):
		var pd: Dictionary = _portal_data[clean_dir]
		_add_debug_sphere(pd["gate_pos"] if pd.has("gate_pos") else pos, Color(1, 1, 0), "GateMark_%s" % direction)
		_add_debug_sphere(pd["spawn_pos"], Color(0, 1, 0), "SpawnMark_%s" % direction)
		_add_debug_sphere(pd["trigger_pos"], Color(1, 0, 0), "TriggerMark_%s" % direction)


func _add_debug_sphere(pos: Vector3, color: Color, sphere_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = sphere_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	add_child(mi)
	mi.global_position = Vector3(pos.x, 1.5, pos.z)


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
		print("[ValleyField] Key using authored position: %s (rotation handled by _map_root)" % key_pos)
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

	_map_root.add_child(key)
	key.position = key_pos

	# Track collection for grid state and update HUD
	key.interacted.connect(func(_player: Node3D) -> void:
		_keys_collected[key_for_cell] = true
		_update_key_hud()
	)
	print("[ValleyField] Key pickup spawned for cell %s at %s (id=%s)" % [
		key_for_cell, key_pos, key_item_id])


func _drop_key_on_clear(target_cell: String, tracking_key: String) -> void:
	var key_item_id := "key_%s" % target_cell.replace(",", "_")
	var key := KeyPickupScript.new()
	key.key_id = key_item_id
	key.name = "KeyDrop_%s" % target_cell

	# Place key at authored position from quest editor, or fall back to room center
	var key_pos := Vector3.ZERO
	var authored_pos: Array = _current_cell.get("key_drop_position", [])
	if authored_pos.size() == 3:
		key_pos = Vector3(float(authored_pos[0]), float(authored_pos[1]), float(authored_pos[2]))
	else:
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

	_map_root.add_child(key)
	key.position = key_pos

	key.interacted.connect(func(_player: Node3D) -> void:
		_keys_collected[tracking_key] = true
		_update_key_hud()
	)
	print("[ValleyField] Key dropped on room clear for gate %s at %s (id=%s)" % [
		target_cell, key_pos, key_item_id])


func _setup_key_hud(cells: Array) -> void:
	# Count total keys in this field section (static pickups + room-clear drops)
	_total_keys_in_field = 0
	for cell in cells:
		if cell.get("has_key", false):
			_total_keys_in_field += 1
		if not str(cell.get("key_drop", "")).is_empty():
			_total_keys_in_field += 1
	_update_key_hud()


func _update_key_hud() -> void:
	if _room_minimap and _total_keys_in_field > 0:
		_room_minimap.update_keys(_keys_collected.size(), _total_keys_in_field)


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


## Check if a cell has living enemies (from quest data or saved state).
## For wave-based cells, any living enemy in any wave counts.
func _cell_has_enemies(cell: Dictionary) -> bool:
	var cell_pos: String = str(cell.get("pos", ""))
	var saved: Dictionary = _cell_states.get(cell_pos, {})
	if not saved.is_empty():
		# Check saved state — are any enemies still alive?
		for obj in saved.get("objects", []):
			if str(obj.get("type", "")) == "enemy" and str(obj.get("state", "")) == "alive":
				return true
		return false
	# Check raw quest data for enemy objects
	for obj in cell.get("objects", []):
		if str(obj.get("type", "")) == "enemy":
			return true
	return false


func _spawn_field_elements() -> void:
	var connections: Dictionary = _current_cell.get("connections", {})
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))
	var is_key_gate: bool = _current_cell.get("is_key_gate", false)
	var key_gate_dir: String = str(_current_cell.get("key_gate_direction", ""))

	# StartWarp on is_start cells at the entry portal (only first section)
	var section_idx_for_warp: int = SessionManager.get_current_section()
	if _current_cell.get("is_start", false) and section_idx_for_warp == 0:
		var start_warp := StartWarpScript.new()
		start_warp.auto_collect = false
		var start_pos := Vector3.ZERO
		var start_rot := 0.0
		if _portal_data.has("default"):
			start_pos = _portal_data["default"]["spawn_pos"]
			if _portal_data["default"].has("default_rotation"):
				start_rot = _portal_data["default"]["default_rotation"]
		else:
			var start_entry_dir: String = str(OPPOSITE.get(warp_edge, ""))
			if not start_entry_dir.is_empty() and _portal_data.has(start_entry_dir):
				start_pos = _portal_data[start_entry_dir]["spawn_pos"]
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

	# Area warps — placed at portals that have no connection (unconnected exits).
	# Behave exactly like gates (locked/open based on enemies, waypoints, triggers)
	# but use the AreaWarp model to indicate a section transition.
	var sections_for_warp: Array = SessionManager.get_field_sections()
	var current_section_data: Dictionary = sections_for_warp[section_idx_for_warp] if section_idx_for_warp < sections_for_warp.size() else {}
	var entry_dir: String = str(current_section_data.get("entry_direction", ""))
	var exit_dir: String = str(current_section_data.get("exit_direction", ""))
	var room_has_enemies: bool = _cell_has_enemies(_current_cell)

	for portal_dir in _portal_data:
		if portal_dir == "default":
			continue
		if connections.has(portal_dir):
			continue  # Has a connection — handled by gate logic above

		# Determine warp target based on direction
		var target_section := 0
		var target_cell := ""
		var target_position := Vector3.ZERO
		var is_exit: bool = (portal_dir == warp_edge or portal_dir == exit_dir)
		var is_entry: bool = (portal_dir == entry_dir)

		if is_exit and section_idx_for_warp + 1 < sections_for_warp.size():
			var next_sec: Dictionary = sections_for_warp[section_idx_for_warp + 1]
			target_section = section_idx_for_warp + 1
			target_cell = str(next_sec.get("start_pos", ""))
		elif is_entry and section_idx_for_warp > 0:
			var prev_sec: Dictionary = sections_for_warp[section_idx_for_warp - 1]
			target_section = section_idx_for_warp - 1
			target_cell = str(prev_sec.get("end_pos", ""))
		else:
			continue  # No valid target — skip

		var pd: Dictionary = _portal_data[portal_dir]
		var aw_gate_pos: Vector3 = pd.get("gate_pos", pd["trigger_pos"])
		var aw_gate_rot: Vector3 = pd.get("gate_rot", Vector3.ZERO)
		var aw_trigger_pos: Vector3 = pd["trigger_pos"]
		var aw_spawn_pos: Vector3 = pd["spawn_pos"]

		# Open/locked state — same logic as regular gates
		var is_spawn_edge: bool = (portal_dir == _spawn_edge)
		var is_open: bool = is_spawn_edge or not room_has_enemies
		var is_delayed: bool = is_spawn_edge  # Delay trigger on entry edge

		# Gate model — AreaWarp instead of Gate
		var area_warp := AreaWarpScript.new()
		area_warp.auto_collect = false
		area_warp.name = "AreaWarp_%s" % portal_dir
		area_warp.element_state = "open" if is_open else "locked"
		add_child(area_warp)
		area_warp.global_position = aw_gate_pos
		area_warp.rotation = aw_gate_rot

		# Gate trigger — same as _create_gate_trigger but transitions to another section
		var t_section := target_section
		var t_cell := target_cell
		var t_pos := target_position
		var aw_callback := func(_body: Node3D) -> void:
			if _body.is_in_group("player"):
				print("[ValleyField] AreaWarp %s activated → section %d, cell %s" % [portal_dir, t_section, t_cell])
				SessionManager.set_current_section(t_section)
				SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
					"current_cell_pos": t_cell,
					"spawn_edge": "",
					"spawn_position": [t_pos.x, t_pos.y, t_pos.z],
					"keys_collected": {},
					"gates_opened": {},
					"visited_cells": {},
					"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
				})
		_create_fallback_trigger("GateTrigger_%s" % portal_dir, aw_trigger_pos, aw_callback, is_delayed, not is_open)

		# Waypoint — same as regular gates
		var wp_pos := Vector3(aw_trigger_pos.x, 1.5, aw_trigger_pos.z)
		var waypoint := WaypointScript.new()
		add_child(waypoint)
		waypoint.global_position = wp_pos
		waypoint._base_y = waypoint.position.y
		waypoint.rotation.y = _facing_yaw(wp_pos, aw_spawn_pos)
		waypoint.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		)
		if is_spawn_edge:
			waypoint.mark_unvisited()
		else:
			waypoint.mark_new()

		# Debug spheres (gate=yellow, spawn=green, trigger=red)
		_add_debug_sphere(aw_gate_pos, Color(1, 1, 0), "GateMark_%s" % portal_dir)
		_add_debug_sphere(aw_spawn_pos, Color(0, 1, 0), "SpawnMark_%s" % portal_dir)
		_add_debug_sphere(aw_trigger_pos, Color(1, 0, 0), "TriggerMark_%s" % portal_dir)

		print("[FieldElements] AreaWarp '%s' → gate=%s trigger=%s open=%s target=s%d/%s" % [
			portal_dir, aw_gate_pos, aw_trigger_pos, is_open, target_section, target_cell])

	# End cells WITHOUT warp_edge — defer telepipe until room clear
	# Skip if any object already provides a telepipe (explicit telepipe object or dialog action)
	if _current_cell.get("is_end", false) and warp_edge.is_empty():
		var has_telepipe_source := false
		for obj in _current_cell.get("objects", []):
			var obj_type: String = str(obj.get("type", ""))
			if obj_type == "telepipe":
				has_telepipe_source = true
				break
			if obj_type in ["dialog_trigger", "quest_item"]:
				for act in obj.get("actions", []):
					if str(act) == "telepipe":
						has_telepipe_source = true
						break
			if has_telepipe_source:
				break
		if not has_telepipe_source:
			_needs_telepipe = true

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
			kg.required_keys = int(_current_cell.get("required_keys", 1))
			kg.name = "KeyGate_%s" % dir
			add_child(kg)
			kg.global_position = gate_pos
			kg.rotation = gate_rot
			# Standard box collision for key gates (6.0 x 1.5 x 0.2)
			var collision := StaticBody3D.new()
			collision.name = "KeyGateCollision_%s" % dir
			collision.collision_layer = 1
			collision.collision_mask = 0
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(6.0, 1.5, 0.2)
			var shape_node := CollisionShape3D.new()
			shape_node.shape = box_shape
			shape_node.position.y = 0.75
			collision.add_child(shape_node)
			add_child(collision)
			collision.global_position = gate_pos
			collision.rotation = gate_rot
			kg.collision_body = collision
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
			var gate_dir_for_minimap: String = str(dir)
			kg.state_changed.connect(func(_old: String, new_state: String) -> void:
				if new_state == "open":
					_gates_opened[cell_pos_for_gate] = true
					var trigger := _find_child_by_name(self, gate_trigger_name) as Area3D
					if trigger:
						trigger.monitoring = true
						print("[ValleyField] KeyGate opened → trigger '%s' enabled, gate tracked" % gate_trigger_name)
					if _room_minimap:
						_room_minimap.set_gate_locked(gate_dir_for_minimap, false)
			)
			print("[FieldElements] ── KEY GATE DONE ──")
		else:
			# Regular gate — open if entry, visited, or room has no enemies
			var target_visited: bool = _visited_cells.has(str(connections[dir]))
			var gate_is_open: bool = (dir == _spawn_edge) or target_visited or not room_has_enemies
			var gate := GateScript.new()
			add_child(gate)
			gate.global_position = gate_pos
			gate.rotation = _portal_data[dir].get("gate_rot", Vector3.ZERO)
			_fixup_gate_materials(gate)
			gate._setup_laser_material()
			if gate_is_open:
				gate.open()
			_fix_gate_depth(gate)

		# Waypoint — navigation marker inside the load trigger area
		var gate_wp_pos := Vector3(trigger_pos.x, 1.5, trigger_pos.z)
		var gate_waypoint := WaypointScript.new()
		add_child(gate_waypoint)
		gate_waypoint.global_position = gate_wp_pos
		gate_waypoint._base_y = gate_waypoint.position.y  # Re-capture after repositioning
		# Face toward spawn point so front faces the player approaching from the room
		var spawn_pt: Vector3 = _portal_data[dir].get("spawn_pos", trigger_pos)
		gate_waypoint.rotation.y = _facing_yaw(gate_wp_pos, spawn_pt)
		# Disable backface culling so it's visible from any angle
		gate_waypoint.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		)
		# Determine waypoint state from visited history
		var target_cell_pos: String = str(connections[dir])
		var wp_state: String
		if dir == _spawn_edge:
			gate_waypoint.mark_unvisited()
			wp_state = "came_from"
		elif _visited_cells.has(target_cell_pos):
			gate_waypoint.mark_visited()
			wp_state = "visited_prior"
		else:
			gate_waypoint.mark_new()
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
			exit_rot = _portal_data[dir].get("gate_rot", Vector3.ZERO).y
			break

	# Fallback to default spawn
	if exit_dir.is_empty() and _portal_data.has("default"):
		exit_pos = _portal_data["default"]["spawn_pos"]
		if _portal_data["default"].has("default_rotation"):
			exit_rot = _portal_data["default"]["default_rotation"]

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


## Spawn a telepipe (cyan cylinder placeholder). Player steps into it to complete the section / quest.
## If pos is zero, falls back to room center / default spawn.
func _spawn_telepipe(pos: Vector3 = Vector3.ZERO) -> void:
	print("[FieldElements] Spawning telepipe at %s" % pos)
	var tp_pos := pos
	if tp_pos == Vector3.ZERO and _portal_data.has("default"):
		tp_pos = _portal_data["default"]["spawn_pos"]

	var telepipe := TelepipeScript.new()
	telepipe.name = "Telepipe"
	_map_root.add_child(telepipe)
	telepipe.position = tp_pos
	telepipe.activated.connect(func() -> void:
		print("[ValleyField] Player activated telepipe")
		_on_end_reached()
	)


func _spawn_quest_item(pos: Vector3, item_id: String, item_label: String, dlg: Array = [], actions: Array = []) -> void:
	var qi := QuestItemPickupScript.new()
	qi.quest_item_id = item_id
	qi.quest_item_label = item_label
	qi.pickup_dialog = dlg
	qi.pickup_actions = actions
	if _companion and is_instance_valid(_companion):
		qi.companion_node = _companion
	_map_root.add_child(qi)
	qi.position = pos
	_room_quest_items.append(qi)


## Spawn placed objects (boxes, enemies, fences, switches, messages) from quest cell data.
## If the cell was previously visited, restore saved state instead.
func _spawn_cell_objects() -> void:
	var cell_pos: String = str(_current_cell.get("pos", ""))
	var saved: Dictionary = _cell_states.get(cell_pos, {})
	var objects: Array = _current_cell.get("objects", [])

	# Reset room tracking arrays
	_room_messages.clear()
	_room_props.clear()
	_room_triggers.clear()
	_room_npcs.clear()
	_room_quest_items.clear()
	_deferred_telepipe = {}

	if objects.is_empty() and saved.is_empty():
		return

	if not saved.is_empty():
		_restore_cell_objects(saved)
	else:
		_spawn_fresh_cell_objects(objects)

	# Wire fence↔switch links
	_wire_fence_links()

	# Count living enemies for gate locking
	var alive_enemies: int = 0
	for e in _room_enemies:
		if is_instance_valid(e) and e.element_state != "dead":
			alive_enemies += 1

	if alive_enemies > 0:
		_lock_gates_for_enemies()
	elif _needs_telepipe:
		# No enemies on end cell — spawn telepipe immediately
		_needs_telepipe = false
		_spawn_telepipe(Vector3.ZERO)


## Spawn objects fresh (first visit to a cell).
func _spawn_fresh_cell_objects(objects: Array) -> void:
	print("[CellObjects] Spawning %d objects (fresh)" % objects.size())
	_wave_enemy_data.clear()
	_current_wave = 1
	_max_wave = 1

	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		var pos_arr: Array = obj.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var obj_rot: float = float(obj.get("rotation", 0))

		match obj_type:
			"box", "rare_box":
				_spawn_box(pos, obj_type == "rare_box")
			"enemy":
				var wave: int = int(obj.get("wave", 1))
				if wave < 1:
					wave = 1
				if wave > _max_wave:
					_max_wave = wave
				if wave == 1:
					var enemy_id: String = str(obj.get("enemy_id", "lizard"))
					_spawn_enemy(pos, enemy_id)
				else:
					if not _wave_enemy_data.has(wave):
						_wave_enemy_data[wave] = []
					_wave_enemy_data[wave].append(obj)
			"fence":
				var link_id: String = str(obj.get("link_id", ""))
				var f_scale_x: float = float(obj.get("scale_x", 1.0))
				_spawn_fence(pos, obj_rot, link_id, f_scale_x)
			"step_switch":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_switch(pos, link_id)
			"message":
				var text: String = str(obj.get("text", ""))
				var msg_locked: bool = obj.get("locked", false)
				var reaction: Array = obj.get("reaction_dialog", [])
				var init_state: String = "locked" if msg_locked else "available"
				_spawn_message(pos, text, init_state, reaction)
			"story_prop":
				var prop_path: String = str(obj.get("prop_path", ""))
				var prop_scale: float = float(obj.get("prop_scale", 1.0))
				_spawn_story_prop(pos, prop_path, obj_rot, prop_scale)
			"dialog_trigger":
				var trigger_id: String = str(obj.get("trigger_id", ""))
				var dlg: Array = obj.get("dialog", [])
				var condition: String = str(obj.get("trigger_condition", "enter"))
				var act: Array = obj.get("actions", [])
				var tsize_arr: Array = obj.get("trigger_size", [])
				var tsize := Vector3.ZERO
				if tsize_arr.size() == 3:
					tsize = Vector3(float(tsize_arr[0]), float(tsize_arr[1]), float(tsize_arr[2]))
				_spawn_dialog_trigger(pos, trigger_id, dlg, "ready", condition, act, tsize)
			"npc":
				var npc_id: String = str(obj.get("npc_id", ""))
				var npc_name: String = str(obj.get("npc_name", ""))
				var dlg: Array = obj.get("dialog", [])
				_spawn_field_npc(pos, npc_id, npc_name, dlg, obj_rot)
			"telepipe":
				var spawn_cond: String = str(obj.get("spawn_condition", "immediate"))
				if spawn_cond == "room_clear":
					# Defer — store data for _check_room_clear
					_deferred_telepipe = { "position": pos }
				else:
					_spawn_telepipe(pos)
			"warp":
				var w_section: int = int(obj.get("warp_section", 0))
				var w_cell: String = str(obj.get("warp_cell", ""))
				var w_pos_arr: Array = obj.get("warp_position", [0, 0, 0])
				var w_pos := Vector3(w_pos_arr[0], w_pos_arr[1], w_pos_arr[2])
				_spawn_warp_point(pos, w_section, w_cell, w_pos)
			"area_warp":
				pass  # Area warps are auto-generated from portal data, not from objects
			"quest_item":
				var qi_id: String = str(obj.get("item_id", ""))
				var qi_label: String = str(obj.get("item_label", ""))
				var qi_dlg: Array = obj.get("dialog", [])
				var qi_act: Array = obj.get("actions", [])
				_spawn_quest_item(pos, qi_id, qi_label, qi_dlg, qi_act)

	if _max_wave > 1:
		print("[CellObjects] Wave system: %d waves, wave 1 spawned" % _max_wave)


## Restore objects from saved cell state (revisiting a cell).
func _restore_cell_objects(saved: Dictionary) -> void:
	var obj_states: Array = saved.get("objects", [])
	var drop_states: Array = saved.get("drops", [])
	_current_wave = int(saved.get("current_wave", 1))
	_max_wave = int(saved.get("max_wave", 1))
	print("[CellObjects] Restoring %d objects + %d drops from saved state (wave %d/%d)" % [
		obj_states.size(), drop_states.size(), _current_wave, _max_wave])

	for obj in obj_states:
		var obj_type: String = str(obj.get("type", ""))
		var pos := Vector3(float(obj.get("px", 0)), float(obj.get("py", 0)), float(obj.get("pz", 0)))
		var state: String = str(obj.get("state", ""))
		var obj_rot: float = float(obj.get("rotation", 0))

		match obj_type:
			"box", "rare_box":
				_spawn_box(pos, obj_type == "rare_box", state,
					str(obj.get("drop_type", "")), str(obj.get("drop_value", "")))
			"enemy":
				_spawn_enemy(pos, str(obj.get("enemy_id", "lizard")), state)
			"fence":
				var link_id: String = str(obj.get("link_id", ""))
				var r_scale_x: float = float(obj.get("scale_x", 1.0))
				_spawn_fence(pos, obj_rot, link_id, r_scale_x)
				# Restore fence state if disabled
				if state == "disabled" and not _fence_links.is_empty():
					for lid in _fence_links:
						for f in _fence_links[lid]["fences"]:
							if (f as Fence).position.distance_to(pos) < 0.1:
								(f as Fence).disable()
			"step_switch":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_switch(pos, link_id)
				# Restore switch state
				if state == "on":
					for lid in _fence_links:
						for s in _fence_links[lid]["switches"]:
							if (s as StepSwitch).position.distance_to(pos) < 0.1:
								(s as StepSwitch).set_state("on")
			"message":
				var text: String = str(obj.get("text", ""))
				var msg_state: String = state if not state.is_empty() else "available"
				var reaction: Array = obj.get("reaction_dialog", [])
				_spawn_message(pos, text, msg_state, reaction)
			"story_prop":
				var prop_path: String = str(obj.get("prop_path", ""))
				var prop_scale: float = float(obj.get("prop_scale", 1.0))
				_spawn_story_prop(pos, prop_path, obj_rot, prop_scale)
			"dialog_trigger":
				var trigger_id: String = str(obj.get("trigger_id", ""))
				var dlg: Array = obj.get("dialog", [])
				var condition: String = str(obj.get("trigger_condition", "enter"))
				var act: Array = obj.get("actions", [])
				var tsize_arr: Array = obj.get("trigger_size", [])
				var tsize := Vector3.ZERO
				if tsize_arr.size() == 3:
					tsize = Vector3(float(tsize_arr[0]), float(tsize_arr[1]), float(tsize_arr[2]))
				_spawn_dialog_trigger(pos, trigger_id, dlg, state, condition, act, tsize)
			"npc":
				var npc_id: String = str(obj.get("npc_id", ""))
				var npc_name: String = str(obj.get("npc_name", ""))
				var dlg: Array = obj.get("dialog", [])
				_spawn_field_npc(pos, npc_id, npc_name, dlg, obj_rot)
			"telepipe":
				# Telepipes are always spawned on restore (player already cleared the room)
				_spawn_telepipe(pos)
			"warp":
				var w_section: int = int(obj.get("warp_section", 0))
				var w_cell: String = str(obj.get("warp_cell", ""))
				var w_pos_arr: Array = obj.get("warp_position", [0, 0, 0])
				var w_pos := Vector3(w_pos_arr[0], w_pos_arr[1], w_pos_arr[2])
				_spawn_warp_point(pos, w_section, w_cell, w_pos)
			"area_warp":
				pass  # Area warps are auto-generated from portal data, not from objects
			"quest_item":
				if state != "collected":
					var qi_id: String = str(obj.get("item_id", ""))
					var qi_label: String = str(obj.get("item_label", ""))
					var qi_dlg: Array = obj.get("dialog", [])
					_spawn_quest_item(pos, qi_id, qi_label, qi_dlg)

	# Restore uncollected drops
	for d in drop_states:
		var pos := Vector3(float(d.get("px", 0)), float(d.get("py", 0)), float(d.get("pz", 0)))
		var drop_kind: String = str(d.get("kind", ""))
		var drop: DropBase = null
		match drop_kind:
			"meseta":
				var dm := DropMesetaScript.new()
				dm.amount = int(d.get("amount", 10))
				drop = dm
			"item":
				var di := DropItemScript.new()
				di.item_id = str(d.get("item_id", ""))
				di.amount = int(d.get("amount", 1))
				drop = di
		if drop:
			_map_root.add_child(drop)
			drop.position = pos
			_room_drops.append(drop)


## Save current cell's object states before transitioning away.
func _save_cell_state() -> void:
	var cell_pos: String = str(_current_cell.get("pos", ""))
	if cell_pos.is_empty():
		return

	var obj_states: Array = []
	var drop_states: Array = []

	# Save box states
	for box in _room_boxes:
		if not is_instance_valid(box):
			# Box was destroyed — save as destroyed
			continue
		var b: Box = box as Box
		obj_states.append({
			"type": "rare_box" if b.is_rare else "box",
			"px": b.position.x, "py": b.position.y, "pz": b.position.z,
			"state": b.element_state,
			"drop_type": b.drop_type,
			"drop_value": b.drop_value,
		})
	# Also record destroyed boxes from the original quest data
	var objects: Array = _current_cell.get("objects", [])
	var intact_box_positions: Array = []
	for box in _room_boxes:
		if is_instance_valid(box):
			intact_box_positions.append(box.position)
	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		if obj_type in ["box", "rare_box"]:
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var found := false
			for intact_pos in intact_box_positions:
				if intact_pos.distance_to(pos) < 0.1:
					found = true
					break
			if not found:
				obj_states.append({
					"type": obj_type,
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "destroyed",
				})

	# Save enemy states (current wave enemies that have been spawned)
	for obj in objects:
		if str(obj.get("type", "")) == "enemy":
			var wave: int = int(obj.get("wave", 1))
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var enemy_id: String = str(obj.get("enemy_id", "lizard"))
			if wave > _current_wave:
				# Future wave — not yet spawned, save as alive
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "alive",
					"enemy_id": enemy_id,
					"wave": wave,
				})
			elif wave < _current_wave:
				# Past wave — already cleared
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "dead",
					"enemy_id": enemy_id,
					"wave": wave,
				})
			else:
				# Current wave — check spawned enemies
				var is_dead := true
				for e in _room_enemies:
					if is_instance_valid(e) and e.position.distance_to(pos) < 0.1:
						is_dead = (e.element_state == "dead")
						break
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "dead" if is_dead else "alive",
					"enemy_id": enemy_id,
					"wave": wave,
				})

	# Save fence/switch states
	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		if obj_type in ["fence", "step_switch"]:
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var state: String = ""
			if obj_type == "fence":
				for lid in _fence_links:
					for f in _fence_links[lid]["fences"]:
						if is_instance_valid(f) and (f as Node3D).position.distance_to(pos) < 0.5:
							state = (f as Fence).element_state
			elif obj_type == "step_switch":
				for lid in _fence_links:
					for s in _fence_links[lid]["switches"]:
						if is_instance_valid(s) and (s as Node3D).position.distance_to(pos) < 0.5:
							state = (s as StepSwitch).element_state
			obj_states.append({
				"type": obj_type,
				"px": pos.x, "py": pos.y, "pz": pos.z,
				"state": state,
				"rotation": float(obj.get("rotation", 0)),
				"link_id": str(obj.get("link_id", "")),
			})

	# Save uncollected drops
	for drop in _room_drops:
		if is_instance_valid(drop) and drop.element_state == "available":
			var d: DropBase = drop as DropBase
			var kind := "meseta" if d is DropMeseta else "item"
			var entry := {
				"kind": kind,
				"px": d.position.x, "py": d.position.y, "pz": d.position.z,
				"amount": d.amount,
			}
			if kind == "item":
				entry["item_id"] = d.item_id
			drop_states.append(entry)

	# Save message states
	for msg in _room_messages:
		if is_instance_valid(msg):
			var msg_entry := {
				"type": "message",
				"px": msg.position.x, "py": msg.position.y, "pz": msg.position.z,
				"state": msg.element_state,
				"text": msg.message_text,
			}
			if not msg.reaction_dialog.is_empty():
				msg_entry["reaction_dialog"] = msg.reaction_dialog
			obj_states.append(msg_entry)

	# Save story prop states
	for prop in _room_props:
		if is_instance_valid(prop):
			obj_states.append({
				"type": "story_prop",
				"px": prop.position.x, "py": prop.position.y, "pz": prop.position.z,
				"state": prop.element_state,
				"prop_path": prop.prop_path,
				"prop_scale": prop.prop_scale,
			})

	# Save dialog trigger states
	for trigger in _room_triggers:
		if is_instance_valid(trigger):
			var tdata := {
				"type": "dialog_trigger",
				"px": trigger.position.x, "py": trigger.position.y, "pz": trigger.position.z,
				"state": trigger.element_state,
				"trigger_id": trigger.trigger_id,
				"dialog": trigger.dialog,
				"trigger_condition": trigger.trigger_condition,
				"actions": trigger.actions,
			}
			var cs: Vector3 = trigger.collision_size
			if cs != Vector3(4.0, 3.0, 4.0):
				tdata["trigger_size"] = [cs.x, cs.y, cs.z]
			obj_states.append(tdata)

	# Save NPC states
	for npc in _room_npcs:
		if is_instance_valid(npc):
			obj_states.append({
				"type": "npc",
				"px": npc.position.x, "py": npc.position.y, "pz": npc.position.z,
				"state": npc.element_state,
				"npc_id": npc.npc_id,
				"npc_name": npc.npc_name,
				"dialog": npc.dialog,
			})

	# Save quest item states
	for qi in _room_quest_items:
		if is_instance_valid(qi):
			obj_states.append({
				"type": "quest_item",
				"px": qi.position.x, "py": qi.position.y, "pz": qi.position.z,
				"state": qi.element_state,
				"item_id": qi.quest_item_id,
				"item_label": qi.quest_item_label,
			})

	# Save telepipe from original quest data (telepipes are procedural, just preserve placement)
	for obj in objects:
		if str(obj.get("type", "")) == "telepipe":
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			obj_states.append({
				"type": "telepipe",
				"px": float(pos_arr[0]), "py": float(pos_arr[1]), "pz": float(pos_arr[2]),
				"state": "spawned",
				"spawn_condition": str(obj.get("spawn_condition", "immediate")),
			})

	_cell_states[cell_pos] = {
		"objects": obj_states, "drops": drop_states,
		"current_wave": _current_wave, "max_wave": _max_wave,
	}
	print("[CellObjects] Saved state for cell %s: %d objects, %d drops (wave %d/%d)" % [
		cell_pos, obj_states.size(), drop_states.size(), _current_wave, _max_wave])


func _spawn_box(pos: Vector3, is_rare: bool, state: String = "intact", drop_type: String = "", drop_value: String = "") -> void:
	if state == "destroyed":
		return  # Don't spawn destroyed boxes
	var box := BoxScript.new()
	box.is_rare = is_rare
	box.drop_type = drop_type if not drop_type.is_empty() else "meseta"
	box.drop_value = drop_value if not drop_value.is_empty() else (str(randi_range(10, 50)) if not is_rare else str(randi_range(50, 200)))
	_map_root.add_child(box)
	box.position = pos
	_fixup_element_materials(box)
	_room_boxes.append(box)
	# Track drops spawned from this box
	box.destroyed_box.connect(func() -> void:
		# Find new drop children added after destruction
		await get_tree().process_frame
		for child in _map_root.get_children():
			if child is DropBase and not _room_drops.has(child):
				_room_drops.append(child)
	)
	print("[CellObjects] Box at %s (rare=%s)" % [pos, is_rare])


func _spawn_enemy(pos: Vector3, enemy_id: String, state: String = "alive") -> void:
	if state == "dead":
		return  # Don't spawn dead enemies
	var enemy := EnemySpawnScript.new()
	enemy.enemy_id = enemy_id
	_map_root.add_child(enemy)
	enemy.position = pos
	_room_enemies.append(enemy)
	var spawn_pos := pos
	var spawn_id := enemy_id
	enemy.defeated.connect(func() -> void:
		_spawn_enemy_drops(spawn_pos, spawn_id)
		_check_room_clear()
	)
	print("[CellObjects] Enemy '%s' at %s" % [enemy_id, pos])


func _spawn_fence(pos: Vector3, rotation_deg: float, link_id: String, scale_x: float = 1.0) -> void:
	var fence := FenceScript.new()
	_map_root.add_child(fence)
	fence.position = pos
	fence.rotation.y = deg_to_rad(rotation_deg)
	if scale_x != 1.0:
		fence.scale.x = scale_x
		fence.collision_size.x = fence.collision_size.x * scale_x
	_fixup_element_materials(fence)
	# Re-run laser material setup after fixup replaced materials (storybook pattern)
	fence._setup_laser_materials()
	if not link_id.is_empty():
		if not _fence_links.has(link_id):
			_fence_links[link_id] = {"fences": [], "switches": []}
		_fence_links[link_id]["fences"].append(fence)
	print("[CellObjects] Fence at %s rot=%.0f° link='%s'" % [pos, rotation_deg, link_id])


func _spawn_switch(pos: Vector3, link_id: String) -> void:
	var sw := StepSwitchScript.new()
	_map_root.add_child(sw)
	sw.position = pos
	_fixup_element_materials(sw)
	if not link_id.is_empty():
		if not _fence_links.has(link_id):
			_fence_links[link_id] = {"fences": [], "switches": []}
		_fence_links[link_id]["switches"].append(sw)
	print("[CellObjects] Switch at %s link='%s'" % [pos, link_id])


## Spawn drops when an enemy is defeated.
func _spawn_enemy_drops(pos: Vector3, enemy_id: String) -> void:
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	var meseta_min: int = 5
	var meseta_max: int = 20
	var enemy_name: String = enemy_id.capitalize()
	if enemy_data:
		meseta_min = int(enemy_data.meseta_min) if int(enemy_data.meseta_min) > 0 else 5
		meseta_max = int(enemy_data.meseta_max) if int(enemy_data.meseta_max) > 0 else 20
		enemy_name = str(enemy_data.name)

	# Always drop meseta
	var dm := DropMesetaScript.new()
	dm.amount = randi_range(meseta_min, meseta_max)
	var offset := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
	_map_root.add_child(dm)
	dm.position = pos + offset
	_room_drops.append(dm)
	print("[EnemyDrop] Meseta %d at %s" % [dm.amount, dm.position])

	# Roll for item drop (15% chance)
	if randf() < 0.15:
		var area_id: String = SessionManager.get_current_area_id()
		var difficulty: String = str(SessionManager.get_session().get("difficulty", "normal"))
		var drop_area: String = AREA_DROP_KEYS.get(area_id, "gurhacia-valley")
		var drop_list: Array = DropRegistry.get_enemy_drops(difficulty, drop_area, enemy_name)
		if drop_list.size() > 0:
			var item_name: String = str(drop_list[randi() % drop_list.size()])
			var item_id: String = item_name.to_lower().replace(" ", "_").replace("/", "_")
			var di := DropItemScript.new()
			di.item_id = item_id
			di.amount = 1
			var item_offset := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
			_map_root.add_child(di)
			di.position = pos + item_offset
			_room_drops.append(di)
			print("[EnemyDrop] Item '%s' (id=%s) at %s" % [item_name, item_id, di.position])


## Spawn a message pack element.
func _spawn_message(pos: Vector3, text: String, state: String = "available", reaction: Array = []) -> void:
	var msg := MessagePackScript.new()
	msg.message_text = text
	_map_root.add_child(msg)
	msg.position = pos
	_fixup_element_materials(msg)
	# Re-run scroll material setup after fixup replaced materials
	msg._setup_scroll_material()
	if state != "available":
		msg.set_state(state)
	# Store and connect reaction dialog — companion speech bubble plays after reading
	msg.reaction_dialog = reaction
	if not reaction.is_empty() and _companion and is_instance_valid(_companion):
		msg.message_read.connect(_on_message_read_reaction.bind(reaction))
	_room_messages.append(msg)
	print("[CellObjects] Message at %s (text=%d chars, state=%s, reaction=%d pages)" % [pos, text.length(), state, reaction.size()])


func _on_message_read_reaction(_text: String, reaction: Array) -> void:
	if not _companion or not is_instance_valid(_companion):
		return
	# Play each reaction page as a speech bubble with delay between pages
	var delay := 0.0
	for page in reaction:
		var speech_text: String = str(page.get("text", ""))
		var speaker: String = str(page.get("speaker", ""))
		var duration: float = maxf(3.0, speech_text.length() / 20.0)
		if delay > 0:
			get_tree().create_timer(delay).timeout.connect(
				_companion.show_speech.bind(speech_text, speaker, duration)
			)
		else:
			_companion.show_speech(speech_text, speaker, duration)
		delay += duration + 0.5


func _spawn_story_prop(pos: Vector3, prop_path: String, rot_deg: float = 0, prop_scale: float = 1.0) -> void:
	var prop := StoryPropScript.new()
	prop.prop_path = prop_path
	prop.prop_scale = prop_scale
	_map_root.add_child(prop)
	prop.position = pos
	if rot_deg != 0:
		prop.rotation.y = deg_to_rad(rot_deg)
	_room_props.append(prop)
	print("[CellObjects] StoryProp at %s (path=%s)" % [pos, prop_path])


func _spawn_dialog_trigger(pos: Vector3, trigger_id: String, dlg: Array, state: String = "ready", condition: String = "enter", act: Array = [], size: Vector3 = Vector3.ZERO) -> void:
	if state == "triggered":
		return  # Already triggered — don't respawn
	var trigger := DialogTriggerScript.new()
	trigger.trigger_id = trigger_id
	trigger.dialog = dlg
	trigger.trigger_condition = condition
	trigger.actions = act
	if size != Vector3.ZERO:
		trigger.collision_size = size
	# Route companion-speaker dialogs to speech bubble
	var is_comp_dlg := _is_companion_dialog(dlg)
	print("[DialogTrigger] companion=%s valid=%s is_comp_dialog=%s" % [_companion != null, is_instance_valid(_companion) if _companion else false, is_comp_dlg])
	if _companion and is_instance_valid(_companion) and is_comp_dlg:
		trigger.companion_node = _companion
		print("[DialogTrigger] → Routed '%s' to companion speech bubble" % trigger_id)
	_map_root.add_child(trigger)
	trigger.position = pos
	_room_triggers.append(trigger)
	print("[CellObjects] DialogTrigger at %s (id=%s, condition=%s, pages=%d, actions=%s, companion=%s)" % [pos, trigger_id, condition, dlg.size(), str(act), trigger.companion_node != null])


func _spawn_field_npc(pos: Vector3, npc_id: String, npc_name: String, dlg: Array, rot_deg: float = 0) -> void:
	var npc := FieldNpcScript.new()
	npc.npc_id = npc_id
	npc.npc_name = npc_name
	npc.dialog = dlg
	_map_root.add_child(npc)
	npc.position = pos
	if rot_deg != 0:
		npc.rotation.y = deg_to_rad(rot_deg)
	_room_npcs.append(npc)
	print("[CellObjects] FieldNpc '%s' (%s) at %s (dialog=%d pages)" % [npc_name, npc_id, pos, dlg.size()])


func _is_companion_dialog(dlg: Array) -> bool:
	## Returns true if the companion is the primary speaker.
	## Allows empty-speaker (narrator) lines mixed in.
	if dlg.is_empty() or not _companion:
		return false
	var comp_id: String = _companion.companion_id.to_lower()
	var has_companion_line := false
	for page in dlg:
		var speaker: String = str(page.get("speaker", "")).to_lower()
		if speaker.is_empty():
			continue  # narrator line — ok
		# Normalize "Dr. Carlo" → "dr_carlo" for comparison
		var normalized: String = speaker.replace(" ", "_").replace(".", "")
		if normalized == comp_id or speaker == comp_id:
			has_companion_line = true
		else:
			return false  # another named speaker — use dialog box
	return has_companion_line


func _spawn_companion() -> void:
	# Remove previous companion if any
	if _companion and is_instance_valid(_companion):
		_companion.queue_free()
		_companion = null

	var companions := SessionManager.get_companions()
	if companions.is_empty():
		return

	var comp_id: String = str(companions[0])
	_companion = CompanionNpcScript.new()
	_companion.companion_id = comp_id
	_companion.name = "Companion_" + comp_id

	# Position 3 units behind the player
	var behind := Vector3(0, 0, 3.0)
	if player:
		behind = -Vector3(sin(player.player_rotation), 0, cos(player.player_rotation)) * 3.0
		add_child(_companion)
		_companion.global_position = player.global_position + behind
		_companion.global_position.y = player.global_position.y
	else:
		add_child(_companion)

	print("[Companion] Spawned '%s' behind player" % comp_id)


func _spawn_warp_point(pos: Vector3, target_section: int, target_cell: String, target_position: Vector3) -> void:
	var wp := WarpPointScript.new()
	wp.warp_section = target_section
	wp.warp_cell = target_cell
	wp.warp_position = target_position
	wp.name = "WarpPoint"
	_map_root.add_child(wp)
	wp.position = pos
	wp.activated.connect(func() -> void:
		print("[ValleyField] Warp activated → section %d, cell %s, position %s" % [target_section, target_cell, target_position])
		SessionManager.set_current_section(target_section)
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": target_cell,
			"spawn_edge": "",
			"spawn_position": [target_position.x, target_position.y, target_position.z],
			"keys_collected": {},
			"gates_opened": {},
			"visited_cells": {},
			"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
		})
	)
	print("[CellObjects] WarpPoint at %s → section %d, cell %s, position %s" % [pos, target_section, target_cell, target_position])




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
					if _room_minimap:
						_room_minimap.set_gate_locked(dir, true)
					print("[CellObjects] Gate %s locked (enemies present)" % dir)
					break

	# Lock area warps (like gates) until room clear — skip entry direction
	for child in get_children():
		if child is AreaWarp and child.name.begins_with("AreaWarp_"):
			var aw_dir: String = child.name.trim_prefix("AreaWarp_")
			if aw_dir == _spawn_edge:
				continue  # Don't lock entry area warp
			child.element_state = "locked"
			child._apply_state()
			_warp_edge_locked.append(child)
			# Add physical blocker
			var blocker := StaticBody3D.new()
			blocker.name = "AreaWarpBlocker_%s" % aw_dir
			blocker.collision_layer = 1
			var bshape := CollisionShape3D.new()
			var bbox := BoxShape3D.new()
			bbox.size = Vector3(6, 4, 1.5)
			bshape.shape = bbox
			bshape.position.y = 2.0
			blocker.add_child(bshape)
			add_child(blocker)
			blocker.global_position = child.global_position
			blocker.global_rotation = child.global_rotation
			_warp_edge_locked.append(blocker)
			# Disable matching gate trigger (uses same GateTrigger_ naming)
			var aw_trigger := _find_child_by_name(self, "GateTrigger_%s" % aw_dir) as Area3D
			if aw_trigger:
				aw_trigger.monitoring = false
				_warp_edge_locked.append(aw_trigger)
			print("[CellObjects] AreaWarp locked (enemies present) [dir=%s]" % aw_dir)
			if _room_minimap:
				_room_minimap.set_gate_locked(aw_dir, true)


## Called when an enemy is defeated — check if all cleared.
func _check_room_clear() -> void:
	for enemy in _room_enemies:
		if is_instance_valid(enemy) and enemy.element_state != "dead":
			return  # Still alive enemies

	# Check for next wave
	if _current_wave < _max_wave:
		_current_wave += 1
		print("[CellObjects] Wave %d cleared! Spawning wave %d" % [_current_wave - 1, _current_wave])
		_spawn_wave(_current_wave)
		return

	print("[CellObjects] Room cleared! Opening %d locked gates" % _room_gates_locked.size())
	for gate in _room_gates_locked:
		if is_instance_valid(gate):
			gate.open()
			var dir := _gate_direction(gate)
			# Enable the gate's trigger
			var trigger := _find_child_by_name(self, "GateTrigger_%s" % dir) as Area3D
			if trigger:
				trigger.monitoring = true
			if _room_minimap and not dir.is_empty():
				_room_minimap.set_gate_locked(dir, false)
	_room_gates_locked.clear()

	# Unlock area warps (same pattern as gates above)
	for node in _warp_edge_locked:
		if is_instance_valid(node):
			if node is AreaWarp:
				node.element_state = "open"
				node._apply_state()
				var aw_dir: String = node.name.trim_prefix("AreaWarp_") if node.name.begins_with("AreaWarp_") else ""
				if _room_minimap and not aw_dir.is_empty():
					_room_minimap.set_gate_locked(aw_dir, false)
				print("[CellObjects] AreaWarp unlocked (room cleared) [dir=%s]" % aw_dir)
			elif node is StaticBody3D:
				node.queue_free()
			elif node is Area3D:
				node.monitoring = true
	_warp_edge_locked.clear()

	# Drop key on room clear if configured
	var key_drop_target: String = str(_current_cell.get("key_drop", ""))
	var current_pos: String = str(_current_cell.get("pos", ""))
	if not key_drop_target.is_empty():
		var drop_tracking_key := current_pos + ">" + key_drop_target
		if not _keys_collected.has(drop_tracking_key):
			_drop_key_on_clear(key_drop_target, drop_tracking_key)

	# Activate locked messages on room clear (scroll animation turns on)
	for msg in _room_messages:
		if is_instance_valid(msg) and msg.element_state == "locked":
			msg.set_state("available")
			if msg._prompt_label and msg._player_nearby:
				msg._prompt_label.visible = true

	# Fire room_clear dialog triggers
	for rc_trigger in _room_triggers:
		if is_instance_valid(rc_trigger) and rc_trigger.trigger_condition == "room_clear" and rc_trigger.element_state == "ready":
			rc_trigger.activate()

	# Spawn deferred telepipe objects (spawn_condition=room_clear) — takes precedence
	if not _deferred_telepipe.is_empty():
		var tp_pos: Vector3 = _deferred_telepipe.get("position", Vector3.ZERO)
		_spawn_telepipe(tp_pos)
		_deferred_telepipe = {}
		_needs_telepipe = false
	elif _needs_telepipe:
		# Fallback: end cells without explicit telepipe object
		_needs_telepipe = false
		_spawn_telepipe(Vector3.ZERO)


## Spawn enemies for a specific wave number.
func _spawn_wave(wave_num: int) -> void:
	_room_enemies.clear()
	var wave_objs: Array = _wave_enemy_data.get(wave_num, [])
	for obj in wave_objs:
		var pos_arr: Array = obj.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var enemy_id: String = str(obj.get("enemy_id", "lizard"))
		_spawn_enemy(pos, enemy_id)
	print("[CellObjects] Wave %d: spawned %d enemies" % [wave_num, wave_objs.size()])


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


func _toggle_all_collision() -> void:
	_show_all_collision = not _show_all_collision
	if _show_all_collision and _debug_all_collision_meshes.is_empty():
		_build_all_collision_debug()
	for m in _debug_all_collision_meshes:
		if is_instance_valid(m):
			m.visible = _show_all_collision
	_update_debug_label()


func _build_all_collision_debug() -> void:
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionShape3D and node.shape and node.get_parent() is StaticBody3D:
			var debug_mesh := MeshInstance3D.new()
			var shape: Shape3D = node.shape
			if shape is BoxShape3D:
				var box_mesh := BoxMesh.new()
				box_mesh.size = shape.size
				debug_mesh.mesh = box_mesh
			elif shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = shape.get_faces()
				if faces.is_empty():
					continue
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
				debug_mesh.mesh = array_mesh
			elif shape is CylinderShape3D:
				var cyl_mesh := CylinderMesh.new()
				cyl_mesh.top_radius = shape.radius
				cyl_mesh.bottom_radius = shape.radius
				cyl_mesh.height = shape.height
				debug_mesh.mesh = cyl_mesh
			elif shape is SphereShape3D:
				var sphere_mesh := SphereMesh.new()
				sphere_mesh.radius = shape.radius
				sphere_mesh.height = shape.radius * 2.0
				debug_mesh.mesh = sphere_mesh
			elif shape is CapsuleShape3D:
				var cap_mesh := CapsuleMesh.new()
				cap_mesh.radius = shape.radius
				cap_mesh.height = shape.height
				debug_mesh.mesh = cap_mesh
			else:
				continue
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.2, 0.2, 0.25)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			debug_mesh.material_override = mat
			debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			debug_mesh.global_transform = node.global_transform
			debug_mesh.visible = _show_all_collision
			add_child(debug_mesh)
			_debug_all_collision_meshes.append(debug_mesh)
			# Label showing parent node name
			var label := Label3D.new()
			label.text = node.get_parent().name
			label.font_size = 32
			label.modulate = Color(1.0, 0.3, 0.3)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.position = Vector3(0, 1.5, 0)
			debug_mesh.add_child(label)
			_debug_all_collision_meshes.append(label)
		for child in node.get_children():
			stack.push_back(child)


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
		+ "F8  Spawns     %s\n" % (on if _show_spawn_points else off) \
		+ "F9  All col    %s" % (on if _show_all_collision else off)


func _transition_to_cell(target_pos: String, spawn_edge: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_save_cell_state()
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": target_pos,
		"spawn_edge": spawn_edge,
		"from_cell_pos": str(_current_cell.get("pos", "")),
		"keys_collected": _keys_collected,
		"gates_opened": _gates_opened,
		"visited_cells": _visited_cells,
		"cell_states": _cell_states,
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
			"gates_opened": {},
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
		if _pause_menu and not _pause_menu.visible:
			_pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
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
			KEY_F9:
				_toggle_all_collision()
				get_viewport().set_input_as_handled()
			KEY_K:
				print("[DEBUG] Kill all enemies (%d)" % _room_enemies.size())
				for enemy in _room_enemies:
					if is_instance_valid(enemy) and enemy.element_state != "dead":
						enemy.take_damage(9999)
				get_viewport().set_input_as_handled()
