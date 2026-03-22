extends DropBase
class_name DropItem
## Generic item drop that uses the weapon drop box model.
## Uses item_id to look up the item name from registries.


func _init() -> void:
	super._init()
	model_path = "valley/o0c_dropwe.glb"


func _get_display_name() -> String:
	if item_id.is_empty():
		return "Item"
	var info: Dictionary = Inventory._lookup_item(item_id)
	return info.get("name", item_id)


func _give_reward() -> void:
	if item_id.is_empty():
		push_warning("[DropItem] No item_id set")
		return

	if Inventory.add_item(item_id, amount):
		print("[DropItem] Collected ", amount, "x ", _get_display_name())
	else:
		print("[DropItem] Failed to add item to inventory: ", item_id)
