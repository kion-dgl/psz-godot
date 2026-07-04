extends Node
## Player inventory system that stores ItemData references.
## Tracks item quantities and provides add/remove functionality.

## Item ordering: `_items` is a Dictionary which preserves insertion
## order in Godot 4, so by default items appear in pickup order. Players
## who prefer organized inventories can either:
##
##   - Open the start menu's inventory item modal → Sort → Auto for a
##     one-shot sort_in_place. Manual triggers a swap-mode pick to
##     re-order two rows by hand.
##   - Flip "Auto-Sort Inventory" in Options — every add_item then
##     re-sorts in place so newly-picked-up items file into their
##     category instead of appending at the end.
##
## Auto-sort is OFF by default for a PSO-authentic feel; it's stored
## per-character in `character.auto_sort_inventory`.

## Category sort order — used by sort_in_place() and by display layers
## that group items into sections. Centralized here so storage, start
## menu, etc. share one canonical order.
const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

## Maximum number of unique items (0 = unlimited)
@export var capacity: int = 40

## Dictionary of item_id -> quantity (insertion order = pickup order)
var _items: Dictionary = {}

## Separate key storage (field-scoped, doesn't count toward capacity)
var _keys: Dictionary = {}

## Counter for generating unique weapon instance IDs
var _instance_counter: int = 0

## Signals
signal item_added(item_id: String, quantity: int, total: int)
signal item_removed(item_id: String, quantity: int, remaining: int)
signal inventory_full()
## Emitted whenever the held-key total changes (pickup or gate consume) so the
## field key HUD can track keys IN HAND, not cumulative pickups.
signal keys_changed(total: int)


## Extract base item ID from an instance ID (e.g., "ein_saber#3" → "ein_saber")
func get_base_id(item_id: String) -> String:
	var idx: int = item_id.rfind("#")
	if idx >= 0:
		return item_id.substr(0, idx)
	return item_id


## Add a weapon to inventory with a unique instance ID.
## Returns the instance ID, or "" if inventory is full.
func add_weapon(base_id: String) -> String:
	return _add_per_slot_instance(base_id)


## Add an armor (frame) to inventory with a unique instance ID.
## Returns the instance ID, or "" if inventory is full. Callers that roll a
## per-instance unit-slot count record it against this returned id (see
## weapon_shop.gd / EquipmentUtils.get_unit_slot_count).
func add_armor(base_id: String) -> String:
	return _add_per_slot_instance(base_id)


## Mint a single per-slot item (weapon/armor) with a unique instance ID.
func _add_per_slot_instance(base_id: String) -> String:
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
	_maybe_auto_sort()
	return inst_id


## Returns true if the active character has auto-sort enabled. Default
## false (PSO-authentic).
func is_auto_sort() -> bool:
	var ch = CharacterManager.get_active_character()
	if ch == null:
		return false
	return bool(ch.get("auto_sort_inventory", false))


## Toggle auto-sort for the active character. Persists with the character
## save (CharacterManager serializes the whole dict). When flipped on,
## the inventory is sorted immediately so the player sees the effect.
func set_auto_sort(value: bool) -> void:
	var ch = CharacterManager.get_active_character()
	if ch == null:
		return
	ch["auto_sort_inventory"] = value
	if value:
		sort_in_place()


func _maybe_auto_sort() -> void:
	if is_auto_sort():
		sort_in_place()


## Move an item to a specific position in the inventory order. Used by
## the start menu's Manual sort (Inventory item modal → Sort → Manual):
## the player picks a destination row and the originally selected item
## moves there, with everything else shifting around it. One-shot — does
## not persist any per-character ordering hint, the new positions just
## live in the Dictionary's insertion order until something else
## re-orders.
##
## target_idx is the visual destination in the *current* item list — i.e.
## what the player's cursor was on when they pressed Accept. Out-of-range
## targets are clamped. Rebuilds the Dictionary in place using the same
## trick as sort_in_place() so the order change shows up in
## get_all_items().
func move_item(item_id: String, target_idx: int) -> void:
	if not _items.has(item_id):
		return
	var ids: Array = _items.keys()
	var current_idx: int = ids.find(item_id)
	if current_idx < 0:
		return
	# Clamp target to valid visual range first (0..size-1), then remove
	# the moved id and reinsert at the same numeric index. Because the
	# array shrank by one, that lands the moved item at the visual
	# position the player pointed at — items shift around it as expected.
	var clamped: int = clampi(target_idx, 0, ids.size() - 1)
	if clamped == current_idx:
		return
	ids.remove_at(current_idx)
	# After remove the array is one shorter; clamped is still within
	# valid insert range (0..ids.size()).
	clamped = clampi(clamped, 0, ids.size())
	ids.insert(clamped, item_id)
	var rebuilt: Dictionary = {}
	for id in ids:
		rebuilt[id] = _items[id]
	_items = rebuilt


## Re-arrange `_items` so iteration order is category-then-name. Mutates
## the Dictionary in place by rebuilding it in sorted order — Godot 4's
## Dictionary preserves insertion order, so the canonical "rebuild" trick
## is to copy out, sort, then re-insert.
func sort_in_place() -> void:
	var ids: Array = _items.keys()
	ids.sort_custom(func(a, b):
		var ca: int = CATEGORY_ORDER.find(get_item_category(a))
		var cb: int = CATEGORY_ORDER.find(get_item_category(b))
		if ca == -1: ca = 99
		if cb == -1: cb = 99
		if ca != cb:
			return ca < cb
		var na: String = str(_lookup_item(a).name)
		var nb: String = str(_lookup_item(b).name)
		return na < nb
	)
	var rebuilt: Dictionary = {}
	for id in ids:
		rebuilt[id] = _items[id]
	_items = rebuilt


## Canonical category for an item id. Centralized here so all display
## layers (storage, start menu, inventory_screen) agree on what's a
## Weapon vs Armor vs Mag etc.
func get_item_category(item_id: String) -> String:
	# Strip the per-slot instance suffix ("frame#2" → "frame") before every
	# registry lookup so duplicates of equippable gear categorize as their
	# real type rather than falling through to "Other"/tool (#357 — same root
	# cause as item_fits_slot).
	var base_id: String = get_base_id(item_id)
	var norm_id: String = base_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(base_id) or WeaponRegistry.get_weapon(norm_id):
		return "Weapon"
	if ArmorRegistry.get_armor(base_id) or ArmorRegistry.get_armor(norm_id):
		return "Armor"
	if UnitRegistry.get_unit(base_id) or UnitRegistry.get_unit(norm_id):
		return "Unit"
	if MagManager.is_mag(base_id) or MagManager.is_mag(norm_id):
		return "Mag"
	if base_id.begins_with("disk_"):
		return "Disk"
	if ConsumableRegistry.get_consumable(base_id) or ConsumableRegistry.get_consumable(norm_id):
		return "Consumable"
	if CombatManager.MATERIAL_STAT_MAP.has(base_id) or MaterialRegistry.get_material(base_id):
		return "Material"
	if ModifierRegistry.get_modifier(base_id) or ModifierRegistry.get_modifier(norm_id):
		return "Modifier"
	var item_data = ItemRegistry.get_item(base_id)
	if item_data == null:
		item_data = ItemRegistry.get_item(norm_id)
	if item_data:
		return "Key Item"
	return "Other"


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
		_maybe_auto_sort()
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
		_maybe_auto_sort()
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


## Maximum stack size for an item id. Per-slot items always return 1.
## Used by the shop UI's quantity picker to clamp the qty selector.
func get_max_stack(item_id: String) -> int:
	if _is_per_slot(item_id):
		return 1
	return int(_lookup_item(item_id).max_stack)


## How many more of this item the player can pick up right now: clamped by
## the existing stack's max_stack for stackables (max_stack - current count),
## or by free slot count for per-slot items. Used by the shop UI to cap a
## bulk-buy at "what would actually fit" rather than letting the user select
## a quantity that Inventory.add_item will silently clamp.
func get_stack_room(item_id: String) -> int:
	if _is_per_slot(item_id):
		if capacity <= 0:
			return 999
		return maxi(0, capacity - get_total_slots())
	var max_stack: int = get_max_stack(item_id)
	var current: int = int(_items.get(item_id, 0))
	# A stackable item that's not yet in inventory needs a free slot too.
	if current == 0 and capacity > 0 and get_total_slots() >= capacity:
		return 0
	return maxi(0, max_stack - current)


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
	"sol_atomizer": {"type": "hp", "percent": 1.00},
	"moon_atomizer": {"type": "hp", "percent": 1.00},
	"star_atomizer": {"type": "hp", "percent": 1.00},
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
	# Parse tech/level from the BASE id, never the raw instance id. A duplicate
	# disk is minted as "disk_foie_3#2"; parsing the raw id makes int("3#2")
	# yield 32 (Godot int() concatenates digits across '#', it does not
	# truncate), so use_disk() rejects every copy past the first as "level 32 >
	# class max". Strip the suffix first, but keep the full instance id for the
	# remove_item below so the exact copy the player selected is consumed
	# (#417, mirrors the #357 get_base_id-before-lookup pattern).
	var base_id := get_base_id(item_id)
	# Strip "disk_" prefix, then split off the trailing _<level>
	var rest := base_id.substr(5)
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
	keys_changed.emit(get_total_keys())


## Check if a key is held
func has_key(key_id: String) -> bool:
	return _keys.has(key_id) and int(_keys[key_id]) > 0


## Get key count for a specific key ID
func get_key_count(key_id: String) -> int:
	return int(_keys.get(key_id, 0))


## Total keys currently held across all key IDs — the count the field HUD
## shows (decrements as gates consume keys).
func get_total_keys() -> int:
	var total := 0
	for k in _keys:
		total += int(_keys[k])
	return total


## Remove a key (consumed when opening a gate)
func remove_key(key_id: String) -> void:
	if _keys.has(key_id):
		var remaining: int = int(_keys[key_id]) - 1
		if remaining <= 0:
			_keys.erase(key_id)
		else:
			_keys[key_id] = remaining
		keys_changed.emit(get_total_keys())


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
