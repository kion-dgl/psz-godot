extends Node
## Autoload that provides access to all EnemyData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const ENEMIES_PATH = "res://data/enemies/"

var _enemies: Dictionary = {}

signal enemies_loaded()


func _ready() -> void:
	_load_all_enemies()


func _load_all_enemies() -> void:
	_RH.load_dir(ENEMIES_PATH, _enemies, "EnemyRegistry", "enemies")
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
