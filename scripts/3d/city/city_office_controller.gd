extends "res://scripts/3d/city/city_area_base.gd"
## Principal's office — quest client NPC.

const NPC_POSITION := Vector3(0.000, 0.000, -5.600)
const NPC_ROTATION_Y := 0.000
const NPC_SCALE := 0.160

const ROOM_SCALE := 0.160

const DOOR_TRIGGER_POSITION := Vector3(0.000, 1.000, 10.900)
const DOOR_TRIGGER_SIZE := Vector3(8.100, 2.000, 1.200)

const SPAWN_POSITION := Vector3(0.000, 0.000, 8.700)
const SPAWN_ROTATION_Y := 3.142

const DEFAULT_SPAWN := Vector3(0.000, 0.000, 8.700)
const DEFAULT_ROT := 3.142

const SPAWN_VARIANTS := {
	"counter-office": {
		"position": Vector3(0.000, 0.000, 8.700),
		"rotation": 3.142,
	},
}


func _ready() -> void:
	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision
	_add_floor_collision(Vector3(0, 0, 0), Vector3(20, 0.2, 30))

	# Principal NPC
	var npc := _add_npc(
		"PrincipalNPC", NPC_POSITION, NPC_ROTATION_Y,
		"res://assets/npcs/principal/principal.glb",
		"Principal",
		"res://scenes/2d/guild_counter.tscn"
	)
	npc.scale = Vector3(NPC_SCALE, NPC_SCALE, NPC_SCALE)

	# Exit trigger — back to counter
	_add_area_trigger(
		DOOR_TRIGGER_POSITION, DOOR_TRIGGER_SIZE,
		"res://scenes/3d/city/city_counter.tscn", "office-exit"
	)

	# Wire up
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "office"
