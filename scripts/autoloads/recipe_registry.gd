extends Node
## Autoload that provides access to all RecipeBoardData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const RECIPES_PATH = "res://data/recipes/"

var _recipes: Dictionary = {}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(RECIPES_PATH, _recipes, "RecipeRegistry", "recipes")


func get_recipe(id: String):
	return _recipes.get(id, null)


func get_all_recipes() -> Array:
	return _recipes.values()

