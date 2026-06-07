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
const KeyGateScript := preload("res://scripts/3d/elements/key_gate.gd")
const WaypointScript := preload("res://scripts/3d/elements/waypoint.gd")
const RoomMinimapScript := preload("res://scripts/3d/field/room_minimap.gd")
const GridMinimapScript := preload("res://scripts/3d/field/grid_minimap.gd")
const FieldHudScript := preload("res://scripts/3d/field/field_hud.gd")
const EnemyBaseScript := preload("res://scripts/3d/enemies/enemy_base.gd")
# Lazily loaded by CellObjectSpawner via the controller back-reference; the
# assignment lands here so the load happens at most once per controller.
var PoisonLilyScript: GDScript = null
const TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")
const CompanionNpcScript := preload("res://scripts/3d/elements/companion_npc.gd")
# Start menu handled by PsoStartMenu autoload

const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

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
var _moonlight: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _transitioning := false
var _keys_collected: Dictionary = {}  # cell_pos → true (key pickup, prevents respawn)
var _gates_opened: Dictionary = {}   # cell_pos → true (gate opened by player, stays open on re-entry)
var _cell_states: Dictionary = {}    # cell_pos → { objects: [{state, ...}], drops: [{type, pos, ...}] }
var _current_cell: Dictionary = {}
var _portal_data: Dictionary = {}
var _map_overlay: CanvasLayer
var _room_minimap: Control
var _grid_minimap: Control
var _field_hud: CanvasLayer
var _blob_shadow: MeshInstance3D
var _stage_config: Dictionary = {}
var _spawn_edge: String = ""
var _rotation_deg: int = 0
var _visited_cells: Dictionary = {}  # cell_pos → true
var _key_hud_label: Label
var _gate_nudge_mode: bool = false
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
var _room_walls: Array = []       # Wall nodes in current room
var _fence_links: Dictionary = {}  # link_id → { "fences": [], "switches": [] }
# NOTE: activated fence-switch links are stored in SessionManager (persists across cell transitions)
var _room_gates_locked: Array = []  # Gate elements locked until enemies cleared
var _warp_edge_locked: Array = []  # AreaWarp + exit trigger locked until enemies cleared
var _needs_telepipe: bool = false      # End cell without warp_edge — spawn telepipe on room clear
var _companion: CharacterBody3D = null  # CompanionNpc following the player
var _deferred_telepipe: Dictionary = {} # Telepipe data deferred until room_clear
var _deferred_quest_complete_telepipe: Dictionary = {} # Telepipe deferred until SessionManager.quest_completed fires
var _deferred_room_clear_items: Array = [] # quest_item objects with spawn_condition=room_clear, deferred until room clear
var _objective_locked_exits: Array = [] # Exit triggers locked until quest objectives complete
var _weather_node: GPUParticles3D = null # Weather effect (snow, rain) attached to player

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
var _debug_floor_viz: MeshInstance3D       # DebugFloorViz green overlay
var _debug_gate_spheres: Array = []        # GateMark/SpawnMark/TriggerMark spheres
var _debug_panel: PanelContainer

## Cell-object spawning + save/restore, extracted into its own module.
## Holds a back-reference to this controller and accesses controller state
## through it. Constructed in _ready (needs `self`).
var _cell_spawner: CellObjectSpawner

## Portal-data parsing + gate/trigger handling, extracted into PortalGateManager.
## Holds a back-reference to this controller and accesses controller state
## through it. Constructed in _ready (needs `self`).
var _gate_mgr: PortalGateManager

## Weather + stage-effects + embedded-light handling, extracted into WeatherController.
## Holds a back-reference to this controller and accesses controller state
## through it. Constructed in _ready (needs `self`).
var _weather: WeatherController


## Verbose field-debug log, gated by DebugConfig.verbose_field (#215-E).
## All [ValleyField]/[FieldElements]/[CellObjects] diagnostics go through here
## so normal play stays quiet; autopilot runs flip the flag on automatically.
func _fdbg(msg: String) -> void:
	if DebugConfig.verbose_field:
		print(msg)


func _ready() -> void:
	_cell_spawner = CellObjectSpawner.new(self)
	_gate_mgr = PortalGateManager.new(self)
	_weather = WeatherController.new(self)
	# Group registration so Inventory.use_item("telepipe") can locate the
	# active field controller without dragging in scene-tree navigation.
	add_to_group("field_controller")

	# Grab lighting nodes immediately so _process() applies TimeManager from frame 1
	_world_env = $WorldEnvironment
	_dir_light = $DirectionalLight3D
	_sky_material = _world_env.environment.sky.sky_material as ProceduralSkyMaterial

	# Moonlight — rotation derived from sun direction by TimeManager
	_moonlight = DirectionalLight3D.new()
	_moonlight.name = "Moonlight"
	_moonlight.light_color = Color(0.5, 0.6, 0.9)
	_moonlight.light_energy = 0.0
	_moonlight.shadow_enabled = false
	_moonlight.visible = false
	add_child(_moonlight)

	# Indoor stages take a one-shot daylight apply and then opt out of the
	# per-frame _process update — interior lighting shouldn't track the
	# day/night cycle. Save and restore current_hour so the world clock
	# isn't affected.
	var initial_stage_id: String = str(_current_cell.get("stage_id", "")) if not _current_cell.is_empty() else ""
	if _is_indoor_stage(initial_stage_id):
		var saved_hour: float = TimeManager.current_hour
		TimeManager.current_hour = 10.0
		TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light, _moonlight)
		TimeManager.current_hour = saved_hour
	else:
		TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light, _moonlight)

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

	# Play area music based on area_id + section variant
	var area_variant: String = str(section.get("area", "a"))
	MusicManager.play_field_music(area_id, area_variant)

	# Load visual mesh from raw stage
	var subfolder: String = _get_stage_subfolder(stage_id, area_cfg["folder"])
	var scene_path := "res://assets/stages/%s/%s/lndmd/%s_m.glb" % [subfolder, stage_id, stage_id]
	var floor_path := "res://assets/stages/%s/%s/lndmd/%s-floor.glb" % [subfolder, stage_id, stage_id]
	var obstacles_path := "res://assets/stages/%s/%s/lndmd/%s-obstacles.glb" % [subfolder, stage_id, stage_id]

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
	_weather._strip_embedded_lights(_map_root)
	_fix_materials(_map_root)

	# Load skybox GLB if present (e.g. wetlands boss s02z_na1 has a separate skybox model)
	var skybox_path := "res://assets/stages/%s/%s/lndmd/skybox/o0s_zsky.glb" % [subfolder, stage_id]
	if ResourceLoader.exists(skybox_path):
		var skybox_scene := load(skybox_path) as PackedScene
		if skybox_scene:
			var skybox_root := skybox_scene.instantiate() as Node3D
			skybox_root.name = "Skybox"
			_map_root.add_child(skybox_root)
			_fix_materials(skybox_root)
			_fdbg("[ValleyField] Loaded skybox: %s" % skybox_path)
	await get_tree().process_frame

	# Load floor collision from separate floor GLB, fall back to embedded -colonly meshes
	if ResourceLoader.exists(floor_path):
		var floor_scene := load(floor_path) as PackedScene
		if floor_scene:
			var floor_root := floor_scene.instantiate() as Node3D
			floor_root.name = "FloorCollision"
			add_child(floor_root)
			# Check if Godot's -colonly suffix import created StaticBody3D nodes
			var has_static := MapCollisionBuilder.has_static_body(floor_root)
			if has_static:
				MapCollisionBuilder.setup_map_collision(floor_root)
				_fdbg("[ValleyField] Floor collision from GLB import suffix: %s" % floor_path)
			else:
				# Suffix import didn't create collision — build manually from meshes
				MapCollisionBuilder.create_collision_from_meshes(floor_root)
				_fdbg("[ValleyField] Floor collision built manually from mesh: %s" % floor_path)
		else:
			MapCollisionBuilder.setup_map_collision(_map_root)
	else:
		MapCollisionBuilder.setup_map_collision(_map_root)

	# Load obstacle collision (walls) from separate obstacles GLB.
	# PSZ_AUTOPILOT_NO_OBSTACLES=1 skips this — used while iterating on the
	# autopilot's waypoint graph so the autopilot doesn't wedge on obstacle
	# colliders that the spec doesn't yet route around.
	var skip_obstacles := OS.has_environment("PSZ_AUTOPILOT_NO_OBSTACLES")
	if skip_obstacles:
		_fdbg("[ValleyField] PSZ_AUTOPILOT_NO_OBSTACLES set — skipping obstacle collision for %s" % stage_id)
	elif ResourceLoader.exists(obstacles_path):
		var obs_scene := load(obstacles_path) as PackedScene
		if obs_scene:
			var obs_root := obs_scene.instantiate() as Node3D
			obs_root.name = "ObstacleCollision"
			add_child(obs_root)
			if MapCollisionBuilder.has_static_body(obs_root):
				MapCollisionBuilder.configure_collision_nodes(obs_root)
				_fdbg("[ValleyField] Obstacle collision from GLB import suffix: %s" % obstacles_path)
			else:
				MapCollisionBuilder.create_collision_from_meshes(obs_root)
				_fdbg("[ValleyField] Obstacle collision built manually from mesh: %s" % obstacles_path)

	# Spawn stage particle effects (spores, embers, etc.)
	_weather._spawn_stage_effects(stage_id)

	# DEBUG: Visualize floor collision mesh as semi-transparent green overlay
	_debug_show_floor_collision()

	await get_tree().process_frame

	# Read baked portal data from quest JSON (pre-computed by quest editor)
	var baked_portals: Dictionary = _current_cell.get("portals", {})
	if not baked_portals.is_empty():
		_portal_data = _gate_mgr._parse_baked_portals(baked_portals)
	else:
		# Fallback: build from config (for non-quest or old quest JSON without baked portals)
		_portal_data = _gate_mgr._build_portal_data_from_config(_stage_config)
		if _rotation_deg != 0:
			var remapped := {}
			for orig_dir in _portal_data:
				if orig_dir == "default":
					remapped["default"] = _portal_data["default"]
				else:
					remapped[StageRotation.rotate_dir(orig_dir, _rotation_deg)] = _portal_data[orig_dir].duplicate()
			_portal_data = remapped

	# Ensure all stage config portals are in _portal_data (some quest JSONs
	# omit unconnected portals like warp_edge from the portals dict).
	for cp in _stage_config.get("portals", []):
		var base_dir: String = str(cp.get("direction", ""))
		var game_dir: String = StageRotation.rotate_dir(base_dir, _rotation_deg)
		if not _portal_data.has(game_dir):
			_portal_data[game_dir] = _gate_mgr._compute_portal_from_config(cp, game_dir)
			_fdbg("[ValleyField]   Synthesized missing portal: '%s' (config dir='%s')" % [game_dir, base_dir])

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

	_fdbg("[ValleyField] ══════════════════════════════════════════")
	_fdbg("[ValleyField] CELL LOAD: %s  stage=%s" % [
		str(_current_cell.get("pos", "?")), stage_id])
	_fdbg("[ValleyField]   section: %d/%d (%s, area=%s)" % [
		section_idx + 1, sections.size(),
		str(section.get("type", "?")), str(section.get("area", "?"))])
	_fdbg("[ValleyField]   spawn_edge='%s'" % spawn_edge)

	# Log portal data
	_fdbg("[ValleyField]   ── Portal data ──")
	for key in _portal_data:
		var pd: Dictionary = _portal_data[key]
		_fdbg("[ValleyField]     '%s': spawn=%s  trigger=%s" % [
			key, pd["spawn_pos"], pd["trigger_pos"]])

	# Determine warp_edge early (needed for spawn resolution)
	var warp_edge: String = str(_current_cell.get("warp_edge", ""))

	# Spawn player
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	var spawn_reason := ""
	# Telepipe-arrival precedence: when the city-side telepipe handler warped
	# us back here, it passes telepipe_arrival_pos so the player materialises
	# exactly where they dropped the pipe rather than at the section's normal
	# entry portal. Skip if zero (sentinel for "not a telepipe arrival").
	var telepipe_arrival_pos: Vector3 = data.get("telepipe_arrival_pos", Vector3.ZERO)
	if telepipe_arrival_pos != Vector3.ZERO:
		spawn_pos = telepipe_arrival_pos
		spawn_reason = "telepipe arrival at %s" % telepipe_arrival_pos
	var raw_spawn_pos: Array = data.get("spawn_position", [])
	if spawn_reason.is_empty() and raw_spawn_pos.size() == 3:
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
					_fdbg("[ValleyField] Inferred spawn_edge='%s' from spawn_position proximity (dist=%.2f)" % [_spawn_edge, best_dist])
	if not spawn_reason.is_empty():
		pass  # spawn_position already resolved above
	elif not spawn_edge.is_empty() and _portal_data.has(spawn_edge):
		spawn_pos = _portal_data[spawn_edge]["spawn_pos"]
		var gate_pos: Vector3 = _portal_data[spawn_edge].get("gate_pos", spawn_pos)
		# Face inward (toward room center, away from gate)
		spawn_rot = _facing_yaw(gate_pos, Vector3.ZERO)
		spawn_reason = "entry from %s, facing inward (yaw=%.2f)" % [spawn_edge, spawn_rot]
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

	_fdbg("[ValleyField]   ── Spawn Resolution ──")
	_fdbg("[ValleyField]     pos=%s  rot=%.2f rad (%.1f°)" % [
		spawn_pos, spawn_rot, rad_to_deg(spawn_rot)])
	_fdbg("[ValleyField]     reason: %s" % spawn_reason)
	_fdbg("[ValleyField]     StageRotation.dir_to_yaw table: N=%.2f E=%.2f S=%.2f W=%.2f" % [
		StageRotation.dir_to_yaw("north"), StageRotation.dir_to_yaw("east"), StageRotation.dir_to_yaw("south"), StageRotation.dir_to_yaw("west")])

	var connections: Dictionary = _current_cell.get("connections", {})
	_fdbg("[ValleyField]   ── Grid Cell Data ──")
	_fdbg("[ValleyField]     connections: %s" % str(connections))
	_fdbg("[ValleyField]     warp_edge: '%s'" % warp_edge)
	_fdbg("[ValleyField]     cell keys: %s" % str(_current_cell.keys()))
	# Log the full cell dict (truncated for readability)
	for ck in _current_cell:
		if ck != "connections":
			_fdbg("[ValleyField]     cell.%s = %s" % [ck, str(_current_cell[ck])])
	_fdbg("[ValleyField] ══════════════════════════════════════════")

	_spawn_player(spawn_pos, spawn_rot)
	_weather._spawn_weather()
	if from_cell_pos.is_empty():
		SfxManager.play("res://assets/sfx/common/common_010.wav")
	await get_tree().process_frame

	# Create gate triggers for each connection (entry edge gets delayed activation)
	# Key-gate direction trigger starts disabled — enabled when gate opens
	var is_key_gate: bool = _current_cell.get("is_key_gate", false)
	var key_gate_dirs: Array = _gate_mgr._get_locked_gates(_current_cell)
	for dir in connections:
		if not _portal_data.has(dir):
			continue
		var is_entry: bool = (dir == spawn_edge)
		var is_locked_gate: bool = is_key_gate and dir in key_gate_dirs and not _gates_opened.has("%s:%s" % [str(_current_cell.get("pos", "")), dir])
		_gate_mgr._create_gate_trigger(dir, str(connections[dir]), _portal_data[dir], is_entry, is_locked_gate)

	# (warp_edge exit is handled by area warp auto-generation in _spawn_field_elements)

	# Place key pickup if this cell has one
	if _current_cell.get("has_key", false):
		var key_for: String = str(_current_cell.get("key_for_cell", ""))
		if not key_for.is_empty() and not _keys_collected.has(key_for):
			_gate_mgr._create_key_pickup(key_for)

	_spawn_field_elements()
	_spawn_companion()
	_cell_spawner._spawn_cell_objects()
	_setup_debug_panel()

	# Re-spawn the player-dropped telepipe if one is active in this exact
	# (area, section, cell). Triggers when the player backtracks via the city
	# warp teleporter — TelepipeManager.is_active() stays true after suspend,
	# so we restore the visual cyan pillar at its saved world_pos.
	#
	# Skipped on telepipe-traversal arrivals because consume_return() in the
	# city already wiped the manager state before this scene loaded.
	var current_area_id: String = SessionManager.get_current_area_id()
	var current_cell_pos_str: String = str(_current_cell.get("pos", ""))
	if TelepipeManager.matches_field(current_area_id, section_idx, current_cell_pos_str):
		var saved: Dictionary = TelepipeManager.get_state()
		respawn_player_telepipe_from_state(saved.get("world_pos", Vector3.ZERO))

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

	# Debug info overlay — quest ID / mission ID, section, cell position
	var debug_session: Dictionary = SessionManager.get_session()
	var debug_id: String = str(debug_session.get("quest_id", ""))
	if debug_id.is_empty():
		debug_id = str(debug_session.get("mission_id", ""))
	var debug_section_text: String = "Section %d/%d (%s)" % [
		section_idx + 1, sections.size(), str(section.get("type", "?"))]
	var debug_cell_pos: String = str(_current_cell.get("pos", ""))
	_field_hud.set_debug_info(debug_id, debug_section_text, debug_cell_pos)

	_room_minimap = RoomMinimapScript.new()
	_room_minimap.setup(stage_id, area_cfg["folder"], _portal_data,
		_current_cell.get("connections", {}),
		str(_current_cell.get("warp_edge", "")), _map_root, _rotation_deg, _spawn_edge)
	_field_hud.add_child(_room_minimap)
	map_panel.top_offset = 200.0

	# Key HUD (drawn below minimap)
	_setup_key_hud(cells)

	# Grid minimap (toggleable with M key, shows section grid layout)
	var grid_minimap_visible: bool = data.get("grid_minimap_visible", true)
	_grid_minimap = GridMinimapScript.new()
	_grid_minimap.setup(cells, str(_current_cell.get("pos", "")),
		_visited_cells, "Section %d" % (section_idx + 1))
	_grid_minimap.visible = grid_minimap_visible
	_grid_minimap.set_meta("toggled_off", not grid_minimap_visible)
	_field_hud.add_child(_grid_minimap)

	# Sync initial gate lock states to minimap (gates were created before minimap)
	var cur_pos: String = str(_current_cell.get("pos", ""))
	for gate in _room_gates_locked:
		if is_instance_valid(gate):
			var dir := _gate_direction(gate)
			if not dir.is_empty():
				_room_minimap.set_gate_locked(dir, true)
				if _grid_minimap:
					_grid_minimap.set_gate_state(cur_pos, dir, "locked")
	# Key-gate per-direction locked state — each direction tracks independently.
	var is_key_gate_cell: bool = _current_cell.get("is_key_gate", false)
	var kg_dirs: Array = _gate_mgr._get_locked_gates(_current_cell)
	if is_key_gate_cell:
		for kg_dir_s in kg_dirs:
			var kg_dir: String = str(kg_dir_s)
			if _gates_opened.has("%s:%s" % [cur_pos, kg_dir]):
				continue
			_room_minimap.set_gate_locked(kg_dir, true)
			if _grid_minimap:
				_grid_minimap.set_gate_state(cur_pos, kg_dir, "locked")

	# Lock warp_edge on minimap if objectives are pending
	var warp_e: String = str(_current_cell.get("warp_edge", ""))
	if not warp_e.is_empty() and _has_pending_objectives():
		_room_minimap.set_gate_locked(warp_e, true)
		if _grid_minimap:
			_grid_minimap.set_gate_state(cur_pos, warp_e, "locked")

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
	_fdbg("[ValleyField] Section warp requirements met — unlocking exits")
	_gate_mgr._unlock_objective_exits()


func _on_quest_completed() -> void:
	_fdbg("[ValleyField] Quest objectives complete — unlocking exits")
	_gate_mgr._unlock_objective_exits()
	# Spawn any quest_complete-deferred telepipe authored in the current cell.
	if not _deferred_quest_complete_telepipe.is_empty():
		var tp_pos: Vector3 = _deferred_quest_complete_telepipe.get("position", Vector3.ZERO)
		_fdbg("[ValleyField] Spawning quest_complete-deferred telepipe at %s" % tp_pos)
		_spawn_telepipe(tp_pos)
		_deferred_quest_complete_telepipe = {}
		return
	# No explicit telepipe object. If the current cell has key_drop authored,
	# re-enter _check_room_clear so its objectives-complete branch spawns the
	# telepipe at key_drop_position. Covers the case where the final quest_item
	# is picked up *after* room_clear already ran (e.g. hildegao "ate" body
	# part in finding_ogi's section B terminals). _check_room_clear early-returns
	# if enemies remain and its other side-effects are idempotent.
	if not str(_current_cell.get("key_drop", "")).is_empty():
		_check_room_clear()


func _process(_delta: float) -> void:
	FrameProfiler.mark("field_lighting")
	if _world_env and _sky_material and _dir_light:
		var cur_stage_id: String = str(_current_cell.get("stage_id", "")) if not _current_cell.is_empty() else ""
		if not _is_indoor_stage(cur_stage_id):
			TimeManager.apply_to_scene(_world_env.environment, _sky_material, _dir_light, _moonlight)
	if _blob_shadow and player:
		_blob_shadow.global_position = Vector3(player.global_position.x, 0.05, player.global_position.z)
	FrameProfiler.mark("field_minimap")
	if _room_minimap and player and _map_root:
		_room_minimap.update_player(player.global_position, player.player_rotation, _map_root)
	_sync_debug_config()
	FrameProfiler.mark("field_done")


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


## Compute yaw angle for facing from position `from_pos` toward `to_pos` (XZ plane).
func _facing_yaw(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	if dx * dx + dz * dz < 0.001:
		return 0.0
	return atan2(dx, dz)


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


const INDOOR_STAGES := ["s03b_lc2", "s03b_nb2", "s03b_ic1", "s03b_tc3", "s03b_lc1", "s03b_sa1"]

func _is_indoor_stage(stage_id: String) -> bool:
	if stage_id in INDOOR_STAGES:
		return true
	# Interior areas covered by prefix:
	# - s06* Arca Plant (a sealed plant/factory interior)
	# - s08* Eternal Tower
	# - s04* Makara Ruins, minus the two open-air stages:
	#     s04a_sa1 (entry plaza, outdoors)
	#     s04e_ia1 (section-E transition, outdoors)
	if stage_id.begins_with("s06") or stage_id.begins_with("s08"):
		return true
	if stage_id.begins_with("s04") and stage_id != "s04a_sa1" and stage_id != "s04e_ia1":
		return true
	return false


func _debug_show_floor_collision() -> void:
	## Visualize all floor collision shapes as a semi-transparent green mesh overlay.
	var faces := PackedVector3Array()
	MapCollisionBuilder.collect_collision_faces(self, faces)
	if faces.is_empty():
		_fdbg("[ValleyField] DEBUG: No collision faces found to visualize")
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
	mi.visible = DebugConfig.show_floor_collision
	add_child(mi)
	_debug_floor_viz = mi
	_fdbg("[ValleyField] DEBUG: Floor collision visualized — %d triangles" % (faces.size() / 3))


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
		var file := FileAccess.open(unified_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				_unified_config_cache = json.data as Dictionary
				_fdbg("[ValleyField] Loaded unified config: %d stages" % _unified_config_cache.size())
			file.close()

	# Load global texture fixes on first access
	if _global_texture_fixes.is_empty():
		var gtf_path := "res://data/stage_configs/global-texture-fixes.json"
		var gtf_file := FileAccess.open(gtf_path, FileAccess.READ)
		if gtf_file:
			var gtf_json := JSON.new()
			if gtf_json.parse(gtf_file.get_as_text()) == OK:
				_global_texture_fixes = gtf_json.data as Dictionary
				_fdbg("[ValleyField] Loaded global texture fixes: %d entries" % _global_texture_fixes.size())
			gtf_file.close()

	# Look up by stage_id
	if _unified_config_cache.has(stage_id):
		return _unified_config_cache[stage_id] as Dictionary

	return {}


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
	## Stage materials use per-vertex shading with vertex_color_use_as_albedo
	## so pre-baked vertex colors provide surface detail while real 3D lighting
	## (DirectionalLight3D, ambient, OmniLight3D) drives day/night atmosphere.
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
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
					new_mat.vertex_color_use_as_albedo = true
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
	mi.visible = DebugConfig.show_gate_dots
	add_child(mi)
	mi.global_position = Vector3(pos.x, 1.5, pos.z)
	_debug_gate_spheres.append(mi)


func _compute_drop_position() -> Vector3:
	# Use authored key_drop_position when present; otherwise fall back to the
	# centroid of the cell's non-default portals (same heuristic as the key
	# drop). Shared between key drops and quest_complete telepipe spawns so
	# both land at the same spot.
	var authored_pos: Array = _current_cell.get("key_drop_position", [])
	if authored_pos.size() == 3:
		return Vector3(float(authored_pos[0]), float(authored_pos[1]), float(authored_pos[2]))
	var portal_positions: Array[Vector3] = []
	for dir in _portal_data:
		if dir != "default":
			portal_positions.append(_portal_data[dir]["spawn_pos"])
	if portal_positions.size() >= 2:
		var sum := Vector3.ZERO
		for pp in portal_positions:
			sum += pp
		var avg := sum / float(portal_positions.size())
		avg.y = 0.5
		return avg
	if portal_positions.size() == 1:
		var single := portal_positions[0]
		single.y = 0.5
		return single
	return Vector3(0, 0.5, 0)


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
	var key_gate_dirs: Array = _gate_mgr._get_locked_gates(_current_cell)

	# StartWarp on is_start cells at the entry portal (only first section).
	# Spec: pressing E on this warp returns the player to the city teleporter
	# room — same exit behaviour as the boss-clear telepipe, just available
	# from the spawn room without needing to clear the area first. This is
	# the "first-room return teleporter" half of issue #136.
	var section_idx_for_warp: int = SessionManager.get_current_section()
	if _current_cell.get("is_start", false) and section_idx_for_warp == 0:
		var start_warp := StartWarpScript.new()
		start_warp.auto_collect = false
		start_warp.interactable = true
		start_warp.interacted.connect(_on_start_warp_interacted)
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
				start_rot = StageRotation.dir_to_yaw(warp_edge)
			else:
				for dir in _portal_data:
					if dir != "default":
						start_pos = _portal_data[dir]["spawn_pos"]
						start_rot = StageRotation.dir_to_yaw(str(OPPOSITE.get(dir, "south")))
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

	# entry_direction is only meaningful at the section's start cell — that's
	# where the player materialises. At any other cell (including the end cell
	# where warp_edge lives), the same direction might collide with a
	# warp_edge or exit_dir and mis-classify the portal as a backward entry.
	# Restricting is_entry to the start cell prevents that collision.
	var is_start_cell: bool = bool(_current_cell.get("is_start", false))

	for portal_dir in _portal_data:
		if portal_dir == "default":
			continue
		if connections.has(portal_dir):
			continue  # Has a connection — handled by gate logic above

		# Determine warp target based on direction
		var target_section := 0
		var target_cell := ""
		var target_position := Vector3.ZERO
		var is_entry: bool = is_start_cell and (portal_dir == entry_dir)
		var is_exit: bool = (portal_dir == warp_edge or portal_dir == exit_dir) and not is_entry

		var is_final_exit: bool = false
		if is_exit and section_idx_for_warp + 1 < sections_for_warp.size():
			var next_sec: Dictionary = sections_for_warp[section_idx_for_warp + 1]
			target_section = section_idx_for_warp + 1
			target_cell = str(next_sec.get("start_pos", ""))
		elif is_exit:
			# Last section — exit returns to city
			is_final_exit = true
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

		# Open/locked state — entry warp is always open (player spawned here)
		var is_spawn_edge: bool = (portal_dir == _spawn_edge)
		var is_player_entry: bool = is_spawn_edge or is_entry
		var is_open: bool = is_player_entry or not room_has_enemies
		var is_delayed: bool = is_player_entry  # Delay trigger on entry edge

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
		# Compute entry edge for the target section
		var aw_entry_edge: String = ""
		if is_exit and t_section < sections_for_warp.size():
			var target_sec: Dictionary = sections_for_warp[t_section]
			aw_entry_edge = str(target_sec.get("entry_direction", ""))
		elif is_entry and t_section >= 0 and t_section < sections_for_warp.size():
			var target_sec: Dictionary = sections_for_warp[t_section]
			aw_entry_edge = str(target_sec.get("exit_direction", ""))

		var is_final := is_final_exit
		var aw_callback := func(_body: Node3D) -> void:
			if _body.is_in_group("player"):
				if is_final:
					_fdbg("[ValleyField] AreaWarp %s → final exit, returning to city" % portal_dir)
					if SessionManager.get_session().get("type") == "quest":
						SessionManager.complete_quest()
					else:
						SessionManager.return_to_city()
					SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")
				else:
					_fdbg("[ValleyField] AreaWarp %s activated → section %d, cell %s, entry=%s" % [portal_dir, t_section, t_cell, aw_entry_edge])
					_cell_spawner._save_cell_state()
					SessionManager.save_section_state(SessionManager.get_current_section(), _cell_states, _keys_collected, _gates_opened, _visited_cells)
					var target_state: Dictionary = SessionManager.get_section_state(t_section)
					SessionManager.set_current_section(t_section)
					SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
						"current_cell_pos": t_cell,
						"spawn_edge": aw_entry_edge,
						"keys_collected": target_state.get("keys_collected", {}),
						"gates_opened": target_state.get("gates_opened", {}),
						"visited_cells": target_state.get("visited_cells", {}),
						"cell_states": target_state.get("cell_states", {}),
						"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
						"grid_minimap_visible": _grid_minimap.visible if _grid_minimap else true,
					})
		_gate_mgr._create_fallback_trigger("GateTrigger_%s" % portal_dir, aw_trigger_pos, aw_callback, is_delayed, not is_open)

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

		_fdbg("[FieldElements] AreaWarp '%s' → gate=%s trigger=%s open=%s target=s%d/%s" % [
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
					if str(act) in ["telepipe", "end_quest"]:
						has_telepipe_source = true
						break
				# Also check remaining_dialog entries for telepipe actions
				if not has_telepipe_source:
					for entry in obj.get("remaining_dialog", []):
						for act in entry.get("actions", []):
							if str(act) in ["telepipe", "end_quest"]:
								has_telepipe_source = true
								break
						if has_telepipe_source:
							break
			if has_telepipe_source:
				break
		if not has_telepipe_source:
			_needs_telepipe = true

	# Gates and Waypoints at each connection trigger (skip warp_edge)
	_fdbg("[FieldElements] spawn_edge='%s' warp_edge='%s' connections=%s" % [
		_spawn_edge, warp_edge, str(connections)])
	for dir in connections:
		if dir == warp_edge:
			_fdbg("[FieldElements]   skip %s (warp_edge)" % dir)
			continue
		if not _portal_data.has(dir):
			_fdbg("[FieldElements]   skip %s (no portal data)" % dir)
			continue
		var trigger_pos: Vector3 = _portal_data[dir]["trigger_pos"]
		var gate_pos: Vector3 = _portal_data[dir].get("gate_pos", trigger_pos)

		# Key-gate — use KeyGate element (o0c_gatet.glb) with collision from GLB gate_box
		if is_key_gate and dir in key_gate_dirs:
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
			_gate_mgr._fixup_gate_materials(kg)
			kg._setup_laser_material()
			kg._apply_state()
			_gate_mgr._fix_gate_depth(kg)
			# Only auto-open if THIS direction was previously opened by the player.
			# The compound (cell:dir) key is what bug fix per-direction tracking needs —
			# previously the per-cell flag opened all locked doors on a multi-gate hub
			# after the player unlocked any one of them.
			if _gates_opened.has("%s:%s" % [key_for_cell, str(dir)]):
				kg.open()
			# Enable the locked gate trigger when the key gate opens
			var gate_trigger_name := "GateTrigger_%s" % dir
			var cell_pos_for_gate := key_for_cell
			var gate_dir_for_minimap: String = str(dir)
			kg.state_changed.connect(func(_old: String, new_state: String) -> void:
				if new_state == "open":
					_gates_opened["%s:%s" % [cell_pos_for_gate, gate_dir_for_minimap]] = true
					var trigger := _find_child_by_name(self, gate_trigger_name) as Area3D
					if trigger:
						trigger.monitoring = true
						_fdbg("[ValleyField] KeyGate opened → trigger '%s' enabled, gate tracked" % gate_trigger_name)
					if _room_minimap:
						_room_minimap.set_gate_locked(gate_dir_for_minimap, false)
					if _grid_minimap:
						_grid_minimap.set_gate_state(cell_pos_for_gate, gate_dir_for_minimap, "open")
			)
			_fdbg("[FieldElements] ── KEY GATE DONE ──")
		else:
			# Regular gate — open if entry, visited, or room has no enemies
			var target_visited: bool = _visited_cells.has(str(connections[dir]))
			var gate_is_open: bool = (dir == _spawn_edge) or target_visited or not room_has_enemies
			var gate := GateScript.new()
			add_child(gate)
			gate.global_position = gate_pos
			gate.rotation = _portal_data[dir].get("gate_rot", Vector3.ZERO)
			_gate_mgr._fixup_gate_materials(gate)
			gate._setup_laser_material()
			if gate_is_open:
				gate.open()
			_gate_mgr._fix_gate_depth(gate)

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
		_fdbg("[Waypoint] dir=%s → target_cell=%s  state=%s" % [dir, target_cell_pos, wp_state])

	# Re-spawn the player telepipe in this room if one is active here. Per spec,
	# the player can drop a telepipe, go to the city, then walk back via the
	# city teleporter — when they arrive, the telepipe should still be standing
	# where they left it. matches_field() checks all three coords (area / section
	# / cell) so the telepipe only re-appears in the exact room it was placed in.
	var current_area_id: String = SessionManager.get_current_area_id()
	var current_cell_pos: String = str(_current_cell.get("pos", ""))
	if TelepipeManager.matches_field(current_area_id, section_idx_for_warp, current_cell_pos):
		var saved_state: Dictionary = TelepipeManager.get_state()
		var saved_pos: Vector3 = saved_state.get("world_pos", Vector3.ZERO)
		if saved_pos != Vector3.ZERO:
			_fdbg("[FieldElements] Re-spawning player telepipe at %s (came back via city teleporter)" % saved_pos)
			respawn_player_telepipe_from_state(saved_pos)


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
			_fdbg("[ValleyField] Player entered end-cell exit warp")
			_on_end_reached()

	_gate_mgr._create_fallback_trigger("EndCellExit", exit_pos, callback, true)
	_fdbg("[FieldElements] End cell exit warp at %s (dir=%s)" % [exit_pos, exit_dir])


## Spawn a telepipe (cyan cylinder placeholder). Player steps into it to complete the section / quest.
## If pos is zero, falls back to room center / default spawn.
func _spawn_telepipe(pos: Vector3 = Vector3.ZERO) -> void:
	_fdbg("[FieldElements] Spawning telepipe at %s" % pos)
	# Per spec: when a quest-completion telepipe spawns, any player-dropped
	# telepipe is closed. The quest one takes the slot conceptually — the
	# player has the boss-clear pad RIGHT THERE, no need for the older one
	# they dropped earlier in the run. The visual node in the prior cell
	# tears down naturally when that cell unloads.
	TelepipeManager.cancel("quest_completion_telepipe")
	var tp_pos := pos
	if tp_pos == Vector3.ZERO and _portal_data.has("default"):
		tp_pos = _portal_data["default"]["spawn_pos"]

	var telepipe := TelepipeScript.new()
	telepipe.name = "Telepipe"
	_map_root.add_child(telepipe)
	telepipe.position = tp_pos
	telepipe.activated.connect(func() -> void:
		_fdbg("[ValleyField] Player activated telepipe")
		_on_end_reached()
	)


## Player-dropped telepipe (consumable use, NOT the boss-clear / end-of-section
## telepipe above). Records placement in TelepipeManager so the city can spawn
## a matching pad and the field can re-spawn this telepipe on re-entry. Wires
## the activated signal to _travel_to_city_via_telepipe instead of advancing
## the section.
func spawn_player_telepipe(world_pos: Vector3) -> void:
	# Record the placement first so the cancellation signal (if a previous
	# telepipe was active) fires before we spawn the new one. The Telepipe
	# element doesn't observe TelepipeManager directly — TelepipeManager is
	# the source of truth, this is just a visual instance of it.
	var area_id: String = SessionManager.get_current_area_id()
	var section_idx: int = SessionManager.get_current_section()
	var cell_pos: String = str(_current_cell.get("pos", ""))
	TelepipeManager.place(area_id, section_idx, cell_pos, world_pos, scene_file_path)

	_spawn_player_telepipe_node(world_pos)


## Re-spawn a previously-placed player telepipe (called from _ready / cell
## load when TelepipeManager indicates one was dropped in this cell).
## Doesn't re-call TelepipeManager.place() — state is already recorded.
func respawn_player_telepipe_from_state(world_pos: Vector3) -> void:
	_spawn_player_telepipe_node(world_pos)


## Internal: build the Telepipe node and wire its activated signal to the
## "travel to city" handler. Used by both fresh placement and re-entry.
## world_pos is in global coordinates (e.g. player.global_position).
func _spawn_player_telepipe_node(world_pos: Vector3) -> void:
	_fdbg("[FieldElements] Spawning PLAYER telepipe at %s" % world_pos)
	var telepipe := TelepipeScript.new()
	telepipe.name = "PlayerTelepipe"
	_map_root.add_child(telepipe)
	# global_position so world-space input is honored regardless of any
	# transform offset on _map_root.
	telepipe.global_position = world_pos
	telepipe.activated.connect(_travel_to_city_via_telepipe)


## StartWarp interaction (the small cyan gate in the section's spawn room).
## Returns the player to the city warp room — full session end, NOT a
## telepipe-style suspend. Any active telepipe is canceled by the
## SessionManager.return_to_city() hook because the player is leaving the
## field entirely; coming back via the city teleporter starts a fresh
## session and a new spawn-room StartWarp.
func _on_start_warp_interacted(_player: Node3D) -> void:
	if _transitioning:
		return
	_transitioning = true
	_fdbg("[ValleyField] Player triggered StartWarp → return to city (suspended)")
	# Per spec, only title return / quest accept / quest end may reset
	# field state. StartWarp is a backtrack escape hatch from the spawn
	# room — it must preserve cleared rooms, opened gates, picked-up items,
	# and any active telepipe so the player can resume by walking back from
	# the warp pad. So: same suspend-session flow as the telepipe travel
	# handler (return_to_city would clear _section_cell_states + cancel the
	# telepipe via the SessionManager hook).
	_cell_spawner._save_cell_state()
	SessionManager.save_section_state(
		SessionManager.get_current_section(),
		_cell_states, _keys_collected, _gates_opened, _visited_cells
	)
	SessionManager.suspend_session()
	SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")


## Field → city via player-dropped telepipe. Saves section state so coming
## back via the city teleporter restores cleared rooms (#103 fix), suspends
## the session so resume_session() can later restore quest progress, then
## transitions to city_counter where the city-side Telepipe will spawn.
func _travel_to_city_via_telepipe() -> void:
	_fdbg("[ValleyField] Player travelling to city via telepipe")
	# CRITICAL: persist the current cell's state into _cell_states BEFORE
	# section-level save, otherwise the room the player just cleared (and is
	# standing in) gets a fresh enemy spawn on re-entry. _cell_states is only
	# updated on cell transitions; an in-place save needs an explicit flush.
	_cell_spawner._save_cell_state()
	# State preservation — the same dicts that section transitions save.
	var section_idx: int = SessionManager.get_current_section()
	_fdbg("[TelepipeDEBUG] saving section_idx=%d, current_cell.pos=%s, _cell_states keys=%s" % [
		section_idx, str(_current_cell.get("pos", "")), str(_cell_states.keys())])
	SessionManager.save_section_state(
		section_idx, _cell_states, _keys_collected, _gates_opened, _visited_cells
	)
	# Verify it round-tripped through SessionManager
	var verify: Dictionary = SessionManager.get_section_state(section_idx)
	_fdbg("[TelepipeDEBUG] post-save get_section_state keys=%s, cell_states keys=%s" % [
		str(verify.keys()),
		str(verify.get("cell_states", {}).keys())])
	# Suspend rather than return_to_city() — resume_session() restores quest
	# objectives + companions when the player comes back via the city telepipe.
	SessionManager.suspend_session()
	# city_area_base._spawn_player reads CityState.get_spawn_key(), not the
	# SceneManager transition_data dict — set the variant key on CityState so
	# city_counter's "telepipe-arrival" SPAWN_VARIANT actually fires.
	CityState.set_spawn_key("telepipe-arrival")
	# Telepipe stays active in TelepipeManager. The city scene's _ready hook
	# checks is_active() and spawns the city-side Telepipe at (0,0).
	SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")


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

	_fdbg("[Companion] Spawned '%s' behind player" % comp_id)


## Wire switch.activated → linked fences.disable()
func _wire_fence_links() -> void:
	for link_id in _fence_links:
		var link: Dictionary = _fence_links[link_id]
		var fences: Array = link["fences"]
		var switches: Array = link["switches"]
		var lid: String = link_id
		for sw in switches:
			var step_sw: StepSwitch = sw as StepSwitch
			step_sw.activated.connect(func() -> void:
				SessionManager.set_link_activated(lid)
				_fdbg("[CellObjects] Link '%s' activated" % lid)
				for fence in fences:
					(fence as Fence).disable()
			)
		if fences.size() > 0 and switches.size() > 0:
			_fdbg("[CellObjects] Wired link '%s': %d switches → %d fences" % [
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
					if _grid_minimap:
						_grid_minimap.set_gate_state(str(_current_cell.get("pos", "")), dir, "locked")
					_fdbg("[CellObjects] Gate %s locked (enemies present)" % dir)
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
			_fdbg("[CellObjects] AreaWarp locked (enemies present) [dir=%s]" % aw_dir)
			if _room_minimap:
				_room_minimap.set_gate_locked(aw_dir, true)
			if _grid_minimap:
				_grid_minimap.set_gate_state(str(_current_cell.get("pos", "")), aw_dir, "locked")


## Called when an enemy is defeated — check if all cleared.
func _check_room_clear() -> void:
	var alive_count: int = 0
	var total_count: int = _room_enemies.size()
	for enemy in _room_enemies:
		if not is_instance_valid(enemy):
			continue
		# EnemyBase uses is_alive, EnemySpawn uses element_state
		if enemy is EnemyBase:
			if enemy.is_alive:
				alive_count += 1
		elif enemy.get("element_state") != "dead":
			alive_count += 1
	_fdbg("[RoomClear] %d/%d enemies alive, %d locked gates, %d locked warps" % [
		alive_count, total_count, _room_gates_locked.size(), _warp_edge_locked.size()])
	if alive_count > 0:
		return

	# Check for next wave
	if _current_wave < _max_wave:
		_current_wave += 1
		_fdbg("[CellObjects] Wave %d cleared! Spawning wave %d" % [_current_wave - 1, _current_wave])
		_spawn_wave(_current_wave)
		return

	_fdbg("[CellObjects] Room cleared! Opening %d locked gates" % _room_gates_locked.size())
	if _room_gates_locked.size() > 0:
		SfxManager.play("res://assets/sfx/ui/door_unlocked.wav")
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
			if _grid_minimap and not dir.is_empty():
				_grid_minimap.set_gate_state(str(_current_cell.get("pos", "")), dir, "open")
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
				if _grid_minimap and not aw_dir.is_empty():
					_grid_minimap.set_gate_state(str(_current_cell.get("pos", "")), aw_dir, "open")
				_fdbg("[CellObjects] AreaWarp unlocked (room cleared) [dir=%s]" % aw_dir)
			elif node is StaticBody3D:
				node.queue_free()
			elif node is Area3D:
				node.monitoring = true
	_warp_edge_locked.clear()

	# Drop key on room clear if configured. If the quest just completed,
	# spawn a telepipe at the same drop position instead — the player has
	# no more locked doors to open, so dropping another key would be waste.
	var key_drop_target: String = str(_current_cell.get("key_drop", ""))
	var current_pos: String = str(_current_cell.get("pos", ""))
	if not key_drop_target.is_empty():
		var drop_tracking_key := current_pos + ">" + key_drop_target
		var has_objs := SessionManager.get_quest_objectives().size() > 0
		if has_objs and SessionManager.are_objectives_complete():
			_spawn_telepipe(_compute_drop_position())
		elif not _keys_collected.has(drop_tracking_key):
			_gate_mgr._drop_key_on_clear(key_drop_target, drop_tracking_key)

	# Activate locked messages on room clear (scroll animation turns on)
	for msg in _room_messages:
		if is_instance_valid(msg) and msg.element_state == "locked":
			msg.set_state("available")
			if msg._prompt_label and msg._player_nearby:
				msg._prompt_label.visible = true

	# Spawn quest_items that were deferred via spawn_condition=room_clear
	# (e.g. the body parts the hildegao "carried"). They were queued at
	# cell-enter time and only materialise once the room is clear.
	for di in _deferred_room_clear_items:
		_cell_spawner._spawn_quest_item(di["pos"], di["id"], di["label"], di["dialog"], di["actions"], di["remaining_dialog"])
	_deferred_room_clear_items.clear()

	# Fire room_clear dialog triggers
	for rc_trigger in _room_triggers:
		if is_instance_valid(rc_trigger) and rc_trigger.trigger_condition == "room_clear" and rc_trigger.element_state == "ready":
			rc_trigger.activate()

	# Spawn deferred telepipe objects (spawn_condition=room_clear)
	if not _deferred_telepipe.is_empty():
		var tp_pos: Vector3 = _deferred_telepipe.get("position", Vector3.ZERO)
		_spawn_telepipe(tp_pos)
		_deferred_telepipe = {}
		_needs_telepipe = false
	elif _needs_telepipe:
		# End cell without an authored telepipe is a quest data bug — the
		# old fallback spawned one at Vector3.ZERO which (a) is rarely on
		# the floor mesh (drops into the void) and (b) fires on room_clear
		# even if there are still quest objectives outstanding. Warn loudly
		# so this surfaces during dev playtest instead of silently
		# producing a phantom telepipe at the room origin.
		_needs_telepipe = false
		push_warning("[ValleyField] End cell %s has no authored telepipe object — add one with spawn_condition: \"quest_complete\" or \"room_clear\" so the player has an exit." % str(_current_cell.get("pos", "?")))

	# Boss room cleared — spawn a return-to-city warp at the default spawn point
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()
	if section_idx >= 0 and section_idx < sections.size():
		var cur_section: Dictionary = sections[section_idx]
		if str(cur_section.get("type", "")) == "boss":
			var ds: Dictionary = _stage_config.get("defaultSpawn", {})
			var ds_pos_arr: Array = ds.get("position", [0, 0, 0])
			var warp_pos := Vector3(float(ds_pos_arr[0]), 0, float(ds_pos_arr[2]))
			_fdbg("[CellObjects] Boss cleared! Spawning return warp at %s" % warp_pos)
			_spawn_telepipe(warp_pos)


## Spawn enemies for a specific wave number.
func _spawn_wave(wave_num: int) -> void:
	_room_enemies.clear()
	var wave_objs: Array = _wave_enemy_data.get(wave_num, [])
	for obj in wave_objs:
		var pos_arr: Array = obj.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var enemy_id: String = str(obj.get("enemy_id", "lizard"))
		_cell_spawner._spawn_enemy(pos, enemy_id)
	_fdbg("[CellObjects] Wave %d: spawned %d enemies" % [wave_num, wave_objs.size()])
	# Empty-wave guard: if this wave spawned zero enemies, no `died` signal
	# will ever fire and the wave system would silently stall here — locked
	# gates wouldn't open, key drops wouldn't spawn, the room would never
	# clear. _check_room_clear will see zero alive enemies, advance to the
	# next wave if there is one, and fall through to the room-cleared path
	# otherwise. Skip the call when there's already a pending death signal
	# (we just spawned non-zero enemies) since their `died` handler will
	# fire `_check_room_clear` for us.
	if wave_objs.is_empty():
		_check_room_clear()


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
	# Sync local state from DebugConfig (persists across field loads)
	_show_floor_collision = DebugConfig.show_floor_collision
	_show_gate_markers = DebugConfig.show_gate_dots

	# Collect GLB debug meshes by category
	_collect_debug_meshes(_map_root)
	# Build collision debug visualizations
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
	DebugConfig.show_gate_dots = _show_gate_markers
	for m in _debug_gate_meshes:
		if is_instance_valid(m):
			m.visible = _show_gate_markers
	_update_debug_label()


func _toggle_floor_collision() -> void:
	_show_floor_collision = not _show_floor_collision
	DebugConfig.show_floor_collision = _show_floor_collision
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


func _sync_debug_config() -> void:
	# Floor collision green overlay (DebugFloorViz)
	if _debug_floor_viz and _debug_floor_viz.visible != DebugConfig.show_floor_collision:
		_debug_floor_viz.visible = DebugConfig.show_floor_collision
	# Gate dot spheres (GateMark/SpawnMark/TriggerMark)
	for m in _debug_gate_spheres:
		if is_instance_valid(m) and m.visible != DebugConfig.show_gate_dots:
			m.visible = DebugConfig.show_gate_dots


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
	_cell_spawner._save_cell_state()
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": target_pos,
		"spawn_edge": spawn_edge,
		"from_cell_pos": str(_current_cell.get("pos", "")),
		"keys_collected": _keys_collected,
		"gates_opened": _gates_opened,
		"visited_cells": _visited_cells,
		"cell_states": _cell_states,
		"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
		"grid_minimap_visible": _grid_minimap.visible if _grid_minimap else true,
	})


func _on_end_reached() -> void:
	if _transitioning:
		return
	_transitioning = true
	# Save current section state before advancing
	_cell_spawner._save_cell_state()
	SessionManager.save_section_state(SessionManager.get_current_section(), _cell_states, _keys_collected, _gates_opened, _visited_cells)

	if SessionManager.advance_section():
		var sections: Array = SessionManager.get_field_sections()
		var new_idx: int = SessionManager.get_current_section()
		var new_section: Dictionary = sections[new_idx]

		# Determine entry edge from previous section's exit direction
		# or the new section's entry_direction field
		var entry_edge: String = ""
		var prev_idx: int = new_idx - 1
		if prev_idx >= 0:
			var prev_section: Dictionary = sections[prev_idx]
			var exit_dir: String = str(prev_section.get("exit_direction", ""))
			if not exit_dir.is_empty():
				entry_edge = OPPOSITE.get(exit_dir, "")
			# Also try the new section's entry_direction
			if entry_edge.is_empty():
				entry_edge = str(new_section.get("entry_direction", ""))

		var target_state: Dictionary = SessionManager.get_section_state(new_idx)
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": str(new_section.get("start_pos", "")),
			"spawn_edge": entry_edge,
			"keys_collected": target_state.get("keys_collected", {}),
			"gates_opened": target_state.get("gates_opened", {}),
			"visited_cells": target_state.get("visited_cells", {}),
			"cell_states": target_state.get("cell_states", {}),
			"map_overlay_visible": _map_overlay.visible if _map_overlay else false,
			"grid_minimap_visible": _grid_minimap.visible if _grid_minimap else true,
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
	# Pause/Start handled by PsoStartMenu autoload
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				if _grid_minimap:
					_grid_minimap.visible = not _grid_minimap.visible
					_grid_minimap.set_meta("toggled_off", not _grid_minimap.visible)
				get_viewport().set_input_as_handled()
			KEY_QUOTELEFT:
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
			KEY_G:
				_gate_nudge_mode = not _gate_nudge_mode
				if orbit_camera:
					orbit_camera.input_enabled = not _gate_nudge_mode
				_fdbg("[GateNudge] Mode %s" % ("ON — arrows to nudge, G to exit" if _gate_nudge_mode else "OFF"))
				get_viewport().set_input_as_handled()

	# Gate nudge mode: arrow keys move nearest gate
	if _gate_nudge_mode and event is InputEventKey and event.pressed:
		var nudge := Vector3.ZERO
		var step := 0.25
		match event.keycode:
			KEY_UP:
				nudge = Vector3(0, 0, -step)
			KEY_DOWN:
				nudge = Vector3(0, 0, step)
			KEY_LEFT:
				nudge = Vector3(-step, 0, 0)
			KEY_RIGHT:
				nudge = Vector3(step, 0, 0)
			KEY_PAGEUP:
				nudge = Vector3(0, step, 0)
			KEY_PAGEDOWN:
				nudge = Vector3(0, -step, 0)
		if nudge.length() > 0:
			_nudge_nearest_gate(nudge)
			get_viewport().set_input_as_handled()


func _nudge_nearest_gate(nudge: Vector3) -> void:
	var player_pos: Vector3 = player.global_position if player else Vector3.ZERO
	var nearest: Node3D = null
	var nearest_dist := 999.0

	# Find all gates and key gates — they're children of self (the field controller)
	for child in get_children():
		if child is Gate or child is KeyGate:
			var dist: float = child.global_position.distance_to(player_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = child

	if nearest == null:
		_fdbg("[GateNudge] No gates found in current room")
		return

	nearest.global_position += nudge

	# Find which direction/portal this gate belongs to
	var gate_dir := ""
	var portal_id := ""
	for dir in _portal_data:
		if dir == "default":
			continue
		var gp: Vector3 = _portal_data[dir].get("gate_pos", Vector3.INF)
		# Use a generous distance since we're nudging it away from the original
		if nearest.global_position.distance_to(gp) < 10.0:
			gate_dir = dir
			var portals: Dictionary = _current_cell.get("portals", {})
			portal_id = str(portals.get(dir, ""))
			break

	var cell_pos: String = str(_current_cell.get("pos", ""))
	var stage_id: String = str(_current_cell.get("stage_id", ""))
	var gp := nearest.global_position
	_fdbg("[GateNudge] dir=%s cell=%s stage=%s portal=%s → gate_pos=[%.2f, %.2f, %.2f]" % [
		gate_dir, cell_pos, stage_id, portal_id, gp.x, gp.y, gp.z])
