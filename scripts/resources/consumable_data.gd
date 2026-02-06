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
