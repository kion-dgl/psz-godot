extends Node
## Test launcher for valley field — sets up SessionManager with a simple 2-cell
## layout using s01a_sa1, then transitions to the 3D valley field scene.

func _ready() -> void:
	# Set up a field session
	SessionManager.enter_field("gurhacia", "normal")

	# Cell 0,0: player enters here (start). South gate connects to cell 0,1.
	# Cell 0,1: player enters from north. South warp_edge exits the section.
	var cells := [
		{
			"pos": "0,0",
			"stage_id": "s01a_sa1",
			"rotation": 0,
			"is_start": true,
			"is_end": false,
			"connections": {"south": "0,1"},
			"has_key": false,
		},
		{
			"pos": "0,1",
			"stage_id": "s01a_sa1",
			"rotation": 0,
			"is_start": false,
			"is_end": true,
			"connections": {"north": "0,0"},
			"has_key": false,
			"warp_edge": "south",
		},
	]

	var sections := [
		{
			"type": "grid",
			"area": "a",
			"cells": cells,
			"start_pos": "0,0",
			"end_pos": "0,1",
		},
	]

	SessionManager.set_field_sections(sections)

	# Transition to the 3D valley field scene
	# spawn_edge="" → cell 0,0 has south portal, so player spawns at south spawn point.
	# Cell 0,1 entry with spawn_edge="north" → no north portal → falls to default spawn.
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": "0,0",
		"spawn_edge": "",
		"keys_collected": {},
	})
