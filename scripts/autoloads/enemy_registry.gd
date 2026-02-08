extends Node
## Autoload that provides access to all EnemyData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const ENEMIES_PATH = "res://data/enemies/"

var _enemies: Dictionary = {}

signal enemies_loaded()


func _ready() -> void:
	_load_all_enemies()


func _load_all_enemies() -> void:
	_enemies.clear()
	for path in _RU.list_resources(ENEMIES_PATH):
		var enemy = load(path)
		if enemy and not enemy.id.is_empty():
			_enemies[enemy.id] = enemy
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
