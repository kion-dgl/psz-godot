extends Node
## Test launcher — loads valley field with stage s01b_ib1 (waterfall stage).
## Run this scene directly to skip field generation and jump to the stage.

func _ready() -> void:
	# Set up a minimal session so valley_field_controller finds what it needs
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections([{
		"type": "a",
		"area": "gurhacia",
		"start_pos": "0,0",
		"cells": [{
			"pos": "0,0",
			"stage_id": "s01b_ib1",
			"rotation": 0,
			"connections": {},
			"is_start": true,
		}],
	}])

	# Transition data the controller expects
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": "0,0",
		"spawn_edge": "",
		"keys_collected": {},
		"visited_cells": {},
	})
