class_name EnemyData extends Resource
## Resource definition for enemies
## Combines psz-sketch metadata with combat stats for Godot

enum Element {
	NATIVE,
	BEAST,
	MACHINE,
	DARK,
}

enum BehaviorType {
	MELEE,      # Walks toward player and attacks
	RANGED,     # Keeps distance, shoots projectiles
	CHARGER,    # Charges at player
	SWARM,      # Weak but attacks in groups
	TANK,       # Slow, high HP
	BOSS,       # Special boss patterns
}

## Unique identifier (derived from filename)
@export var id: String = ""

## Display name
@export var name: String = ""

## Japanese name
@export var japanese_name: String = ""

## Element type (affects damage weaknesses)
@export var element: Element = Element.NATIVE

## Locations where this enemy spawns
@export var locations: PackedStringArray = []

## Is this a rare variant?
@export var is_rare: bool = false

## Is this a boss enemy?
@export var is_boss: bool = false

## 3D model ID for loading
@export var model_id: String = ""

# ============================================================================
# COMBAT STATS (not in psz-sketch, designed for Godot)
# ============================================================================

## Base HP (scales with difficulty)
@export var hp_base: int = 100

## Base attack damage
@export var attack_base: int = 10

## Base defense
@export var defense_base: int = 5

## Movement speed
@export var move_speed: float = 3.0

## Attack range (how close before attacking)
@export var attack_range: float = 2.0

## Detection range (how far they can see player)
@export var detection_range: float = 15.0

## Experience given on defeat
@export var exp_reward: int = 10

## Meseta dropped on defeat
@export var meseta_min: int = 5
@export var meseta_max: int = 15

## Behavior pattern
@export var behavior: BehaviorType = BehaviorType.MELEE

## Attack cooldown in seconds
@export var attack_cooldown: float = 1.5

## Collision radius
@export var collision_radius: float = 0.5

## Collision height
@export var collision_height: float = 1.5


## Get element as string
func get_element_name() -> String:
	match element:
		Element.NATIVE: return "Native"
		Element.BEAST: return "Beast"
		Element.MACHINE: return "Machine"
		Element.DARK: return "Dark"
	return "Unknown"


## Get behavior as string
func get_behavior_name() -> String:
	match behavior:
		BehaviorType.MELEE: return "Melee"
		BehaviorType.RANGED: return "Ranged"
		BehaviorType.CHARGER: return "Charger"
		BehaviorType.SWARM: return "Swarm"
		BehaviorType.TANK: return "Tank"
		BehaviorType.BOSS: return "Boss"
	return "Unknown"


## Get HP scaled for difficulty (1.0 = normal, 1.5 = hard, 2.0 = super hard)
func get_hp_for_difficulty(difficulty_mult: float = 1.0) -> int:
	return int(hp_base * difficulty_mult)


## Get attack scaled for difficulty
func get_attack_for_difficulty(difficulty_mult: float = 1.0) -> int:
	return int(attack_base * difficulty_mult)


## Get random meseta drop amount
func get_meseta_drop() -> int:
	return randi_range(meseta_min, meseta_max)


## Check if enemy spawns in a location
func spawns_in(location: String) -> bool:
	return location in locations


## Get model resource path
func get_model_path() -> String:
	if model_id.is_empty():
		return ""
	# TODO: Update path when enemy models are imported
	return "res://assets/enemies/" + model_id + "/" + model_id + ".glb"
