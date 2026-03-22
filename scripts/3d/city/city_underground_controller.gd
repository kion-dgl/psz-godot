extends "res://scripts/3d/city/city_area_base.gd"
## Underground (sewer) area controller — Photon Collector and Enemy Collector NPCs.

const DEFAULT_SPAWN := Vector3(0.04, 0, -1.0)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"market-exit": {
		"position": Vector3(0.04, 0, -1.0),
		"rotation": PI,
	},
}


func _ready() -> void:
	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on underground walkable area
	_add_floor_collision(Vector3(0, 0, -5), Vector3(30, 0.2, 30))

	# NPCs
	_add_npc(
		"SynthesisNPC", Vector3(8.38, 0, -4.81), PI,
		"res://assets/npcs/np_017_00_0/np_017_00_0.glb",
		"Synthesis Shop",
		"res://scenes/2d/shops/crafting_shop.tscn"
	)
	_add_npc(
		"PhotonCollectorNPC", Vector3(-6.32, 0, -5.35), PI,
		"res://assets/npcs/np_018_00_0/np_018_00_0.glb",
		"Photon Collector",
		"res://scenes/2d/shops/photon_shop.tscn"
	)

	# Interactive exit trigger — back to market
	_add_interactive_trigger(
		Vector3(0.04, 1, 3.0), Vector3(3, 3, 1),
		"res://scenes/3d/city/city_market.tscn", "underground-exit",
		"Exit to City"
	)

	# Wire up player references
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "underground"
