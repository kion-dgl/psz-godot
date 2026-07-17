extends Node
## Autoload that provides access to all EnemyData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const ENEMIES_PATH = "res://data/enemies/"

var _enemies: Dictionary = {}


func _ready() -> void:
	_load_all_enemies()


func _load_all_enemies() -> void:
	_RH.load_dir(ENEMIES_PATH, _enemies, "EnemyRegistry", "enemies")


func get_enemy(enemy_id: String):
	return _enemies.get(enemy_id, null)


func get_enemy_count() -> int:
	return _enemies.size()
