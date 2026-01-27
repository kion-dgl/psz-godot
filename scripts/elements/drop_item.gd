extends DropBase
class_name DropItem
## Generic item drop that adds an ItemData item to inventory when collected.
## Uses item_id to look up the item in ItemRegistry.


func _init() -> void:
	super._init()
	# model_path will be set from ItemData if item_id is valid


func _ready() -> void:
	# If item_id is set, try to load model from ItemData
	if not item_id.is_empty():
		var item_data = ItemRegistry.get_item(item_id)
		if item_data and not item_data.model_path.is_empty():
			model_path = item_data.model_path

	super._ready()


func _give_reward() -> void:
	if item_id.is_empty():
		push_warning("[DropItem] No item_id set")
		return

	if Inventory.add_item(item_id, amount):
		var item_data = ItemRegistry.get_item(item_id)
		var item_name = item_data.name if item_data else item_id
		print("[DropItem] Collected ", amount, "x ", item_name)
	else:
		print("[DropItem] Failed to add item to inventory: ", item_id)
