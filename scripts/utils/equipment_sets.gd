extends RefCounted
## Character-owned references, not snapshots of mutable item stats.
const SLOTS := ["weapon", "frame", "mag", "unit1", "unit2", "unit3", "unit4"]
const LIMIT := 8
const Instance := preload("res://scripts/utils/equipment_instance.gd")

static func owner(ch: Dictionary) -> String:
	if not ch.has("equipment_owner"):
		ch.equipment_owner = Crypto.new().generate_random_bytes(16).hex_encode()
	return str(ch.equipment_owner)

static func list_sets() -> Array:
	var ch = CharacterManager.get_active_character()
	return ch.get("equipment_sets", []) if ch != null else []

static func result(ok: bool, message: String) -> Dictionary:
	return {"success": ok, "message": message}

static func save_set(label: String, index: int = -1) -> Dictionary:
	var ch = CharacterManager.get_active_character()
	label = label.strip_edges().left(32)
	if ch == null or label.is_empty(): return result(false, "Enter a set name.")
	var sets := list_sets().duplicate(true)
	if index < -1 or index >= sets.size(): return result(false, "Set no longer exists.")
	if index == -1 and sets.size() >= LIMIT: return result(false, "All eight slots are occupied.")
	var identities := {}
	for id in ch.get("equipment", {}).values():
		if not str(id).is_empty(): identities[id] = Instance.identity(ch, id)
	var entry := {"version": 1, "owner": owner(ch), "name": label,
		"equipment": ch.get("equipment", {}).duplicate(true), "order": Inventory._items.keys(), "identities": identities}
	if index == -1: sets.append(entry)
	else: sets[index] = entry
	ch.equipment_sets = sets
	return result(true, "Saved %s." % label)

static func rename_set(index: int, label: String) -> Dictionary:
	label = label.strip_edges().left(32)
	var sets := list_sets()
	if index < 0 or index >= sets.size() or label.is_empty(): return result(false, "Enter a valid set name.")
	sets[index].name = label
	return result(true, "Renamed %s." % label)

static func delete_set(index: int) -> Dictionary:
	var sets := list_sets()
	if index < 0 or index >= sets.size(): return result(false, "Set no longer exists.")
	sets.remove_at(index)
	return result(true, "Set deleted; equipment retained.")

static func recall(index: int) -> Dictionary:
	var ch = CharacterManager.get_active_character()
	var sets := list_sets()
	if ch == null or index < 0 or index >= sets.size(): return result(false, "Set no longer exists.")
	var entry: Dictionary = sets[index]
	if int(entry.get("version", 0)) != 1 or entry.get("owner", "") != owner(ch):
		return result(false, "This set belongs to a different character or version.")
	var plan := _plan(ch, entry)
	if not plan.success: return plan
	var equip: Dictionary = plan.equipment
	var staged: Dictionary = plan.character
	var held: Dictionary = plan.held
	var bank: Array = plan.bank
	# Commit only after all validation succeeds; no item acquisition/reminting.
	GameState.shared_storage = bank
	Inventory.restore_items(held, entry.get("order", []))
	for field in preload("res://scripts/utils/equipment_instance.gd").FIELDS:
		ch[field] = staged.get(field, {})
	ch.equipment = equip
	CharacterManager.sync_inventory_to_active()
	return result(true, "Recalled %s." % str(entry.get("name", "set")))

static func _plan(ch: Dictionary, entry: Dictionary) -> Dictionary:
	var equip: Dictionary = entry.get("equipment", {}).duplicate(true)
	var held := Inventory._items.duplicate()
	var bank := GameState.shared_storage.duplicate(true)
	var used: Array = []
	var staged: Dictionary = ch.duplicate(true)
	for slot in SLOTS:
		var id := str(equip.get(slot, ""))
		equip[slot] = id
		if id.is_empty(): continue
		if id in used or not EquipmentUtils.item_fits_slot(id, slot):
			return result(false, "Invalid equipment in %s." % slot)
		used.append(id)
		if int(held.get(id, 0)) > 0:
			if str(ch.get("equipment_tokens", {}).get(id, "")) != entry.get("identities", {}).get(id, ""):
				return result(false, "The original %s is no longer carried." % id)
			continue
		var transfer := _retrieve(ch, staged, held, bank, id)
		if not transfer.success: return transfer
		if str(staged.get("equipment_tokens", {}).get(id, "")) != entry.get("identities", {}).get(id, ""):
			return result(false, "The original %s is no longer stored." % id)

	for n in range(1, 5):
		if not str(equip.get("unit%d" % n, "")).is_empty() and n > EquipmentUtils.get_unit_slot_count(str(equip.frame), staged):
			return result(false, "The saved frame no longer has enough unit slots.")
	if Inventory.capacity > 0 and Inventory.count_slots(held) > Inventory.capacity:
		return result(false, "Not enough inventory space for stored equipment.")
	return {"success": true, "equipment": equip, "character": staged, "held": held, "bank": bank}

static func _retrieve(ch: Dictionary, staged: Dictionary, held: Dictionary, bank: Array, id: String) -> Dictionary:
	var matches := bank.filter(func(item): return item.get("id", "") == id and item.get("owner", "") == owner(ch))
	if matches.size() != 1 or int(matches[0].get("quantity", 0)) != 1:
		return result(false, "Missing %s. Legacy stored gear must be withdrawn manually." % id)
	if matches[0].has("properties"):
		preload("res://scripts/utils/equipment_instance.gd").restore(staged, id, matches[0].properties)
	held[id] = 1
	bank.erase(matches[0])
	return result(true, "")
