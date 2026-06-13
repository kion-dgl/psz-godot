extends "res://scripts/3d/city/city_area_base.gd"
## Principal's office — quest client NPC.
## Handles intro cutscene for new characters, quest briefing, and quest reporting.

# -- Configurable NPC positions --
# Update these if the office geometry changes.
# Principal always stands at PRINCIPAL_POSITION.
# pos_1 and pos_2 are for quest client NPCs.
# Coords match the v0.28 in-house GLB at scale 1.0:
#   round chamber centered at origin (radius 16),
#   platform top at y=0.4, principal stands behind desk at chair (z≈-9.7),
#   hallway extends out the front along Godot +Z to z ≈ +28.
const PRINCIPAL_POSITION := { "position": Vector3(0.000, 0.400, -9.700), "rotation": 0.000 }
const NPC_POSITIONS := {
	"pos_1": { "position": Vector3(-3.000, 0.000, -3.000), "rotation": 0.000 },
	"pos_2": { "position": Vector3(-4.000, 0.000, -2.000), "rotation": -0.401 },
}

const NPC_SCALE := 0.090

const DOOR_TRIGGER_POSITION := Vector3(0.000, 1.000, 27.000)
const DOOR_TRIGGER_SIZE := Vector3(7.000, 2.500, 1.500)

# Spawn inside the round chamber so the room is visible immediately
# (spawning in the hallway puts the chamber wall in front of the camera).
const DEFAULT_SPAWN := Vector3(0.000, 0.000, 8.000)
const DEFAULT_ROT := 3.142

const SPAWN_VARIANTS := {
	"counter-office": {
		"position": Vector3(0.000, 0.000, 8.000),
		"rotation": 3.142,
	},
	"intro": {
		"position": Vector3(0.000, 0.000, -3.000),
		"rotation": 3.142,
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

## Speech bubble viewport size (matches companion_npc.gd)
const BUBBLE_WIDTH := 400
const BUBBLE_HEIGHT := 180

## Bubble height for capsule NPCs (1.4 tall + label space)
const CAPSULE_BUBBLE_HEIGHT := 2.2

var _is_intro := false
var _is_briefing := false
var _principal_npc: CityNPC
var _briefing_npcs: Array[Node3D] = []

# Speech bubble state
var _npc_bubbles: Dictionary = {}  # speaker name → {viewport, sprite, label}
var _briefing_active := false
var _briefing_pages: Array = []
var _briefing_index: int = 0
var _bubble_timer: float = 0.0
var _active_bubble_sprite: Sprite3D = null


func _ready() -> void:
	# Apply texture fixes from global config
	_fix_city_materials()
	_add_interior_lights([Vector3(0, 6, 0), Vector3(0, 6, 18)])

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

	# Floor collision (covers round chamber + hallway)
	_add_floor_collision(Vector3(0, 0, 6), Vector3(40, 0.2, 60))

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


func _process(delta: float) -> void:
	if not _briefing_active or _bubble_timer <= 0:
		return
	_bubble_timer -= delta
	# Fade out during last 0.5s
	if _active_bubble_sprite and _bubble_timer < 0.5:
		_active_bubble_sprite.modulate.a = _bubble_timer / 0.5
	if _bubble_timer <= 0:
		_advance_briefing()


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

	# Build speech bubbles for Principal + office NPCs
	# Principal bubble sits ~1.4m above the feet, regardless of how high
	# the platform raises them — keep it relative so geometry tweaks don't
	# desync the bubble.
	var principal_pos := PRINCIPAL_POSITION["position"]
	_build_npc_bubble(Vector3(principal_pos.x, principal_pos.y + 1.4, principal_pos.z), "Principal")
	for i in office_npcs.size():
		if i < _briefing_npcs.size():
			var npc_name: String = str(office_npcs[i].get("npc_name", ""))
			if not npc_name.is_empty():
				var npc_node: Node3D = _briefing_npcs[i]
				_build_npc_bubble(
					Vector3(npc_node.position.x, CAPSULE_BUBBLE_HEIGHT, npc_node.position.z),
					npc_name
				)

	# Store briefing dialog pages and start immediately
	_briefing_pages = quest.get("briefing_dialog", [])
	if not _briefing_pages.is_empty():
		# Small delay so the scene finishes setting up visually
		await get_tree().create_timer(0.3).timeout
		_play_briefing_dialog()


# ── Speech Bubble Construction ──────────────────────────────────────────────

func _build_npc_bubble(world_pos: Vector3, speaker_name: String) -> void:
	# SubViewport renders 2D speech bubble → Sprite3D displays in 3D
	# Parented to scene root (not NPC) to avoid scale issues with scaled models
	var viewport := SubViewport.new()
	viewport.name = "Bubble_%s" % speaker_name
	viewport.size = Vector2i(BUBBLE_WIDTH, BUBBLE_HEIGHT)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	# Root control
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)

	var cx: float = BUBBLE_WIDTH * 0.5
	var top_y: float = BUBBLE_HEIGHT * 0.78

	# Tail border (behind everything)
	var tail_border := Polygon2D.new()
	tail_border.polygon = PackedVector2Array([
		Vector2(cx - 13, top_y - 1),
		Vector2(cx + 13, top_y - 1),
		Vector2(cx, top_y + 30),
	])
	tail_border.color = Color(0.3, 0.3, 0.3, 0.6)
	root.add_child(tail_border)

	# White rounded rectangle (the bubble body)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.05
	panel.anchor_right = 0.95
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.78
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 4
	panel.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.border_color = Color(0.3, 0.3, 0.3, 0.6)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	# Text label inside panel
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	label.add_theme_font_size_override("font_size", 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	# White tail triangle
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(cx - 12, top_y),
		Vector2(cx + 12, top_y),
		Vector2(cx, top_y + 28),
	])
	tail.color = Color.WHITE
	root.add_child(tail)

	# Sprite3D billboard at fixed world position (avoids NPC scale issues)
	var sprite := Sprite3D.new()
	sprite.name = "BubbleSprite_%s" % speaker_name
	sprite.pixel_size = 0.006
	sprite.position = world_pos
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.render_priority = 10
	sprite.visible = false
	add_child(sprite)

	# Assign viewport texture after one frame
	_assign_bubble_texture.call_deferred(viewport, sprite)

	_npc_bubbles[speaker_name] = {"viewport": viewport, "sprite": sprite, "label": label}


func _assign_bubble_texture(viewport: SubViewport, sprite: Sprite3D) -> void:
	if viewport and sprite:
		sprite.texture = viewport.get_texture()


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

	# Hide previous bubble
	if _active_bubble_sprite:
		_active_bubble_sprite.visible = false

	var page: Dictionary = _briefing_pages[_briefing_index]
	var speaker: String = str(page.get("speaker", ""))
	var text: String = str(page.get("text", ""))

	# Show speech bubble for this speaker
	SfxManager.play("res://assets/sfx/ui/dialog_open.wav")
	if _npc_bubbles.has(speaker):
		var bubble: Dictionary = _npc_bubbles[speaker]
		var label: Label = bubble["label"]
		var sprite: Sprite3D = bubble["sprite"]
		label.text = text
		sprite.visible = true
		sprite.modulate.a = 1.0
		_active_bubble_sprite = sprite
	else:
		_active_bubble_sprite = null

	# Auto-advance duration based on text length
	_bubble_timer = maxf(3.0, text.length() / 20.0)

	# Log to action log
	_log_briefing_speech(speaker, text)


func _advance_briefing() -> void:
	if not _briefing_active:
		return
	_briefing_index += 1
	_bubble_timer = 0.0
	_play_bubble_page()


func _on_briefing_complete() -> void:
	_briefing_active = false
	_bubble_timer = 0.0
	if _active_bubble_sprite:
		_active_bubble_sprite.visible = false
		_active_bubble_sprite = null

	# Mark briefing as shown so it doesn't replay on re-entry
	var aq := SessionManager.get_accepted_quest()
	if not aq.is_empty():
		aq["briefing_shown"] = true

	# Log "Quest accepted!" to action log
	var field_hud := _find_field_hud()
	if field_hud:
		field_hud.log_entry("Quest accepted!", Color(0.4, 0.8, 1.0))

	player.transition_to(player.PlayerState.IDLE)


func _log_briefing_speech(speaker: String, text: String) -> void:
	var field_hud := _find_field_hud()
	if field_hud:
		field_hud.log_speech(speaker, text)


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
