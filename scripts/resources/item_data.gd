class_name ItemData extends Resource
## Resource definition for all game items (weapons, armor, consumables, keys, materials)

enum ItemType {
	WEAPON,
	ARMOR,
	CONSUMABLE,
	KEY,
	MATERIAL,
	ACCESSORY,
}

## Unique identifier for this item
@export var id: String = ""

## Display name
@export var name: String = ""

## Item category
@export var type: ItemType = ItemType.MATERIAL

## Rarity (0-4 stars)
@export_range(0, 4) var rarity: int = 0

## Icon texture for UI display
@export var icon: Texture2D

## Path to 3D model (relative to assets folder)
@export var model_path: String = ""

## Item stats (atk, def, hp, mp, etc.)
@export var stats: Dictionary = {}

## Base shop value in meseta
@export var value: int = 0

## Description text
@export_multiline var description: String = ""

## Whether item can be stacked in inventory
@export var stackable: bool = false

## Maximum stack size (if stackable)
@export var max_stack: int = 99


## Get a stat value, returns 0 if not present
func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 0)


## Check if item has a specific stat
func has_stat(stat_name: String) -> bool:
	return stats.has(stat_name)


## Get the full model path for loading
func get_model_resource_path() -> String:
	if model_path.is_empty():
		return ""
	return "res://assets/objects/" + model_path


## Get type as readable string
func get_type_name() -> String:
	match type:
		ItemType.WEAPON:
			return "Weapon"
		ItemType.ARMOR:
			return "Armor"
		ItemType.CONSUMABLE:
			return "Consumable"
		ItemType.KEY:
			return "Key"
		ItemType.MATERIAL:
			return "Material"
		ItemType.ACCESSORY:
			return "Accessory"
	return "Unknown"


## Get rarity as star string
func get_rarity_string() -> String:
	var stars = ""
	for i in range(rarity + 1):
		stars += "★"
	return stars
