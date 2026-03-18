extends Node
## QuestLoader — loads hand-authored quest JSON files from res://data/quests/
## and field quest files from res://data/field_quests/.


func load_quest(quest_id: String) -> Dictionary:
	var path := "res://data/quests/%s.json" % quest_id
	return _load_json(path)


func load_field_quest(quest_id: String) -> Dictionary:
	var path := "res://data/field_quests/%s.json" % quest_id
	return _load_json(path)


func list_quests() -> Array[String]:
	return _list_json_dir("res://data/quests")


func list_field_quests() -> Array[String]:
	return _list_json_dir("res://data/field_quests")


## Return a random field quest for the given area_id, or empty if none found.
func pick_field_quest(area_id: String) -> Dictionary:
	var all_ids := list_field_quests()
	var matching: Array[String] = []
	for qid in all_ids:
		var quest := load_field_quest(qid)
		if str(quest.get("area_id", "")) == area_id:
			matching.append(qid)
	if matching.is_empty():
		return {}
	matching.sort()
	var pick: String = matching[0]  # Always pick first (_01) for testing
	return load_field_quest(pick)


func _load_json(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		return {}
	var json := JSON.new()
	if json.parse(fa.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _list_json_dir(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if not dir:
		return result
	dir.list_dir_begin()
	var file := dir.get_next()
	while not file.is_empty():
		if file.ends_with(".json") or file.ends_with(".json.remap"):
			var name := file.replace(".json.remap", "").replace(".json", "")
			if name != "manifest":
				result.append(name)
		file = dir.get_next()
	return result
