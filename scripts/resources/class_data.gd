class_name ClassData extends Resource
## Resource definition for character classes, matching psz-sketch class schema.

@export var id: String = ""
@export var name: String = ""
@export var race: String = ""   # Human, Newman, Cast
@export var gender: String = "" # Male, Female
@export var type: String = ""   # Hunter, Ranger, Force
## Short playstyle descriptor used by the class-select UI in place of stat
## numbers — keeps focus on the character's role rather than the RPG values.
@export var tagline: String = ""
@export var bonuses: PackedStringArray = []
@export var material_limit: int = 100

## Innate weapon type — class gets bonus damage with this type (-1 = none)
## Values match WeaponData.WeaponType enum: SABER=0, SWORD=1, DAGGERS=2, CLAW=3, DOUBLE_SABER=4, SPEAR=5, SLICER=6, GUN_BLADE=7, SHIELD=8, HANDGUN=9, MECH_GUN=10, RIFLE=11, BAZOOKA=12, LASER_CANNON=13, ROD=14, WAND=15
@export var innate_weapon_type: int = -1

## Weapon types this class can equip (WeaponData.WeaponType enum values)
## Empty array means no restrictions (all weapons allowed)
@export var allowed_weapon_types: Array[int] = []

## Stats dict: { "hp": { "1": 82, "20": 258, ... }, "attack": {...}, ... }
## Breakpoints are the fallback path; per-level lookup prefers the ROM rows
## loaded from ROM_LEVEL_PARAMS_PATH (every level 1..100, no interpolation).
@export var stats: Dictionary = {}

## ROM-exact per-level stat rows, decoded from the original player_lv_param
## table (data/re_reference/player_lv_param.json; pszm-decomp FUN_020412d8
## row layout, dumped by scripts/tools/dump_player_lv_param.py). Class→member
## mapping follows the JSON's class_match evidence: all 14 classes matched a
## member's curve at every breakpoint (hucaseal accuracy L20 corrected to the
## ROM value 178 when this table was hooked up).
const ROM_LEVEL_PARAMS_PATH := "res://data/re_reference/player_lv_param.json"
const ROM_STAT_NAMES := ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]
static var _rom_rows_by_class: Dictionary = {}
static var _rom_loaded := false


static func _load_rom_rows() -> void:
	if _rom_loaded:
		return
	_rom_loaded = true
	if not FileAccess.file_exists(ROM_LEVEL_PARAMS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROM_LEVEL_PARAMS_PATH))
	if parsed == null or not parsed is Dictionary:
		return
	var members: Dictionary = parsed.get("members", {})
	for member_key in members:
		var member: Dictionary = members[member_key]
		var match: Dictionary = member.get("class_match", {})
		var class_id := ""
		if match.get("exact", []) is Array and not (match["exact"] as Array).is_empty():
			class_id = match["exact"][0]
		elif match.has("near"):
			class_id = match["near"]["class"]
		if class_id.is_empty():
			continue
		var rows := {}
		for stat_name in ROM_STAT_NAMES:
			var series: Array = member.get("stats", {}).get(stat_name, [])
			if series.size() == 100:
				rows[stat_name] = series
		if rows.size() == ROM_STAT_NAMES.size():
			_rom_rows_by_class[class_id] = rows

## Technique limits: { "foieBartaZonde": 15, "grants": 0, ... } (0 = can't use)
@export var technique_limits: Dictionary = {}

## Trap limits: { "fire": [5,6,7,8,9,10], ... } or empty if no traps
@export var trap_limits: Dictionary = {}


## Get stat value at a specific level. ROM rows give the exact per-level value
## when loaded; authored breakpoints (interpolated) remain the fallback.
func get_stat_at_level(stat_name: String, level: int) -> int:
	_load_rom_rows()
	if _rom_rows_by_class.has(id) and _rom_rows_by_class[id].has(stat_name):
		var series: Array = _rom_rows_by_class[id][stat_name]
		return int(series[clampi(level, 1, series.size()) - 1])
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
