class_name MaterialData extends Resource
## Resource definition for materials (stat enhancement items).

@export var id: String = ""
@export var name: String = ""
@export var japanese_name: String = ""
@export var details: String = ""
@export_range(1, 7) var rarity: int = 6
@export var pso_world_id: int = 0
