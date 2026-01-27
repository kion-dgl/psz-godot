extends Node
## Autoload that provides access to all EnemyData resources by ID.

const ENEMIES_PATH = "res://data/enemies/"

var _enemies: Dictionary = {}

signal enemies_loaded()


func _ready() -> void:
	_load_all_enemies()


func _load_all_enemies() -> void:
	_enemies.clear()

	var dir = DirAccess.open(ENEMIES_PATH)
	if dir == null:
		push_warning("[EnemyRegistry] Could not open enemies directory: ", ENEMIES_PATH)
		enemies_loaded.emit()
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path = ENEMIES_PATH + file_name
			var enemy = load(full_path)
			if enemy and not enemy.id.is_empty():
				_enemies[enemy.id] = enemy
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[EnemyRegistry] Loaded ", _enemies.size(), " enemies")
	enemies_loaded.emit()


func get_enemy(enemy_id: String):
	return _enemies.get(enemy_id, null)


func has_enemy(enemy_id: String) -> bool:
	return _enemies.has(enemy_id)


func get_enemies_by_element(element: int) -> Array:
	var result: Array = []
	for enemy in _enemies.values():
		if enemy.element == element:
			result.append(enemy)
	return result


func get_enemies_in_location(location: String) -> Array:
	var result: Array = []
	for enemy in _enemies.values():
		if enemy.spawns_in(location):
			result.append(enemy)
	return result


func get_all_enemy_ids() -> Array:
	return _enemies.keys()


func get_enemy_count() -> int:
	return _enemies.size()
