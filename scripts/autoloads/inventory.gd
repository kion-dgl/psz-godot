extends Node
## Player inventory system that stores ItemData references.
## Tracks item quantities and provides add/remove functionality.

## Maximum number of unique items (0 = unlimited)
@export var capacity: int = 0

## Dictionary of item_id -> quantity
var _items: Dictionary = {}

## Signals
signal item_added(item_id: String, quantity: int, total: int)
signal item_removed(item_id: String, quantity: int, remaining: int)
signal inventory_full()


## Add an item to inventory by ID
## Returns true if item was added successfully
func add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var item_data = ItemRegistry.get_item(item_id)
	if item_data == null:
		push_warning("[Inventory] Unknown item ID: ", item_id)
		return false

	# Check capacity (if limited)
	if capacity > 0 and not has_item(item_id) and _items.size() >= capacity:
		inventory_full.emit()
		return false

	# Check stack limit
	var current = _items.get(item_id, 0)
	var max_add = quantity

	if item_data.stackable:
		max_add = mini(quantity, item_data.max_stack - current)
	elif current > 0:
		# Non-stackable and already have one
		return false
	else:
		max_add = 1

	if max_add <= 0:
		return false

	_items[item_id] = current + max_add
	var new_total = _items[item_id]
	item_added.emit(item_id, max_add, new_total)
	print("[Inventory] Added ", max_add, "x ", item_data.name, " (total: ", new_total, ")")
	return true


## Remove an item from inventory by ID
## Returns true if item was removed successfully
func remove_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	if not has_item(item_id):
		return false

	var current = _items[item_id]
	var to_remove = mini(quantity, current)
	var remaining = current - to_remove

	if remaining <= 0:
		_items.erase(item_id)
		remaining = 0
	else:
		_items[item_id] = remaining

	item_removed.emit(item_id, to_remove, remaining)
	print("[Inventory] Removed ", to_remove, "x ", item_id, " (remaining: ", remaining, ")")
	return true


## Check if inventory contains an item
func has_item(item_id: String) -> bool:
	return _items.has(item_id) and _items[item_id] > 0


## Get quantity of an item
func get_item_count(item_id: String) -> int:
	return _items.get(item_id, 0)


## Get total number of unique items
func get_unique_item_count() -> int:
	return _items.size()


## Get all items as array of {id: String, quantity: int}
func get_all_items() -> Array:
	var result = []
	for item_id in _items:
		result.append({"id": item_id, "quantity": _items[item_id]})
	return result


## Get all items of a specific type (use ItemData.ItemType enum value)
func get_items_by_type(type: int) -> Array:
	var result = []
	for item_id in _items:
		var item_data = ItemRegistry.get_item(item_id)
		if item_data and item_data.type == type:
			result.append({"id": item_id, "quantity": _items[item_id], "data": item_data})
	return result


## Check if inventory has room for an item
func can_add_item(item_id: String) -> bool:
	# Already have it
	if has_item(item_id):
		var item_data = ItemRegistry.get_item(item_id)
		if item_data and item_data.stackable:
			return _items[item_id] < item_data.max_stack
		return false  # Non-stackable

	# Check capacity
	if capacity > 0 and _items.size() >= capacity:
		return false

	return true


## Use a consumable item (removes it and applies effect)
## Returns true if item was used
func use_item(item_id: String) -> bool:
	var item_data = ItemRegistry.get_item(item_id)
	if item_data == null or not has_item(item_id):
		return false

	# ItemType.CONSUMABLE = 2
	if item_data.type != 2:
		return false

	# Apply effects
	if item_data.has_stat("heal"):
		GameState.heal(item_data.get_stat("heal"))

	if item_data.has_stat("mp_restore"):
		GameState.restore_mp(item_data.get_stat("mp_restore"))

	# Remove from inventory
	remove_item(item_id, 1)
	print("[Inventory] Used: ", item_data.name)
	return true


## Clear all items
func clear_inventory() -> void:
	_items.clear()
	print("[Inventory] Cleared")
