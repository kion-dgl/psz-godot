extends "res://scripts/3d/city/city_area_base.gd"
## Warp area controller — single central warp pad that opens the teleporter menu.

const DEFAULT_SPAWN := Vector3(0.08, 2, 15.26)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"counter-exit": {
		"position": Vector3(0.08, 2, 15.26),
		"rotation": PI,
	},
}


func _ready() -> void:
	# Apply texture fixes from global config
	_fix_city_materials()
	# Match SA2 hallway lighting style — bright center, darker edges
	_add_interior_lights([
		Vector3(0, 4, 14),
		Vector3(0, 4, 8),
		Vector3(0, 4, 2),
		Vector3(0, 4, -4),
	])

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~-8 to ~18)
	_add_floor_collision(Vector3(0, 0, 5), Vector3(24, 0.2, 30))

	# Single central warp pad — area selection happens in the teleporter menu
	_add_warp_pad("WarpTeleporter", Vector3(0.08, 0, 1.0), "", "Warp Teleporter")

	# North exit trigger → Counter
	_add_area_trigger(
		Vector3(0.105, 1, 18.26), Vector3(1, 2, 1),
		"res://scenes/3d/city/city_counter.tscn", "warp-exit"
	)

	# Wire up
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "warp"
