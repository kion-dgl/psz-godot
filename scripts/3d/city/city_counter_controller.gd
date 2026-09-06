extends "res://scripts/3d/city/city_area_base.gd"
## Counter area controller — storage and quest counter NPCs.

const BUBBLE_WIDTH := 400
const BUBBLE_HEIGHT := 180
## Head-height offset above the NPC origin (feet) for the speech bubble anchor.
const BUBBLE_OFFSET := Vector3(0, 2.5, 0)

const TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")
const TeleporterDressingScript := preload("res://scripts/3d/elements/teleporter_dressing.gd")

# Positions probed on the merged mesh (floor at y≈-10.67). Spawns sit a touch
# above the floor so the player settles onto it. Rotations are provisional
# (the mock didn't capture facing) — tune in-game.
const DEFAULT_SPAWN := Vector3(-0.05, -9.0, 121.78)
const DEFAULT_ROT := PI

# City-side telepipe spawns at the player's arrival spot (spec: same place the
# player lands). The telepipe-arrival variant drops a step east of it.
const TELEPIPE_CITY_POS := Vector3(-0.05, -10.67, 121.78)

const SPAWN_VARIANTS := {
	"market-exit": {
		"position": Vector3(-0.06, -9.0, 137.68),
		"rotation": PI,
	},
	"warp-exit": {
		"position": Vector3(0.05, -4.0, 64.0),
		"rotation": 0.0,
	},
	"office-exit": {
		"position": Vector3(10.59, -9.0, 111.17),
		"rotation": -PI / 2.0,
	},
	"telepipe-arrival": {
		"position": Vector3(1.95, -9.0, 121.78),
		"rotation": -PI / 2.0,
	},
}


func _ready() -> void:
	# Apply texture fixes from global config
	_fix_city_materials()
	# Override: disable vertex colors for SA2 — they're baked too dark
	_override_vertex_colors(false)
	# Interior lights along the hallway (Z runs from ~20 to ~-22, y=2 is floor)
	_add_interior_lights([
		Vector3(0, 4, 18),
		Vector3(0, 4, 12),
		Vector3(0, 4, 6),
		Vector3(0, 4, 0),
		Vector3(0, 4, -6),
		Vector3(0, 4, -12),
		Vector3(0, 4, -18),
	])

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)
	# This mesh is authored low (floor ≈ -10.67), below the player's default
	# -10.0 fall-respawn — drop the threshold so the floor isn't read as a fall.
	if player:
		player.fall_respawn_y = -25.0

	# Camera
	_setup_camera(player)

	# Floor collision — trimesh from the hand-authored s00e_sa2-floor.glb (the
	# walkable surface incl. the kaidan slope, selected in the floor-collider
	# tool). The tool bakes the GLB node transforms, so the collider is already
	# in the model's natural frame and overlaps the visual mesh at identity — no
	# offset.
	_add_trimesh_floor(
		"res://assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2-floor.glb",
		Vector3.ZERO
	)

	# NPCs, exit triggers, and the warp pad — positions probed on the merged mesh.
	_add_interactables()

	# City-side telepipe — spawns if a player-dropped telepipe is active in
	# TelepipeManager. Interaction (E) consumes it: returns the player to the
	# field cell where it was dropped, and the telepipe disappears in both
	# city and field (one-shot return per spec).
	_maybe_spawn_city_telepipe()
	# Clear the city visual if the telepipe is canceled while we're here
	# (quest accept / abandon / report all cancel it) — #358. Without this the
	# state clears but the orphaned pad lingers. Autoload→scene connections
	# auto-drop when this node frees, so no manual disconnect is needed.
	TelepipeManager.canceled.connect(_on_telepipe_canceled)

	# Wire up
	_connect_player_to_interactables()


## NPCs (behind the counter — interaction boxes sized to reach across the counter
## from the floor without overlapping each other, so storage/guild switch
## cleanly), the market/office exit triggers, and the warp teleporter pad on the
## raised kaidan plaza.
func _add_interactables() -> void:
	# Nudged ~1.1u forward along their facing (just behind the counter front).
	_add_npc(
		"StorageNPC", Vector3(-10.53, -10.67, 114.15), 0.94,
		"res://assets/npcs/np_000_00_0/np_000_00_0.glb",
		"Storage",
		"res://scenes/2d/storage.tscn",
		"pso_f_sa_stand", "", "", Vector3(3.6, 3, 3.6)
	)
	_add_npc(
		"QuestCounterNPC", Vector3(-7.86, -10.67, 111.39), 0.64,
		"res://assets/npcs/np_001_00_0/np_001_00_0.glb",
		"Guild Counter",
		"res://scenes/2d/guild_counter.tscn",
		"pso_f_sa_stand", "", "", Vector3(3.6, 3, 3.6)
	)
	# Coliseum Master (kion): debug enemy lab beside the guild counter — pick any
	# roster enemy and warp alone with it into the s00a_nr2 coliseum for 1:1 combat
	# testing (the in-game counterpart of #/enemy-room). Model np_009 from the
	# special_c2 city set (pack-shipped like the other np_* townsfolk).
	_add_npc(
		# Kion playtest position: west side of the south entrance (the y from the
		# blocked debug read snaps to the shared counter floor; the rot mirrors
		# the original pick to face into the room, same compass as the guild
		# NPC). Clear of the guild stand-point, the telepipe-arrival pad, and
		# every exit trigger.
		"ColiseumMasterNPC", Vector3(-9.0, -10.67, 121.28), 0.60,
		"res://assets/npcs/np_009_00_0/np_009_00_0.glb",
		"Coliseum Master",
		"res://scenes/2d/shops/coliseum_pick.tscn",
		"pso_ro_stand", "", "pso_f_emote_bow", Vector3(2.8, 3, 2.8)
	)
	# Exit triggers — floor at y≈-10.67, box centered ~1.5 above it. The old
	# counter→warp trigger is gone; the teleporter lives in this scene now.
	_add_area_trigger(
		Vector3(-0.06, -9.17, 140.65), Vector3(4, 3, 1),
		"res://scenes/3d/city/city_market.tscn", "counter-exit"
	)
	_add_area_trigger(
		Vector3(14.30, -9.17, 107.47), Vector3(2, 3, 2),
		"res://scenes/3d/city/city_office.tscn", "counter-office"
	)
	# Warp teleporter — empty area_id = central pad that opens the teleporter menu.
	_add_warp_pad("WarpTeleporter", Vector3(0.05, -5.08, 60.96), "", "Warp Teleporter")
	# Decorative special_c3 dressing around the pad — positions itself from
	# data/city_teleporter.json (authored in the web #/teleporter-mock).
	add_child(TeleporterDressingScript.new())


func _maybe_spawn_city_telepipe() -> void:
	if not TelepipeManager.is_active():
		return
	var telepipe := TelepipeScript.new()
	telepipe.name = "CityTelepipe"
	add_child(telepipe)
	telepipe.position = TELEPIPE_CITY_POS
	telepipe.activated.connect(_on_city_telepipe_activated)


## #358 — free the orphaned city telepipe pad when the manager state is canceled.
func _on_telepipe_canceled(_reason: String) -> void:
	var pipe := get_node_or_null("CityTelepipe")
	if pipe:
		pipe.name = "CityTelepipeStale"
		pipe.queue_free()


func _on_city_telepipe_activated() -> void:
	# consume_return() snapshots the saved location and clears the manager
	# state in one call, so by the time the field _ready hook runs we won't
	# re-spawn the telepipe there. That's the "one-shot" semantic: the round
	# trip from field → city → field destroys the telepipe.
	var snapshot: Dictionary = TelepipeManager.consume_return()
	if snapshot.is_empty():
		# Defensive: somehow lost the state between spawn and interact.
		return
	# Bring back the field run so quest objectives, companions, and section
	# state come back with the player. A quest lives in the suspended-quest
	# slot; a free field lives in the per-area Free-Roam store (spec
	# /states/quest-vs-field) — restore from whichever holds this run.
	if SessionManager.has_suspended_session():
		SessionManager.resume_session()
	elif SessionManager.has_free_roam_field(str(snapshot.get("area_id", ""))):
		SessionManager.enter_free_roam_field(str(snapshot.get("area_id", "")))
	# CRITICAL: override current_section to the telepipe's section_idx.
	# Without this, if the player suspended from a DIFFERENT section than
	# where the telepipe was placed (e.g. dropped telepipe in area B,
	# walked back to area A, then used StartWarp from area A), the resumed
	# session has current_section pointing at the suspend location (area
	# A = section 0), not the telepipe location (area B = section 2). The
	# field controller would then load section 0's cell_pos = wrong area's
	# stage, even though the telepipe stored cell coords for area B.
	var telepipe_section_idx: int = int(snapshot.get("section_idx", 0))
	SessionManager.set_current_section(telepipe_section_idx)
	# Pass the saved position so the field controller can spawn the player
	# exactly where they dropped the telepipe (rather than the section's
	# normal entry portal). Section state was saved by _travel_to_city_via_telepipe;
	# we hand it back through SceneManager's transition_data dict.
	var section_state: Dictionary = SessionManager.get_section_state(telepipe_section_idx)
	print("[TelepipeDEBUG] city→field section_idx=%d, section_state keys=%s, cell_states keys=%s, target_cell_pos=%s" % [
		int(snapshot.get("section_idx", 0)),
		str(section_state.keys()),
		str(section_state.get("cell_states", {}).keys()),
		str(snapshot.get("cell_pos", "0,0"))])
	SceneManager.goto_scene(snapshot.get("field_scene", "res://scenes/3d/field/valley_field.tscn"), {
		"current_cell_pos": snapshot.get("cell_pos", "0,0"),
		"telepipe_arrival_pos": snapshot.get("world_pos", Vector3.ZERO),
		"keys_collected": section_state.get("keys_collected", {}),
		"gates_opened": section_state.get("gates_opened", {}),
		"visited_cells": section_state.get("visited_cells", {}),
		"cell_states": section_state.get("cell_states", {}),
	})


func _notification(what: int) -> void:
	# Fires when overlay (guild counter) pops and this scene's process resumes
	if what == NOTIFICATION_UNPAUSED:
		_check_quest_accepted()


func _check_quest_accepted() -> void:
	var data := SceneManager.get_transition_data()
	if data.get("storage_closed", false):
		_play_npc_reaction("StorageNPC", "plymotiondata_421")
		return
	if not data.get("quest_accepted", false):
		return
	# Find the QuestCounterNPC and show a speech bubble + bow
	var counter_npc: Node3D = null
	for npc in _npcs:
		if npc.name == "QuestCounterNPC":
			counter_npc = npc
			break
	if not counter_npc:
		return
	if counter_npc.has_method("play_oneshot"):
		counter_npc.play_oneshot("pso_f_emote_bow")
	# Anchor the bubble to the NPC's live position + head offset. (A stale
	# hardcoded world pos left it floating far from the repositioned counter.)
	_show_npc_speech_bubble(counter_npc, counter_npc.global_position + BUBBLE_OFFSET,
		"Please head to the Principal's office for your briefing.")


func _play_npc_reaction(npc_name: String, anim_name: String) -> void:
	for npc in _npcs:
		if npc.name == npc_name and npc.has_method("play_oneshot"):
			npc.play_oneshot(anim_name)
			return


func _show_npc_speech_bubble(_npc: Node3D, world_pos: Vector3, text: String) -> void:
	SfxManager.play("res://assets/sfx/ui/dialog_open.wav")
	# Build a speech bubble at a fixed world position (not parented to scaled NPC)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(BUBBLE_WIDTH, BUBBLE_HEIGHT)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)

	var cx: float = BUBBLE_WIDTH * 0.5
	var top_y: float = BUBBLE_HEIGHT * 0.78

	var tail_border := Polygon2D.new()
	tail_border.polygon = PackedVector2Array([
		Vector2(cx - 13, top_y - 1),
		Vector2(cx + 13, top_y - 1),
		Vector2(cx, top_y + 30),
	])
	tail_border.color = Color(0.3, 0.3, 0.3, 0.6)
	root.add_child(tail_border)

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

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	label.add_theme_font_size_override("font_size", 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(cx - 12, top_y),
		Vector2(cx + 12, top_y),
		Vector2(cx, top_y + 28),
	])
	tail.color = Color.WHITE
	root.add_child(tail)

	var sprite := Sprite3D.new()
	sprite.pixel_size = 0.006
	sprite.global_position = world_pos
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.render_priority = 10
	add_child(sprite)

	# Assign texture after one frame
	(func() -> void:
		if viewport and sprite:
			sprite.texture = viewport.get_texture()
	).call_deferred()

	# Auto-dismiss after 6 seconds
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
		if is_instance_valid(viewport):
			viewport.queue_free()
	)


func _get_area_name() -> String:
	return "counter"
