class_name UnitData extends Resource
## Resource definition for unit (equipment slot) items.

@export var id: String = ""
@export var name: String = ""
@export var japanese_name: String = ""
@export_range(1, 7) var rarity: int = 1
@export var category: String = ""  # Power, Guard, HP, Hit, Mind, Swift
@export var effect: String = ""
@export var effect_value: int = 0
@export var pso_world_id: int = 0
