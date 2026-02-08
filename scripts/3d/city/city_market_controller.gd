extends "res://scripts/3d/city/city_area_base.gd"
## Market area controller — first city area with 3 shop NPCs.

const DEFAULT_SPAWN := Vector3(0.98, 2, 62.79)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"counter-exit": {
		"position": Vector3(0.98, 2, 18.84),
		"rotation": PI,
	},
}

# Wall data: [x, y, z, length, rotation_y]
const WALL_DATA := [
	# West walls
	[-15.5, 0, 45, 40, 0],
	[-15.5, 0, 20, 10, 0],
	# East walls
	[16.5, 0, 45, 40, 0],
	[16.5, 0, 20, 10, 0],
	# North wall
	[0, 0, 67, 33, PI / 2],
	# South-west
	[-6, 0, 14.4, 10, PI / 2],
	# South-east
	[7, 0, 14.4, 10, PI / 2],
	# Shop alcove walls (west side)
	[-13, 0, 30, 6, 0],
	[-13, 0, 22, 4, PI / 2],
	# Shop alcove walls (east side)
	[13, 0, 30, 6, 0],
	[13, 0, 22, 4, PI / 2],
	# Inner corridor guides
	[-10, 0, 16, 4, PI / 4],
	[10, 0, 16, 4, -PI / 4],
	# Back walls behind shops
	[-9, 0, 35, 8, PI / 2],
	[9, 0, 35, 8, PI / 2],
	# Central platform edges
	[-5, 0, 40, 8, 0],
	[5, 0, 40, 8, 0],
	# Fountain barriers
	[-3, 0, 50, 4, PI / 2],
	[3, 0, 50, 4, PI / 2],
	[-3, 0, 55, 4, 0],
	[3, 0, 55, 4, 0],
	# Ramp edges
	[-4, 0, 60, 6, 0],
	[4, 0, 60, 6, 0],
	# Near-spawn containment
	[-8, 0, 65, 4, PI / 2],
	[8, 0, 65, 4, PI / 2],
]


func _ready() -> void:
	# Heal on city entry
	_heal_character()

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~14 to ~67)
	_add_floor_collision(Vector3(0, 0, 40), Vector3(50, 0.2, 70))

	# Walls
	var walls := CityWalls.new()
	walls.name = "Walls"
	add_child(walls)
	walls.create_walls(WALL_DATA)

	# NPCs
	_add_npc(
		"ShopNPC", Vector3(-10.34, 0, 27.67), PI,
		"res://assets/npcs/np_003_00_0/np_003_00_0.glb",
		"Shop",
		"res://scenes/2d/shops/item_shop.tscn"
	)
	_add_npc(
		"WeaponShopNPC", Vector3(-6.78, 0, 21.81), PI,
		"res://assets/npcs/np_002_00_0/np_002_00_0.glb",
		"Weapon Shop",
		"res://scenes/2d/shops/weapon_shop.tscn"
	)
	_add_npc(
		"TekkerNPC", Vector3(6.25, 0, 23.45), PI,
		"res://assets/npcs/np_004_00_0/np_004_00_0.glb",
		"Tekker",
		"res://scenes/2d/shops/tekker.tscn"
	)

	# Area triggers
	_add_area_trigger(
		Vector3(0.38, 1, 14.43), Vector3(7.42, 3, 1),
		"res://scenes/3d/city/city_counter.tscn", "market-exit"
	)

	# Wire up player references
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "market"
