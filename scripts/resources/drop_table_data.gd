class_name DropTableData extends Resource
## Resource definition for enemy drop tables.

@export var id: String = ""
@export var difficulty: String = ""  # "normal", "hard", "super-hard"
## Area drops: { "areaName": { "enemyName": ["item1", "item2"] } }
@export var area_drops: Dictionary = {}
