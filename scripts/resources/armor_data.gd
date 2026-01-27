class_name ArmorData extends Resource
## Resource definition for armor, matching psz-sketch armor schema

enum ArmorType {
	ARMOR,  # Hunter type
	FRAME,  # Ranger/CAST type
	ROBE,   # Force type
	RARE,   # Special rare armors
}

## Unique identifier (derived from filename)
@export var id: String = ""

## Display name
@export var name: String = ""

## Japanese name
@export var japanese_name: String = ""

## Armor category
@export var type: ArmorType = ArmorType.ARMOR

## Rarity (1-7 stars)
@export_range(1, 7) var rarity: int = 1

## Maximum grind level
@export var max_grind: int = 0

## Required level to equip
@export var level: int = 1

## Shop resale value in meseta
@export var resale_value: int = 0

## Base defense
@export var defense_base: int = 0

## Max defense at max grind
@export var defense_max: int = 0

## Base evasion
@export var evasion_base: int = 0

## Max evasion at max grind
@export var evasion_max: int = 0

## Maximum unit slots (0-4)
@export_range(0, 4) var max_slots: int = 0

## Elemental resistances
@export var resist_fire: int = 0
@export var resist_ice: int = 0
@export var resist_lightning: int = 0
@export var resist_light: int = 0
@export var resist_dark: int = 0

## Classes that can use this armor
@export var usable_by: PackedStringArray = []

## Set bonus reference (if applicable)
@export var set_bonus: String = ""

## PSO World reference ID
@export var pso_world_id: int = 0

## Icon texture
@export var icon: Texture2D


## Get armor type as string
func get_type_name() -> String:
	match type:
		ArmorType.ARMOR: return "Armor"
		ArmorType.FRAME: return "Frame"
		ArmorType.ROBE: return "Robe"
		ArmorType.RARE: return "Rare"
	return "Unknown"


## Get defense at specific grind level
func get_defense_at_grind(grind: int) -> int:
	if max_grind <= 0:
		return defense_base
	var t = clampf(float(grind) / float(max_grind), 0.0, 1.0)
	return int(lerpf(defense_base, defense_max, t))


## Get evasion at specific grind level
func get_evasion_at_grind(grind: int) -> int:
	if max_grind <= 0:
		return evasion_base
	var t = clampf(float(grind) / float(max_grind), 0.0, 1.0)
	return int(lerpf(evasion_base, evasion_max, t))


## Check if a class can use this armor
func can_be_used_by(class_name_str: String) -> bool:
	if usable_by.is_empty():
		return true  # No restrictions
	return class_name_str in usable_by


## Get rarity as star string
func get_rarity_string() -> String:
	var stars = ""
	for i in range(rarity):
		stars += "★"
	return stars


## Get total elemental resistance
func get_total_resistance() -> int:
	return resist_fire + resist_ice + resist_lightning + resist_light + resist_dark
