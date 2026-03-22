extends DropBase
class_name DropMaterial
## Material/recipe drop that uses the item drop box model.


func _init() -> void:
	super._init()
	model_path = "valley/o0c_dropit.glb"


func _ready() -> void:
	# Use rare drop model for recipe boards
	if not item_id.is_empty():
		var recipe_res = RecipeRegistry.get_recipe(item_id)
		if recipe_res and not recipe_res.is_default:
			model_path = "valley/o0c_dropra.glb"
	super._ready()


func _get_display_name() -> String:
	if item_id.is_empty():
		return "Material"
	var mat_res = MaterialRegistry.get_material(item_id)
	if mat_res:
		return mat_res.name
	var recipe_res = RecipeRegistry.get_recipe(item_id)
	if recipe_res:
		return recipe_res.name
	return item_id


func _give_reward() -> void:
	if item_id.is_empty():
		push_warning("[DropMaterial] No item_id set")
		return

	if Inventory.add_item(item_id, amount):
		print("[DropMaterial] Collected ", amount, "x ", _get_display_name())
	else:
		print("[DropMaterial] Failed to add to inventory: ", item_id)
