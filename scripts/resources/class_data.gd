class_name ClassData extends Resource
## Resource definition for character classes, matching psz-sketch class schema.

@export var id: String = ""
@export var name: String = ""
@export var race: String = ""   # Human, Newman, Cast
@export var gender: String = "" # Male, Female
@export var type: String = ""   # Hunter, Ranger, Force
@export var bonuses: PackedStringArray = []
@export var material_limit: int = 100

## Innate weapon type — class gets bonus damage with this type (-1 = none)
## Values match WeaponData.WeaponType enum: SABER=0, SWORD=1, DAGGERS=2, CLAW=3, DOUBLE_SABER=4, SPEAR=5, SLICER=6, GUN_BLADE=7, SHIELD=8, HANDGUN=9, MECH_GUN=10, RIFLE=11, BAZOOKA=12, LASER_CANNON=13, ROD=14, WAND=15
@export var innate_weapon_type: int = -1

## Weapon types this class can equip (WeaponData.WeaponType enum values)
## Empty array means no restrictions (all weapons allowed)
@export var allowed_weapon_types: Array[int] = []

## Stats dict: { "hp": { "1": 82, "20": 258, ... }, "attack": {...}, ... }
@export var stats: Dictionary = {}

## Technique limits: { "foieBartaZonde": 15, "grants": 0, ... } (0 = can't use)
@export var technique_limits: Dictionary = {}

## Trap limits: { "fire": [5,6,7,8,9,10], ... } or empty if no traps
@export var trap_limits: Dictionary = {}


## Get stat value at a specific level (interpolates between defined breakpoints)
func get_stat_at_level(stat_name: String, level: int) -> int:
	if not stats.has(stat_name):
		return 0
	var stat_table: Dictionary = stats[stat_name]
	var breakpoints := [1, 20, 40, 60, 80, 100]

	# Exact match
	var level_str := str(level)
	if stat_table.has(level_str):
		return int(stat_table[level_str])

	# Find surrounding breakpoints and interpolate
	var lower_bp := 1
	var upper_bp := 100
	for i in range(breakpoints.size() - 1):
		if level >= breakpoints[i] and level < breakpoints[i + 1]:
			lower_bp = breakpoints[i]
			upper_bp = breakpoints[i + 1]
			break

	var lower_val: float = float(stat_table.get(str(lower_bp), 0))
	var upper_val: float = float(stat_table.get(str(upper_bp), 0))
	var t := float(level - lower_bp) / float(upper_bp - lower_bp)
	return int(lerpf(lower_val, upper_val, t))


## Get all stats at a level as a dictionary
func get_stats_at_level(level: int) -> Dictionary:
	var result: Dictionary = {}
	for stat_name in ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]:
		result[stat_name] = get_stat_at_level(stat_name, level)
	return result


## Check if this class can equip a weapon type
func can_equip_weapon_type(weapon_type: int) -> bool:
	if allowed_weapon_types.is_empty():
		return true
	return weapon_type in allowed_weapon_types


## Get short description for class selection
func get_description() -> String:
	return "%s %s %s" % [race, gender, type]
