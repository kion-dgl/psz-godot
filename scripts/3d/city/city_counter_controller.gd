extends "res://scripts/3d/city/city_area_base.gd"
## Counter area controller — storage and quest counter NPCs.

const BUBBLE_WIDTH := 400
const BUBBLE_HEIGHT := 180

const DEFAULT_SPAWN := Vector3(0.06, 2, 12.95)
const DEFAULT_ROT := PI

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
}

const WALL_DATA := [
	# West walls
	[-12, 0, 0, 30, 0],
	# East walls
	[12, 0, 0, 30, 0],
	# North boundary
	[-4, 0, 18, 6, PI / 2],
	[4, 0, 18, 6, PI / 2],
	# South boundary
	[-3.5, 0, -22.3, 5, PI / 2],
	[3.5, 0, -22.3, 5, PI / 2],
	# Counter desk (west)
	[-10, 0, -5, 8, 0],
	[-7, 0, -9, 4, PI / 2],
	# Counter desk (east)
	[10, 0, -5, 8, 0],
	[7, 0, -9, 4, PI / 2],
	# Corridor narrowing north
	[-8, 0, 15, 4, PI / 4],
	[8, 0, 15, 4, -PI / 4],
	# Corridor narrowing south
	[-8, 0, -18, 4, -PI / 4],
	[8, 0, -18, 4, PI / 4],
	# Inner pillars/benches
	[-4, 0, 5, 3, 0],
	[4, 0, 5, 3, 0],
	[-4, 0, -3, 3, 0],
	[4, 0, -3, 3, 0],
	# Back wall sections
	[-6, 0, -12, 4, PI / 2],
	[6, 0, -12, 4, PI / 2],
	# Exit corridor guides
	[-2, 0, -20, 3, 0],
	[2, 0, -20, 3, 0],
]


func _ready() -> void:
	# Apply texture fixes from global config
	_fix_city_materials()

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~-22 to ~20)
	_add_floor_collision(Vector3(0, 0, 0), Vector3(30, 0.2, 50))

	# Walls
	var walls := CityWalls.new()
	walls.name = "Walls"
	add_child(walls)
	walls.create_walls(WALL_DATA)

	# NPCs
	_add_npc(
		"StorageNPC", Vector3(-10.66, 0, -7.93), 4.06 + PI,
		"res://assets/npcs/np_000_00_0/np_000_00_0.glb",
		"Storage",
		"res://scenes/2d/storage.tscn"
	)
	_add_npc(
		"QuestCounterNPC", Vector3(-8.31, 0, -10.37), 3.86 + PI,
		"res://assets/npcs/np_001_00_0/np_001_00_0.glb",
		"Guild Counter",
		"res://scenes/2d/guild_counter.tscn"
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

	# Wire up
	_connect_player_to_interactables()


func _notification(what: int) -> void:
	# Fires when overlay (guild counter) pops and this scene's process resumes
	if what == NOTIFICATION_UNPAUSED:
		_check_quest_accepted()


func _check_quest_accepted() -> void:
	var data := SceneManager.get_transition_data()
	if not data.get("quest_accepted", false):
		return
	# Find the QuestCounterNPC and show a speech bubble above it
	var counter_npc: Node3D = null
	for npc in _npcs:
		if npc.name == "QuestCounterNPC":
			counter_npc = npc
			break
	if not counter_npc:
		return
	_show_npc_speech_bubble(counter_npc, Vector3(-8.31, 2.8, -10.37),
		"Please head to the Principal's office for your briefing.")


func _show_npc_speech_bubble(npc: Node3D, world_pos: Vector3, text: String) -> void:
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
