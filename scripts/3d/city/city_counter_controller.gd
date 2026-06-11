extends "res://scripts/3d/city/city_area_base.gd"
## Counter area controller — storage and quest counter NPCs.

const BUBBLE_WIDTH := 400
const BUBBLE_HEIGHT := 180

const TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")

const DEFAULT_SPAWN := Vector3(0.06, 2, 12.95)
const DEFAULT_ROT := PI

# Where the city-side telepipe spawns when one is active. Per spec: (0,0) in
# the city scene with the quest + storage NPCs (this scene). Player spawn for
# the "telepipe-arrival" variant lands a step in front of it so they're not
# clipping the trigger volume on arrival.
const TELEPIPE_CITY_POS := Vector3(0, 0, 0)

const SPAWN_VARIANTS := {
	"market-exit": {
		"position": Vector3(0.06, 2, 12.95),
		"rotation": PI,
	},
	"warp-exit": {
		"position": Vector3(0.50, 2, -15.33),
		"rotation": 0.0,
	},
	"office-exit": {
		"position": Vector3(11.496, 0, -11.572),
		"rotation": PI + PI / 4,
	},
	"telepipe-arrival": {
		# Per spec: (2, 0, 0) drops the player just east of the city-side
		# telepipe (which lives at TELEPIPE_CITY_POS = 0,0,0), placing them
		# next to the counter NPCs. Rotation faces west so the cyan pillar
		# is right in front of the player on arrival — they can press accept
		# immediately to bounce back to the field, or walk away to use the
		# storage / quest counter.
		"position": Vector3(2, 0, 0),
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

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~-22 to ~20)
	_add_floor_collision(Vector3(0, 0, 0), Vector3(30, 0.2, 50))

	# NPCs
	_add_npc(
		"StorageNPC", Vector3(-10.66, 0, -7.93), 4.06 + PI,
		"res://assets/npcs/np_000_00_0/np_000_00_0.glb",
		"Storage",
		"res://scenes/2d/storage.tscn",
		"pso_f_sa_stand"
	)
	_add_npc(
		"QuestCounterNPC", Vector3(-8.31, 0, -10.37), 3.86 + PI,
		"res://assets/npcs/np_001_00_0/np_001_00_0.glb",
		"Guild Counter",
		"res://scenes/2d/guild_counter.tscn",
		"pso_f_sa_stand"
	)

	# Area triggers
	_add_area_trigger(
		Vector3(0, 1, 20), Vector3(4, 3, 1),
		"res://scenes/3d/city/city_market.tscn", "counter-exit"
	)
	_add_area_trigger(
		Vector3(-0.015, 1, -22.305), Vector3(3.29, 3, 0.91),
		"res://scenes/3d/city/city_warp.tscn", "counter-exit"
	)

	# East exit — Principal's office
	_add_area_trigger(
		Vector3(11.496, 1, -11.572), Vector3(2, 3, 2),
		"res://scenes/3d/city/city_office.tscn", "counter-office"
	)

	# City-side telepipe — spawns if a player-dropped telepipe is active in
	# TelepipeManager. Interaction (E) consumes it: returns the player to the
	# field cell where it was dropped, and the telepipe disappears in both
	# city and field (one-shot return per spec).
	_maybe_spawn_city_telepipe()

	# Wire up
	_connect_player_to_interactables()


func _maybe_spawn_city_telepipe() -> void:
	if not TelepipeManager.is_active():
		return
	var telepipe := TelepipeScript.new()
	telepipe.name = "CityTelepipe"
	add_child(telepipe)
	telepipe.position = TELEPIPE_CITY_POS
	telepipe.activated.connect(_on_city_telepipe_activated)


func _on_city_telepipe_activated() -> void:
	# consume_return() snapshots the saved location and clears the manager
	# state in one call, so by the time the field _ready hook runs we won't
	# re-spawn the telepipe there. That's the "one-shot" semantic: the round
	# trip from field → city → field destroys the telepipe.
	var snapshot: Dictionary = TelepipeManager.consume_return()
	if snapshot.is_empty():
		# Defensive: somehow lost the state between spawn and interact.
		return
	# Bring back the suspended quest/field session so quest objectives,
	# companions, and section state come back with the player.
	if SessionManager.has_suspended_session():
		SessionManager.resume_session()
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
	_show_npc_speech_bubble(counter_npc, Vector3(-8.31, 2.8, -10.37),
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
