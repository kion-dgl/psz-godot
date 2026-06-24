class_name ConsumableData extends Resource
## Resource definition for consumable items.

@export var id: String = ""
@export var name: String = ""
@export var japanese_name: String = ""
@export var details: String = ""
@export_range(1, 7) var rarity: int = 1
@export var max_stack: int = 10
@export var pso_world_id: int = 0

## Buy/sell price
@export var buy_price: int = 0
@export var sell_price: int = 0

## Class/race usage restriction — same contract as WeaponData/ArmorData:
## empty means usable by everyone; otherwise the character's "Type Race" string
## (e.g. "Force Newman") must be listed. Drives the capability grey in the item
## shop (spec /states/shops). NOTE: no consumable populates this yet — which
## items a CAST cannot use (the antidote/antipara observation) is the open
## question tracked in the spec; until then every consumable is usable by all.
@export var usable_by: PackedStringArray = []


## True if a character whose class/race is `class_name_str` ("Type Race") can use
## this consumable. Empty `usable_by` = no restriction.
func can_be_used_by(class_name_str: String) -> bool:
	if usable_by.is_empty():
		return true
	return class_name_str in usable_by
