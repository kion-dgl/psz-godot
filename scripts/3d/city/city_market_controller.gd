extends "res://scripts/3d/city/city_area_base.gd"
## Market area controller — first city area with 3 shop NPCs.

const DEFAULT_SPAWN := Vector3(0.98, 2, 62.79)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"counter-exit": {
		"position": Vector3(0.98, 2, 18.84),
		"rotation": PI,
	},
	"underground-exit": {
		"position": Vector3(-13.44, 2, 55.0),
		"rotation": 0.0,
	},
}


func _ready() -> void:
	# s00e_sa1 uses baked textures from psz-asset-viewer — no runtime fixes needed

	# Heal on city entry
	_heal_character()

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~14 to ~67)
	_add_floor_collision(Vector3(0, 0, 40), Vector3(50, 0.2, 70))

	# NPCs
	_add_npc(
		"ShopNPC", Vector3(-10.34, 0, 27.67), 1.4207,
		"res://assets/npcs/np_003_00_0/np_003_00_0.glb",
		"Shop",
		"res://scenes/2d/shops/item_shop.tscn"
	)
	_add_npc(
		"WeaponShopNPC", Vector3(-6.78, 0, 21.81), 0.7835,
		"res://assets/npcs/np_002_00_0/np_002_00_0.glb",
		"Weapon Shop",
		"res://scenes/2d/shops/weapon_shop.tscn"
	)
	_add_npc(
		"SynthesisNPC", Vector3(6.25, 0, 23.45), -0.7533,
		"res://assets/npcs/np_004_00_0/np_004_00_0.glb",
		"Synthesis Shop",
		"res://scenes/2d/shops/crafting_shop.tscn"
	)

	# Area triggers
	_add_area_trigger(
		Vector3(0.38, 1, 14.43), Vector3(7.42, 3, 1),
		"res://scenes/3d/city/city_counter.tscn", "market-exit"
	)
	# Interactive trigger — Enter Underground
	_add_interactive_trigger(
		Vector3(-13.44, 1, 57.44), Vector3(3, 3, 3),
		"res://scenes/3d/city/city_underground.tscn", "market-exit",
		"Enter Underground"
	)

	# Wire up player references
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "market"
