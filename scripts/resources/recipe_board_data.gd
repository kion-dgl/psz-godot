class_name RecipeBoardData extends Resource
## Resource definition for weapon synthesis recipe boards.

@export var id: String = ""
@export var name: String = ""
@export var details: String = ""
@export_range(1, 7) var rarity: int = 1
@export var output_weapon_id: String = ""
@export var ingredients: Array = []  # Array of {item_id: String, quantity: int}
@export var craft_cost: int = 0  # Meseta cost to craft
@export var has_photon_slot: bool = true
