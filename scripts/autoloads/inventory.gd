extends Node
## Player inventory system that stores ItemData references.
## Tracks item quantities and provides add/remove functionality.

## Maximum number of unique items (0 = unlimited)
@export var capacity: int = 40

## Dictionary of item_id -> quantity
var _items: Dictionary = {}

## Separate key storage (field-scoped, doesn't count toward capacity)
var _keys: Dictionary = {}

## Signals
signal item_added(item_id: String, quantity: int, total: int)
signal item_removed(item_id: String, quantity: int, remaining: int)
signal inventory_full()


## Add an item to inventory by ID
## Returns true if item was added successfully
func add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var info = _lookup_item(item_id)
	var item_name: String = info.name

	if _is_per_slot(item_id):
		# Per-slot items (weapons, armor, units, mags): each copy takes 1 slot
		var available: int = capacity - get_total_slots() if capacity > 0 else quantity
		var max_add: int = mini(quantity, available)
		if max_add <= 0:
			inventory_full.emit()
			return false
		_items[item_id] = int(_items.get(item_id, 0)) + max_add
		var new_total: int = int(_items[item_id])
		item_added.emit(item_id, max_add, new_total)
		print("[Inventory] Added ", max_add, "x ", item_name, " (total: ", new_total, ")")
		return true
	else:
		# Stackable items: 1 stack = 1 slot, limited by max_stack
		if capacity > 0 and not has_item(item_id) and get_total_slots() >= capacity:
			inventory_full.emit()
			return false
		var max_stack: int = info.max_stack
		var current: int = int(_items.get(item_id, 0))
		var max_add: int = mini(quantity, max_stack - current)
		if max_add <= 0:
			return false
		_items[item_id] = current + max_add
		var new_total: int = int(_items[item_id])
		item_added.emit(item_id, max_add, new_total)
		print("[Inventory] Added ", max_add, "x ", item_name, " (total: ", new_total, ")")
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


## Get all items as array of {id: String, name: String, quantity: int}
func get_all_items() -> Array:
	var result = []
	for item_id in _items:
		var info = _lookup_item(item_id)
		result.append({"id": item_id, "name": info.name, "quantity": _items[item_id]})
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
	if _is_per_slot(item_id):
		# Per-slot: just need a free slot
		return capacity <= 0 or get_total_slots() < capacity
	# Stackable: check stack limit
	if has_item(item_id):
		var info = _lookup_item(item_id)
		return int(_items[item_id]) < info.max_stack
	# New stackable item: need a free slot
	if capacity > 0 and get_total_slots() >= capacity:
		return false
	return true


## Count total inventory slots used. Per-slot items count each copy as 1 slot.
func get_total_slots() -> int:
	var total := 0
	for item_id in _items:
		if _is_per_slot(item_id):
			total += int(_items[item_id])  # each copy = 1 slot
		else:
			total += 1  # entire stack = 1 slot
	return total


## Check if an item is per-slot (each copy takes 1 inventory slot)
func _is_per_slot(item_id: String) -> bool:
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(item_id) or WeaponRegistry.get_weapon(norm_id):
		return true
	if ArmorRegistry.get_armor(item_id) or ArmorRegistry.get_armor(norm_id):
		return true
	if UnitRegistry.get_unit(item_id) or UnitRegistry.get_unit(norm_id):
		return true
	if ResourceLoader.exists("res://data/mags/%s.tres" % item_id):
		return true
	if item_id.begins_with("disk_"):
		return true
	return false


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


## Lookup item info from all registries. Returns {name: String, max_stack: int}
func _lookup_item(item_id: String) -> Dictionary:
	# ItemRegistry (general items)
	var item_data = ItemRegistry.get_item(item_id)
	if item_data:
		return {"name": item_data.name, "max_stack": item_data.max_stack if item_data.stackable else 1}

	# ConsumableRegistry
	var consumable = ConsumableRegistry.get_consumable(item_id)
	if consumable:
		var ms = int(consumable.max_stack) if int(consumable.max_stack) > 0 else 10
		return {"name": consumable.name, "max_stack": ms}

	# WeaponRegistry (non-stackable)
	var weapon = WeaponRegistry.get_weapon(item_id)
	if weapon:
		return {"name": weapon.name, "max_stack": 1}

	# ArmorRegistry (non-stackable)
	var armor = ArmorRegistry.get_armor(item_id)
	if armor:
		return {"name": armor.name, "max_stack": 1}

	# UnitRegistry (non-stackable)
	var unit = UnitRegistry.get_unit(item_id)
	if unit:
		return {"name": unit.name, "max_stack": 1}

	# MaterialRegistry (stackable materials)
	var material = MaterialRegistry.get_material(item_id)
	if material:
		return {"name": material.name, "max_stack": 99}

	# ModifierRegistry (grinders, elements)
	var modifier = ModifierRegistry.get_modifier(item_id)
	if modifier:
		return {"name": modifier.name, "max_stack": 99}

	# Technique disks (per-slot, format: disk_<tech_id>_<level>)
	if item_id.begins_with("disk_"):
		var parts: PackedStringArray = item_id.split("_", false, 2)
		if parts.size() >= 3:
			var tech_id: String = parts[1]
			var level: int = int(parts[2])
			var tech: Dictionary = TechniqueManager.TECHNIQUES.get(tech_id, {})
			var tech_name: String = str(tech.get("name", tech_id))
			return {"name": "Disk: %s Lv.%d" % [tech_name, level], "max_stack": 1}
		return {"name": item_id, "max_stack": 1}

	# Mags (load directly, no registry)
	var mag_path := "res://data/mags/%s.tres" % item_id
	if ResourceLoader.exists(mag_path):
		var mag = load(mag_path)
		if mag:
			return {"name": mag.name, "max_stack": 1}

	# Unknown item — allow with default stack
	return {"name": item_id, "max_stack": 10}


## Clear all items
func clear_inventory() -> void:
	_items.clear()
	_keys.clear()
	print("[Inventory] Cleared")


## Add a key (separate from main inventory, no capacity limit)
func add_key(key_id: String) -> void:
	_keys[key_id] = int(_keys.get(key_id, 0)) + 1
	print("[Inventory] Key collected: ", key_id)


## Check if a key is held
func has_key(key_id: String) -> bool:
	return _keys.has(key_id) and int(_keys[key_id]) > 0


## Remove a key (consumed when opening a gate)
func remove_key(key_id: String) -> void:
	if _keys.has(key_id):
		var remaining: int = int(_keys[key_id]) - 1
		if remaining <= 0:
			_keys.erase(key_id)
		else:
			_keys[key_id] = remaining
