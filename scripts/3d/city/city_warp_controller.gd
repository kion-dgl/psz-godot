extends "res://scripts/3d/city/city_area_base.gd"
## Warp area controller — 8 warp pads in circular arrangement.

const DEFAULT_SPAWN := Vector3(0.08, 2, 15.26)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"counter-exit": {
		"position": Vector3(0.08, 2, 15.26),
		"rotation": PI,
	},
}

const WALL_DATA := [
	# Circular containment walls (approximation with box segments)
	# North
	[-2, 0, 18.26, 3, PI / 2],
	[2, 0, 18.26, 3, PI / 2],
	# North-east
	[6, 0, 14, 6, -PI / 6],
	# East
	[9, 0, 7, 8, 0],
	# South-east
	[7, 0, -3, 6, PI / 6],
	# South
	[0, 0, -8.5, 10, PI / 2],
	# South-west
	[-7, 0, -3, 6, -PI / 6],
	# West
	[-9, 0, 7, 8, 0],
	# North-west
	[-6, 0, 14, 6, PI / 6],
	# Exit corridor walls
	[-1, 0, 17, 2, 0],
	[1, 0, 17, 2, 0],
]


func _ready() -> void:
	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~-8 to ~18)
	_add_floor_collision(Vector3(0, 0, 5), Vector3(24, 0.2, 30))

	# Walls
	var walls := CityWalls.new()
	walls.name = "Walls"
	add_child(walls)
	walls.create_walls(WALL_DATA)

	# Warp pads
	_add_warp_pad("GurhaciaValley", Vector3(4.55, 0, -4.10), "gurhacia-valley", "Gurhacia Valley")
	_add_warp_pad("OzetteWetlands", Vector3(6.56, 0, 0.42), "ozette-wetland", "Ozette Wetlands")
	_add_warp_pad("RiohSnowfield", Vector3(4.65, 0, 5.14), "rioh-snowfield", "Rioh Snowfield")
	_add_warp_pad("MakaraRuins", Vector3(0.08, 0, 6.72), "makara-ruins", "Makara Ruins")
	_add_warp_pad("OblivionCityParu", Vector3(-4.50, 0, 4.50), "oblivion-city-paru", "Oblivion City Paru")
	_add_warp_pad("ArcaPlant", Vector3(-6.68, 0, 0.42), "arca-plant", "Arca Plant")
	_add_warp_pad("DarkShrine", Vector3(-4.69, 0, -4.17), "dark-shrine", "Dark Shrine")
	_add_warp_pad("EternalTower", Vector3(0.08, 0, -6.25), "eternal-tower", "Eternal Tower")

	# North exit trigger → Counter
	_add_area_trigger(
		Vector3(0.105, 1, 18.26), Vector3(1, 2, 1),
		"res://scenes/3d/city/city_counter.tscn", "warp-exit"
	)

	# Wire up
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "warp"
