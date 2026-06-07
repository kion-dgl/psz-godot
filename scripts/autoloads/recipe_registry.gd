extends Node
## Autoload that provides access to all RecipeBoardData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const RECIPES_PATH = "res://data/recipes/"

var _recipes: Dictionary = {}

signal recipes_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(RECIPES_PATH, _recipes, "RecipeRegistry", "recipes")
	recipes_loaded.emit()


func get_recipe(id: String):
	return _recipes.get(id, null)


func get_all_recipes() -> Array:
	return _recipes.values()


func get_all_recipe_ids() -> Array:
	return _recipes.keys()
