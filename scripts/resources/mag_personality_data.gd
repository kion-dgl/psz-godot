class_name MagPersonalityData extends Resource
## Resource definition for mag personalities.

@export var id: String = ""
@export var name: String = ""
@export var japanese_name: String = ""
@export var category: String = ""  # offensive, defensive, recovery, special
@export var tier: String = ""      # basic, advanced
@export var unlock_level: int = 0
@export var favorite_food: String = ""
@export var switch_from: String = ""
@export var triggers: Dictionary = {}
