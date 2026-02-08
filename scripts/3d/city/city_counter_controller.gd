extends "res://scripts/3d/city/city_area_base.gd"
## Counter area controller — storage and quest counter NPCs.

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

	# Wire up
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "counter"
