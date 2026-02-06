class_name QuestDefinitionData extends Resource
## Resource definition for quest definitions.

@export var id: String = ""
@export var quest_id: String = ""
@export var quest_name: String = ""
@export var quest_type: String = ""  # "story", "side"
@export var area: String = ""
@export var description: String = ""
@export var difficulties: Array[Dictionary] = []
@export var requirements: Dictionary = {}
@export var objectives: Array[Dictionary] = []
@export var is_repeatable: bool = false
@export var is_secret: bool = false
