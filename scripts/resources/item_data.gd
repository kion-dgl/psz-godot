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


## Get rarity as star string
func get_rarity_string() -> String:
	var stars = ""
	for i in range(rarity + 1):
		stars += "★"
	return stars
