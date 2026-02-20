extends Node
## QuestLoader — loads hand-authored quest JSON files from res://data/quests/.


func load_quest(quest_id: String) -> Dictionary:
	var path := "res://data/quests/%s.json" % quest_id
	if not FileAccess.file_exists(path):
		return {}
	var fa := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(fa.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func list_quests() -> Array[String]:
	var quests: Array[String] = []
	var dir := DirAccess.open("res://data/quests")
	if not dir:
		return quests
	dir.list_dir_begin()
	var file := dir.get_next()
	while not file.is_empty():
		if file.ends_with(".json") or file.ends_with(".json.remap"):
			quests.append(file.replace(".json.remap", "").replace(".json", ""))
		file = dir.get_next()
	return quests
