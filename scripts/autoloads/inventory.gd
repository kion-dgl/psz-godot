extends Node
## Player inventory system that stores ItemData references.
## Tracks item quantities and provides add/remove functionality.

## Maximum number of unique items (0 = unlimited)
@export var capacity: int = 40

## Dictionary of item_id -> quantity
var _items: Dictionary = {}

## Separate key storage (field-scoped, doesn't count toward capacity)
var _keys: Dictionary = {}

## Counter for generating unique weapon instance IDs
var _instance_counter: int = 0

## Signals
signal item_added(item_id: String, quantity: int, total: int)
signal item_removed(item_id: String, quantity: int, remaining: int)
signal inventory_full()


## Extract base item ID from an instance ID (e.g., "ein_blade#3" → "ein_blade")
func get_base_id(item_id: String) -> String:
	var idx: int = item_id.rfind("#")
	if idx >= 0:
		return item_id.substr(0, idx)
	return item_id


## Add a weapon to inventory with a unique instance ID.
## Returns the instance ID, or "" if inventory is full.
func add_weapon(base_id: String) -> String:
	if capacity > 0 and get_total_slots() >= capacity:
		inventory_full.emit()
		SfxManager.play("res://assets/sfx/common/common_022.wav")
		return ""
	var inst_id: String = base_id
	while _items.has(inst_id):
		_instance_counter += 1
		inst_id = "%s#%d" % [base_id, _instance_counter]
	_items[inst_id] = 1
	var info = _lookup_item(inst_id)
	item_added.emit(inst_id, 1, 1)
	print("[Inventory] Added 1x ", info.name, " (", inst_id, ")")
	return inst_id


## Add an item to inventory by ID
## Returns true if item was added successfully
func add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var info = _lookup_item(item_id)
	var item_name: String = info.name

	if _is_per_slot(item_id):
		# Per-slot items: each copy gets a unique instance ID
		var available: int = capacity - get_total_slots() if capacity > 0 else quantity
		var max_add: int = mini(quantity, available)
		if max_add <= 0:
			inventory_full.emit()
			SfxManager.play("res://assets/sfx/common/common_022.wav")
			return false
		var base_id: String = get_base_id(item_id)
		for _i in range(max_add):
			var inst_id: String = base_id
			while _items.has(inst_id):
				_instance_counter += 1
				inst_id = "%s#%d" % [base_id, _instance_counter]
			_items[inst_id] = 1
		print("[Inventory] Added ", max_add, "x ", item_name)
		item_added.emit(item_id, max_add, max_add)
		return true
	else:
		# Stackable items: 1 stack = 1 slot, limited by max_stack
		if capacity > 0 and not has_item(item_id) and get_total_slots() >= capacity:
			inventory_full.emit()
			SfxManager.play("res://assets/sfx/common/common_022.wav")
			return false
		var max_stack: int = info.max_stack
		var current: int = int(_items.get(item_id, 0))
		var max_add: int = mini(quantity, max_stack - current)
		if max_add <= 0:
			# Stack already at max_stack — same UX as capacity-full.
			inventory_full.emit()
			SfxManager.play("res://assets/sfx/common/common_022.wav")
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
	var base_id: String = get_base_id(item_id)
	var norm_id: String = base_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(base_id) or WeaponRegistry.get_weapon(norm_id):
		return true
	if ArmorRegistry.get_armor(base_id) or ArmorRegistry.get_armor(norm_id):
		return true
	if UnitRegistry.get_unit(base_id) or UnitRegistry.get_unit(norm_id):
		return true
	if MagManager.is_mag(base_id):
		return true
	if base_id.begins_with("disk_"):
		return true
	return false


## Consumable effects — percentage of max HP or max PP restored
const CONSUMABLE_EFFECTS := {
	"monomate": {"type": "hp", "percent": 0.30},
	"dimate": {"type": "hp", "percent": 0.60},
	"trimate": {"type": "hp", "percent": 1.00},
	"monofluid": {"type": "pp", "percent": 0.30},
	"difluid": {"type": "pp", "percent": 0.60},
	"trifluid": {"type": "pp", "percent": 1.00},
}


## Use a consumable item (removes it and applies effect)
## Returns a dict: {success: bool, type: String, amount: int} or {success: false}
func use_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false

	# Technique disks: parse disk_<tech>_<level> and route to TechniqueManager
	if item_id.begins_with("disk_"):
		return _use_disk(item_id)

	# Telepipe — drops a portable city-warp at the player's current position.
	# Field-only; no effect in city / on title screen. Doesn't auto-travel; the
	# player still has to walk into the spawned Telepipe and press accept.
	if item_id == "telepipe":
		return _use_telepipe()

	var effect: Dictionary = CONSUMABLE_EFFECTS.get(item_id, {})
	if effect.is_empty():
		# Not a known consumable — try legacy path for other usable items
		var item_data = ItemRegistry.get_item(item_id)
		if item_data and item_data.type == 2:
			remove_item(item_id, 1)
			return true
		return false

	var effect_type: String = str(effect.get("type", ""))
	var percent: float = float(effect.get("percent", 0))

	if effect_type == "hp":
		if GameState.hp >= GameState.max_hp:
			return false  # Already full
		var amount: int = int(float(GameState.max_hp) * percent)
		GameState.heal(amount)
		_last_use_type = "hp"
		_last_use_amount = amount
	elif effect_type == "pp":
		if GameState.mp >= GameState.max_mp:
			return false  # Already full
		var amount: int = int(float(GameState.max_mp) * percent)
		GameState.restore_mp(amount)
		_last_use_type = "pp"
		_last_use_amount = amount
	else:
		return false

	remove_item(item_id, 1)
	print("[Inventory] Used %s: +%d %s" % [item_id, _last_use_amount, _last_use_type.to_upper()])
	return true


## Drop a telepipe at the player's current world position. Field-only; no
## effect in the city or on the title screen. Doesn't transport the player —
## it spawns the cyan Telepipe element where the player is standing, and the
## player has to step into it and press accept to actually warp.
##
## The TelepipeManager handles the once-active rule (dropping a new telepipe
## while one is already active automatically cancels the old one) so this
## function just needs to find the field controller and let it spawn.
func _use_telepipe() -> bool:
	if SessionManager.get_location() != "field":
		_last_use_type = "telepipe_fail"
		_last_use_amount = 0
		print("[Inventory] Telepipe rejected: not in a field (location=%s)"
			% SessionManager.get_location())
		return false
	var field_ctrl = get_tree().get_first_node_in_group("field_controller")
	if field_ctrl == null or not field_ctrl.has_method("spawn_player_telepipe"):
		# Field scenes register themselves in the "field_controller" group on
		# _ready. If we can't find one, refuse rather than consume the item.
		_last_use_type = "telepipe_fail"
		_last_use_amount = 0
		print("[Inventory] Telepipe rejected: no field controller in scene")
		return false
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		_last_use_type = "telepipe_fail"
		_last_use_amount = 0
		print("[Inventory] Telepipe rejected: no player in scene")
		return false
	field_ctrl.spawn_player_telepipe(player.global_position)
	remove_item("telepipe", 1)
	_last_use_type = "telepipe"
	_last_use_amount = 1
	print("[Inventory] Used telepipe at %s" % player.global_position)
	return true


## Use a technique disk to learn or upgrade a tech.
## Disk id format: disk_<technique_id>_<level>, e.g. "disk_foie_3"
func _use_disk(item_id: String) -> bool:
	# Strip "disk_" prefix, then split off the trailing _<level>
	var rest := item_id.substr(5)
	var underscore := rest.rfind("_")
	if underscore < 0:
		return false
	var technique_id := rest.substr(0, underscore)
	var level := int(rest.substr(underscore + 1))
	if technique_id.is_empty() or level <= 0:
		return false

	var character = CharacterManager.get_active_character()
	if character == null:
		return false

	var disk: Dictionary = {"technique_id": technique_id, "level": level}
	var result: Dictionary = TechniqueManager.use_disk(character, disk)
	if not result.get("success", false):
		_last_use_type = "tech_fail"
		_last_use_amount = 0
		print("[Inventory] Disk %s failed: %s" % [item_id, str(result.get("message", ""))])
		return false

	# TechniqueManager.use_disk() mutates the character dict in place,
	# so the change persists for the rest of the session. SaveManager
	# will pick it up on the next auto-save.
	remove_item(item_id, 1)
	_last_use_type = "tech"
	_last_use_amount = int(result.get("new_level", level))
	print("[Inventory] %s" % str(result.get("message", "")))
	return true


## Last use info — read by player for visual feedback
var _last_use_type: String = ""
var _last_use_amount: int = 0

func get_last_use_info() -> Dictionary:
	return {"type": _last_use_type, "amount": _last_use_amount}


## Lookup item info from all registries. Returns {name: String, max_stack: int}
func _lookup_item(item_id: String) -> Dictionary:
	var base_id: String = get_base_id(item_id)

	# ItemRegistry (general items)
	var item_data = ItemRegistry.get_item(base_id)
	if item_data:
		return {"name": item_data.name, "max_stack": item_data.max_stack if item_data.stackable else 1}

	# ConsumableRegistry
	var consumable = ConsumableRegistry.get_consumable(base_id)
	if consumable:
		var ms = int(consumable.max_stack) if int(consumable.max_stack) > 0 else 10
		return {"name": consumable.name, "max_stack": ms}

	# WeaponRegistry (non-stackable) — use base_id for registry, item_id for per-instance data
	var weapon = WeaponRegistry.get_weapon(base_id)
	if weapon == null:
		var norm_base: String = base_id.replace("-", "_").replace("/", "_")
		weapon = WeaponRegistry.get_weapon(norm_base)
	if weapon:
		var display_name: String = weapon.name
		var character = CharacterManager.get_active_character()
		if character:
			# Use special prefix (e.g. "Heat", "Freeze") if available
			var special: Dictionary = character.get("weapon_specials", {}).get(item_id, {})
			if not special.is_empty():
				var prefix: String = str(special.get("prefix", ""))
				if not prefix.is_empty():
					display_name = prefix + " " + display_name
			else:
				# Fallback to old photon display name
				var photon_id: String = character.get("weapon_elements", {}).get(item_id, "")
				if not photon_id.is_empty():
					var element_prefix: String = _photon_display_name(photon_id)
					if not element_prefix.is_empty():
						display_name = element_prefix + " " + display_name
		return {"name": display_name, "max_stack": 1}

	# ArmorRegistry (non-stackable)
	var armor = ArmorRegistry.get_armor(base_id)
	if armor:
		return {"name": armor.name, "max_stack": 1}

	# UnitRegistry (non-stackable)
	var unit = UnitRegistry.get_unit(base_id)
	if unit:
		return {"name": unit.name, "max_stack": 1}

	# MaterialRegistry (stackable materials)
	var material = MaterialRegistry.get_material(base_id)
	if material:
		return {"name": material.name, "max_stack": 99}

	# ModifierRegistry (grinders, elements)
	var modifier = ModifierRegistry.get_modifier(base_id)
	if modifier:
		return {"name": modifier.name, "max_stack": 99}

	# RecipeRegistry (recipe boards, stackable)
	var recipe = RecipeRegistry.get_recipe(base_id)
	if recipe:
		return {"name": recipe.name, "max_stack": 99}

	# Debug mag feed items (stackable consumables)
	if base_id.begins_with("debug_mag_"):
		var debug_names := {
			"debug_mag_power": "Mag POW +50",
			"debug_mag_guard": "Mag GRD +50",
			"debug_mag_hit": "Mag HIT +50",
			"debug_mag_mind": "Mag MND +50",
		}
		return {"name": debug_names.get(base_id, base_id), "max_stack": 10}

	# Technique disks (per-slot, format: disk_<tech_id>_<level>)
	if base_id.begins_with("disk_"):
		var parts: PackedStringArray = base_id.split("_", false, 2)
		if parts.size() >= 3:
			var tech_id: String = parts[1]
			var level: int = int(parts[2])
			var tech: Dictionary = TechniqueManager.TECHNIQUES.get(tech_id, {})
			var tech_name: String = str(tech.get("name", tech_id))
			return {"name": "Disk: %s Lv.%d" % [tech_name, level], "max_stack": 1}
		return {"name": base_id, "max_stack": 1}

	# Mags — show current form name from mag_state if available
	if MagManager.is_mag(base_id):
		var character = CharacterManager.get_active_character()
		if character:
			var display_name: String = MagManager.get_mag_display_name(character, item_id)
			return {"name": display_name, "max_stack": 1}
		var form = MagManager.get_mag_form(base_id)
		if form:
			return {"name": form.name, "max_stack": 1}
		return {"name": base_id, "max_stack": 1}

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


## Get key count for a specific key ID
func get_key_count(key_id: String) -> int:
	return int(_keys.get(key_id, 0))


## Remove a key (consumed when opening a gate)
func remove_key(key_id: String) -> void:
	if _keys.has(key_id):
		var remaining: int = int(_keys[key_id]) - 1
		if remaining <= 0:
			_keys.erase(key_id)
		else:
			_keys[key_id] = remaining


## Get display name prefix for a photon element
func _photon_display_name(photon_id: String) -> String:
	match photon_id:
		"ban_photon": return "Ban"
		"ray_photon": return "Ray"
		"zon_photon": return "Zon"
		"megi_photon": return "Megi"
		"gra_photon": return "Gra"
		# Legacy fallback
		"fire_photon": return "Fire"
		"ice_photon": return "Ice"
		"poison_photon": return "Poison"
		"shock_photon": return "Shock"
		"devil_photon": return "Devil"
	return ""
