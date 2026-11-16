extends "res://scripts/3d/city/city_area_base.gd"
## Principal's office — quest client NPC.
## Handles intro cutscene for new characters, quest briefing, and quest reporting.

const OfficeLibraryRoom := preload("res://scripts/3d/city/office_library_room.gd")

# -- Configurable NPC positions --
# Update these if the office geometry changes.
# Principal always stands at PRINCIPAL_POSITION.
# pos_1 and pos_2 are for quest client NPCs.
# Rear library landing and Principal share the procedural room's floor height.
# Entry and quest clients remain on the lower floor. Stairs connect both levels.
const PRINCIPAL_POSITION := { "position": Vector3(0.000, OfficeLibraryRoom.LANDING_H, -5.600), "rotation": 0.000 }
const NPC_POSITIONS := {
	"pos_1": { "position": Vector3(-2.800, 0.000, -2.400), "rotation": 0.000 },
	"pos_2": { "position": Vector3(-3.900, 0.000, -1.500), "rotation": -0.401 },
}

const NPC_SCALE := 0.090

const DOOR_TRIGGER_POSITION := Vector3(0.000, 1.000, 6.500)
const DOOR_TRIGGER_SIZE := Vector3(8.100, 2.000, 1.200)

# Spawn just inside the entrance, facing the Principal / sun window (-Z).
const DEFAULT_SPAWN := Vector3(0.000, 0.000, 4.400)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"counter-office": {
		"position": Vector3(0.000, 0.000, 4.400),
		"rotation": PI,
	},
	"intro": {
		"position": Vector3(0.000, 0.000, 1.500),
		"rotation": PI,
	},
}

const INTRO_DIALOG := [
	{"speaker": "Principal", "text": "Ah, a new recruit. Welcome to the Hunters Guild."},
	{"speaker": "Principal", "text": "Your job is simple — take missions, don't die."},
	{"speaker": "Principal", "text": "The guild counter is down the hall. Talk to them when you're ready."},
]

## NPC models for quest client NPCs (npc_id → {glb, texture} paths)
const CLIENT_MODELS := {
	"kai": {"glb": "res://assets/npcs/kai/pc_a01_000.glb", "texture": "res://assets/npcs/kai/pc_a01_000.png", "idle": "pmsa_wait"},
	"sarisa": {"glb": "res://assets/npcs/sarisa/pc_a00_000.glb", "texture": "res://assets/npcs/sarisa/pc_a00_000.png", "idle": "pwsa_wait"},
	"dorn": {"glb": "res://assets/npcs/dorn/dorn.glb", "texture": "res://assets/npcs/dorn/dorn.png", "idle": "pmsa_wait"},
	"dr_carlo": {"glb": "res://assets/npcs/dr_carlo/dr_carlo.glb", "texture": "res://assets/npcs/dr_carlo/dr_carlo.png", "idle": "pmsa_wait"},
	"elio": {"glb": "res://assets/npcs/elio/elio.glb", "texture": "res://assets/npcs/elio/elio.png", "idle": "pwsa_wait"},
	"fern": {"glb": "res://assets/npcs/fern/fern.glb", "texture": "res://assets/npcs/fern/fern.png", "idle": "pwsa_wait"},
	"vash": {"glb": "res://assets/npcs/vash/vash.glb", "texture": "res://assets/npcs/vash/vash.png", "idle": "pmsa_wait"},
	"ren": {"glb": "res://assets/npcs/ren/ren.glb", "texture": "res://assets/npcs/ren/ren.png", "idle": "pmsa_wait"},
	"mira": {"glb": "res://assets/npcs/mira/mira.glb", "texture": "res://assets/npcs/mira/mira.png", "idle": "pwsa_wait"},
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

# Speech bubble state (shared SpeechBubble, #557)
var _speaker_anchors: Dictionary = {}  # speaker name → Node3D
var _briefing_bubble: SpeechBubble = null
var _hidden_speaker_label: Label3D = null
var _briefing_active := false
var _briefing_pages: Array = []
var _briefing_index: int = 0


func _ready() -> void:
	# Build the procedural library room (#356) — replaces the old in-house office
	# GLB. Geometry + textures + warm/cool lighting mirror the approved R3F set.
	OfficeLibraryRoom.build(self)

	# Capture spawn key before _spawn_player consumes it
	var spawn_key := CityState.get_spawn_key()
	_is_intro = spawn_key == "intro"
	# Briefing triggers when the player has an accepted quest (walks in from counter)
	# Only play once — check the briefing_shown flag so re-entering the office skips it
	_is_briefing = not _is_intro and SessionManager.has_accepted_quest() \
		and not SessionManager.get_accepted_quest().get("briefing_shown", false)

	# Spawn player — at origin for briefings so cutscene starts immediately
	if _is_briefing:
		_spawn_player(Vector3.ZERO, DEFAULT_ROT, {})
	else:
		_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — covers the R=9 round hall plus the +Z door threshold.
	_add_floor_collision(Vector3(0, 0, 0), Vector3(24, 0.2, 24))

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
		_setup_briefing()


func _unhandled_input(event: InputEvent) -> void:
	if _briefing_active:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_advance_briefing()
			return
	# Fall through to base class for ESC handling
	super._unhandled_input(event)


func _start_intro() -> void:
	player.transition_to(player.PlayerState.CUTSCENE)
	# Small delay so the scene finishes setting up visually
	await get_tree().create_timer(0.3).timeout
	_show_dialog(INTRO_DIALOG, _on_intro_complete)


func _on_intro_complete() -> void:
	player.transition_to(player.PlayerState.IDLE)


# ── Briefing Setup ──────────────────────────────────────────────────────────

func _setup_briefing() -> void:
	# Load quest data
	var accepted: Dictionary = SessionManager.get_accepted_quest()
	var quest_id: String = str(accepted.get("quest_id", ""))
	if quest_id.is_empty():
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
			var model_data: Dictionary = CLIENT_MODELS[npc_id]
			var idle_name: String = str(model_data.get("idle", ""))
			var npc := _add_npc(
				"Briefing_%s" % npc_id, spawn_pos, spawn_rot,
				model_data["glb"], npc_name, "", idle_name
			)
			_briefing_npcs.append(npc)
		else:
			var capsule_npc := _spawn_capsule_npc(npc_id, npc_name, spawn_pos, spawn_rot)
			_briefing_npcs.append(capsule_npc)

	# Bind live Node3D anchors for Principal + quest-client NPCs (#557;
	# spec /states/speech-bubbles + /journey/city/office).
	_speaker_anchors.clear()
	_speaker_anchors["Principal"] = _principal_npc
	for i in office_npcs.size():
		if i < _briefing_npcs.size():
			var npc_name: String = str(office_npcs[i].get("npc_name", ""))
			if not npc_name.is_empty():
				_speaker_anchors[npc_name] = _briefing_npcs[i]

	_briefing_bubble = SpeechBubble.new()
	add_child(_briefing_bubble)
	_briefing_bubble.finished.connect(_on_bubble_page_finished)

	# Store briefing dialog pages and start immediately
	_briefing_pages = quest.get("briefing_dialog", [])
	if not _briefing_pages.is_empty():
		# Small delay so the scene finishes setting up visually
		await get_tree().create_timer(0.3).timeout
		_play_briefing_dialog()


# ── Briefing Playback ───────────────────────────────────────────────────────

func _play_briefing_dialog() -> void:
	if _briefing_pages.is_empty():
		return
	player.transition_to(player.PlayerState.CUTSCENE)
	_briefing_active = true
	_briefing_index = 0
	_play_bubble_page()


func _play_bubble_page() -> void:
	if _briefing_index >= _briefing_pages.size():
		_on_briefing_complete()
		return

	_restore_speaker_label()

	var page: Dictionary = _briefing_pages[_briefing_index]
	var speaker: String = str(page.get("speaker", ""))
	var text: String = str(page.get("text", ""))
	var duration := maxf(3.0, text.length() / 20.0)
	var anchor_node: Node3D = _speaker_anchors.get(speaker, _principal_npc) as Node3D

	if anchor_node != null:
		var name_lbl := anchor_node.get_node_or_null("NameLabel") as Label3D
		if name_lbl != null and name_lbl.visible:
			name_lbl.visible = false
			_hidden_speaker_label = name_lbl
		_briefing_bubble.present(anchor_node, text, duration, speaker)
	else:
		SfxManager.play("res://assets/sfx/ui/dialog_open.wav")


func _on_bubble_page_finished() -> void:
	if _briefing_active:
		_advance_briefing()


func _advance_briefing() -> void:
	if not _briefing_active:
		return
	_briefing_index += 1
	_play_bubble_page()


func _on_briefing_complete() -> void:
	_briefing_active = false
	_restore_speaker_label()
	if _briefing_bubble:
		_briefing_bubble.dismiss()

	# Mark briefing as shown so it doesn't replay on re-entry
	var aq := SessionManager.get_accepted_quest()
	if not aq.is_empty():
		aq["briefing_shown"] = true

	player.transition_to(player.PlayerState.IDLE)


func _restore_speaker_label() -> void:
	if _hidden_speaker_label != null and is_instance_valid(_hidden_speaker_label):
		_hidden_speaker_label.visible = true
	_hidden_speaker_label = null


func _find_field_hud() -> Node:
	for child in get_children():
		if child is CanvasLayer and child.name == "FieldHud":
			return child
	return null


# ── Capsule NPC (unchanged) ─────────────────────────────────────────────────

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
	label.name = "NameLabel"
	label.text = npc_name
	label.position.y = 1.8
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	add_child(root)
	return root


# ── Principal Interaction & Reporting ────────────────────────────────────────

func _on_principal_interact(_player: Node3D) -> void:
	# Quest turn-in happens at the GUILD COUNTER only (#354) — the Principal
	# handles story dialog (intro / briefing), never completion. When a quest
	# is awaiting report, point the player at the counter instead of reporting
	# here. (The autopilot asserts has_completed_quest() stays true through
	# this interaction — if the Principal ever completes a quest again, the
	# regression matrix catches it.)
	if SessionManager.has_completed_quest():
		_show_dialog([
			{"speaker": "Principal", "text": "Good work out there, hunter."},
			{"speaker": "Principal", "text": "Report your mission at the guild counter to make it official."},
		], func() -> void:
			player.transition_to(player.PlayerState.IDLE)
		)
		player.transition_to(player.PlayerState.CUTSCENE)
		return

	# Default: give debug meseta. The prior `else` path pushed the guild
	# counter when `_session` was non-empty, but reaching the office with an
	# active session is an abnormal state — the player can't sensibly browse
	# quests mid-run. Fall through to the meseta grant so the debug path is
	# reachable regardless.
	var character = CharacterManager.get_active_character()
	if character:
		character["meseta"] = int(character.get("meseta", 0)) + 10000
		GameState.meseta = int(character["meseta"])
	_show_dialog([
		{"speaker": "Principal", "text": "Short on funds? Here's 10,000 meseta. Don't spend it all in one place."},
	], func() -> void:
		player.transition_to(player.PlayerState.IDLE)
	)
	player.transition_to(player.PlayerState.CUTSCENE)


func _show_dialog(pages: Array, on_complete: Callable) -> void:
	var field_hud: CanvasLayer = _find_field_hud()

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
