class_name SetBonusData extends Resource
## Resource definition for armor set bonuses.

@export var id: String = ""
@export var armor: String = ""
@export var weapons: PackedStringArray = []
@export var bonuses: Dictionary = {}  # { "attack": 10, "defense": 5, ... }
