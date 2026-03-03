extends "res://scripts/3d/city/city_area_base.gd"
## Principal's office — quest client NPC.
## Handles intro cutscene for new characters, quest briefing, and quest reporting.

# -- Configurable NPC positions --
# Update these if the office geometry changes.
# Principal always stands at PRINCIPAL_POSITION.
# pos_1 and pos_2 are for quest client NPCs.
const PRINCIPAL_POSITION := { "position": Vector3(0.000, 0.000, -6.100), "rotation": 0.000 }
const NPC_POSITIONS := {
	"pos_1": { "position": Vector3(-2.800, 0.000, -2.400), "rotation": 0.000 },
	"pos_2": { "position": Vector3(-3.900, 0.000, -1.500), "rotation": -0.401 },
}

const NPC_SCALE := 0.090
const ROOM_SCALE := 0.160

const DOOR_TRIGGER_POSITION := Vector3(0.000, 1.000, 10.900)
const DOOR_TRIGGER_SIZE := Vector3(8.100, 2.000, 1.200)

const DEFAULT_SPAWN := Vector3(0.000, 0.000, 8.700)
const DEFAULT_ROT := 3.142

const SPAWN_VARIANTS := {
	"counter-office": {
		"position": Vector3(0.000, 0.000, 8.700),
		"rotation": 3.142,
	},
	"intro": {
		"position": Vector3(0.000, 0.000, -2.000),
		"rotation": 3.142,
	},
	"quest-briefing": {
		"position": Vector3(0.000, 0.000, -2.000),
		"rotation": 3.142,
	},
}

const INTRO_DIALOG := [
	{"speaker": "Principal", "text": "Ah, a new recruit. Welcome to the Hunters Guild."},
	{"speaker": "Principal", "text": "Your job is simple — take missions, don't die."},
	{"speaker": "Principal", "text": "The guild counter is down the hall. Talk to them when you're ready."},
]

## NPC models for quest client NPCs (npc_id → GLB path)
const CLIENT_MODELS := {
	"kai": "res://assets/npcs/kai/pc_a01_000.glb",
	"sarisa": "res://assets/npcs/sarisa/pc_a00_000.glb",
}

## Companion capsule colors (for NPCs without GLB models)
const CAPSULE_COLORS := {
	"kai": Color(1.0, 0.9, 0.1),
	"dorn": Color(1.0, 0.6, 0.0),
	"ren": Color(0.0, 0.9, 0.9),
	"elio": Color(0.2, 0.9, 0.2),
	"mira": Color(0.7, 0.3, 0.9),
	"sarisa": Color(1.0, 0.5, 0.7),
	"fern": Color(0.6, 0.8, 0.3),
	"dr_carlo": Color(0.4, 0.6, 0.9),
}

var _is_intro := false
var _is_briefing := false
var _principal_npc: CityNPC
var _briefing_npcs: Array[Node3D] = []


func _ready() -> void:
	# Capture spawn key before _spawn_player consumes it
	var spawn_key := CityState.get_spawn_key()
	_is_intro = spawn_key == "intro"
	_is_briefing = spawn_key == "quest-briefing"

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision
	_add_floor_collision(Vector3(0, 0, 0), Vector3(20, 0.2, 30))

	# Principal NPC at fixed position
	_principal_npc = _add_npc(
		"PrincipalNPC", PRINCIPAL_POSITION["position"], PRINCIPAL_POSITION["rotation"],
		"res://assets/npcs/principal/principal.glb",
		"Principal",
		""  # Empty target — we handle interaction ourselves
	)
	_principal_npc.scale = Vector3(NPC_SCALE, NPC_SCALE, NPC_SCALE)

	# Connect custom interaction handler via signal
	_principal_npc.interacted.connect(_on_principal_interact)

	# Exit trigger — back to counter
	_add_area_trigger(
		DOOR_TRIGGER_POSITION, DOOR_TRIGGER_SIZE,
		"res://scenes/3d/city/city_counter.tscn", "office-exit"
	)

	# Wire up
	_connect_player_to_interactables()

	# Start intro cutscene if applicable
	if _is_intro:
		_start_intro()
	elif _is_briefing:
		_start_briefing()


func _start_intro() -> void:
	player.transition_to(player.PlayerState.CUTSCENE)
	# Small delay so the scene finishes setting up visually
	await get_tree().create_timer(0.3).timeout
	_show_dialog(INTRO_DIALOG, _on_intro_complete)


func _on_intro_complete() -> void:
	player.transition_to(player.PlayerState.IDLE)


func _start_briefing() -> void:
	player.transition_to(player.PlayerState.CUTSCENE)

	# Load quest data
	var accepted: Dictionary = SessionManager.get_accepted_quest()
	var quest_id: String = str(accepted.get("quest_id", ""))
	if quest_id.is_empty():
		player.transition_to(player.PlayerState.IDLE)
		return

	var quest: Dictionary = QuestLoader.load_quest(quest_id)

	# Spawn office NPCs at assigned positions
	var office_npcs: Array = quest.get("office_npcs", [])
	for npc_data in office_npcs:
		var npc_id: String = str(npc_data.get("npc_id", ""))
		var npc_name: String = str(npc_data.get("npc_name", ""))
		var office_pos: String = str(npc_data.get("office_position", ""))

		if npc_id.is_empty() or office_pos.is_empty():
			continue
		if not NPC_POSITIONS.has(office_pos):
			continue

		var slot: Dictionary = NPC_POSITIONS[office_pos]
		var spawn_pos: Vector3 = slot["position"]
		var spawn_rot: float = slot["rotation"]

		if CLIENT_MODELS.has(npc_id):
			var npc := _add_npc(
				"Briefing_%s" % npc_id, spawn_pos, spawn_rot,
				CLIENT_MODELS[npc_id], npc_name, ""
			)
			_briefing_npcs.append(npc)
		else:
			var capsule_npc := _spawn_capsule_npc(npc_id, npc_name, spawn_pos, spawn_rot)
			_briefing_npcs.append(capsule_npc)

	# Small delay so visuals settle
	await get_tree().create_timer(0.3).timeout

	# Play briefing dialog
	var briefing_dialog: Array = quest.get("briefing_dialog", [])
	if briefing_dialog.is_empty():
		_on_briefing_complete()
		return

	_show_dialog(briefing_dialog, _on_briefing_complete)


func _on_briefing_complete() -> void:
	# Briefing NPCs stay visible until the player leaves the office
	player.transition_to(player.PlayerState.IDLE)


func _spawn_capsule_npc(npc_id: String, npc_name: String, pos: Vector3, rot: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Briefing_%s" % npc_id
	root.position = pos
	root.rotation.y = rot

	# Capsule mesh
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = CAPSULE_COLORS.get(npc_id, Color(1.0, 1.0, 1.0))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)

	# Name label
	var label := Label3D.new()
	label.text = npc_name
	label.position.y = 1.8
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	add_child(root)
	return root


func _on_principal_interact(_player: Node3D) -> void:
	if SessionManager.has_completed_quest():
		_report_quest()
	else:
		# Default: open guild counter
		_save_player_state()
		SceneManager.push_scene("res://scenes/2d/guild_counter.tscn")


func _report_quest() -> void:
	player.transition_to(player.PlayerState.CUTSCENE)
	var data: Dictionary = SessionManager.report_quest()
	if data.is_empty():
		player.transition_to(player.PlayerState.IDLE)
		return

	var quest_id: String = str(data.get("quest_id", ""))
	if not quest_id.is_empty():
		GameState.complete_mission(quest_id)

	var exp_val: int = int(data.get("total_exp", 0))
	var meseta_val: int = int(data.get("total_meseta", 0))
	var report_dialog := [
		{"speaker": "Principal", "text": "Mission complete. Well done, hunter."},
		{"speaker": "Principal", "text": "Your reward: %d EXP, %d meseta." % [exp_val, meseta_val]},
	]

	_show_dialog(report_dialog, _on_report_complete)


func _on_report_complete() -> void:
	SaveManager.auto_save()
	player.transition_to(player.PlayerState.IDLE)


func _show_dialog(pages: Array, on_complete: Callable) -> void:
	var field_hud: CanvasLayer = null
	for child in get_children():
		if child is CanvasLayer:
			field_hud = child
			break

	if not field_hud:
		push_warning("[Office] No CanvasLayer found for dialog")
		on_complete.call()
		return

	var dialog := DialogBox.new()
	field_hud.add_child(dialog)
	dialog.dialog_complete.connect(func() -> void:
		dialog.queue_free()
		on_complete.call()
	)
	dialog.show_dialog(pages)


func _get_area_name() -> String:
	return "office"
