extends Node
## Autoload that provides access to all RecipeBoardData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const RECIPES_PATH = "res://data/recipes/"

var _recipes: Dictionary = {}

signal recipes_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_recipes.clear()
	for path in _RU.list_resources(RECIPES_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_recipes[res.id] = res
	print("[RecipeRegistry] Loaded ", _recipes.size(), " recipes")
	recipes_loaded.emit()


func get_recipe(id: String):
	return _recipes.get(id, null)


func get_all_recipes() -> Array:
	return _recipes.values()


func get_all_recipe_ids() -> Array:
	return _recipes.keys()
