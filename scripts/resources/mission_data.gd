class_name MissionData extends Resource
## Resource definition for missions.

@export var id: String = ""
@export var name: String = ""
@export var area: String = ""
@export var is_main: bool = false
@export var is_secret: bool = false
@export var requires: PackedStringArray = []
## Rewards per difficulty: { "normal": {item, quantity, meseta}, "hard": {...}, "superHard": {...} }
@export var rewards: Dictionary = {}
