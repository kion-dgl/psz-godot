class_name ExperienceTable extends Resource
## Experience table for leveling. Array of { "level": int, "totalExp": int, "expToNext": int }

@export var levels: Array[Dictionary] = []


func get_exp_for_level(level: int) -> int:
	for entry in levels:
		if int(entry.get("level", 0)) == level:
			return int(entry.get("totalExp", 0))
	return 0


func get_exp_to_next(level: int) -> int:
	for entry in levels:
		if int(entry.get("level", 0)) == level:
			return int(entry.get("expToNext", 0))
	return 0


func get_level_for_exp(total_exp: int) -> int:
	var result_level := 1
	for entry in levels:
		if total_exp >= int(entry.get("totalExp", 0)):
			result_level = int(entry.get("level", 1))
		else:
			break
	return result_level
