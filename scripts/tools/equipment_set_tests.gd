extends RefCounted
const Sets = preload("res://scripts/utils/equipment_sets.gd")

static func run(t: Node) -> void:
	var saved_chars = CharacterManager.get_save_data()
	var saved_slot = CharacterManager._active_slot
	var saved_inv = Inventory._items.duplicate(true)
	var saved_bank = GameState.shared_storage.duplicate(true)
	var capacity = Inventory.capacity
	CharacterManager._active_slot = -1
	CharacterManager._characters.resize(20)
	CharacterManager._characters[19] = null
	var ch = CharacterManager.create_character(19, "humar", "Loadout test")
	CharacterManager.set_active_slot(19)
	GameState.shared_storage = []
	_transactions(t, ch)
	ch = CharacterManager.get_active_character()
	_boundaries(t, ch)
	_full_equipment(t, ch)
	CharacterManager._characters = saved_chars
	CharacterManager._active_slot = saved_slot
	Inventory._items = saved_inv
	GameState.shared_storage = saved_bank
	Inventory.capacity = capacity
	CharacterManager._sync_to_game_state()

static func _transactions(t: Node, ch: Dictionary) -> void:
	var capacity := Inventory.capacity
	ch.weapon_grinds.saber = 4
	t.assert_true(Sets.save_set("First").success, "save named equipment set")
	ch.equipment.weapon = ""
	GameState.shared_storage.append({"id": "saber", "quantity": 1, "owner": Sets.owner(ch)})
	Inventory.remove_item("saber")
	var other = Inventory.add_weapon("saber")
	t.assert_true(other != "saber", "banked and saved instance IDs cannot be reused")
	t.assert_true(Sets.recall(0).success, "recall retrieves exact banked weapon")
	t.assert_eq(ch.equipment.weapon, "saber", "recall exact instance")
	t.assert_eq(ch.weapon_grinds.saber, 4, "recall preserves current grind")
	t.assert_true(GameState.shared_storage.is_empty(), "withdraw exactly once")
	t.assert_eq(Inventory._items.keys()[0], "saber", "restore saved inventory order")
	ch.weapon_grinds.saber = 6
	t.assert_true(Sets.recall(0).success, "repeat recall succeeds")
	t.assert_eq(ch.weapon_grinds.saber, 6, "set does not roll back upgrades")
	Inventory.remove_item("saber")
	var before = ch.equipment.duplicate(true)
	t.assert_true(not Sets.recall(0).success, "missing item refuses whole set")
	t.assert_eq(ch.equipment, before, "failed recall leaves equipment unchanged")
	GameState.shared_storage.append({"id": "saber", "quantity": 1, "owner": "someone-else"})
	t.assert_true(not Sets.recall(0).success, "cannot steal another character's matching ID")
	GameState.shared_storage[0].owner = Sets.owner(ch)
	Inventory.capacity = Inventory.get_total_slots()
	t.assert_true(not Sets.recall(0).success, "full inventory refuses transaction")
	t.assert_eq(GameState.shared_storage.size(), 1, "failure preserves bank")
	Inventory.capacity = capacity
	t.assert_true(Sets.recall(0).success, "recall after freeing capacity")
	t.assert_true(Sets.rename_set(0, "Field").success, "rename set")
	var persisted = JSON.parse_string(JSON.stringify(CharacterManager.get_save_data()))
	CharacterManager.load_from_save(persisted)
	ch = CharacterManager.get_active_character()
	t.assert_eq(ch.equipment_sets[0].name, "Field", "schema survives save serialization")
	t.assert_true(Sets.recall(0).success, "serialized schema recalls")
	ch.equipment_sets[0].equipment.unit1 = "mag"
	t.assert_true(not Sets.recall(0).success, "wrong category/duplicate reference rejected")
	t.assert_true(Sets.delete_set(0).success, "delete set")
	t.assert_true(ch.equipment_sets.is_empty(), "deletion affects only set")

static func _boundaries(t: Node, ch: Dictionary) -> void:
	var original_token = ch.equipment_tokens.saber
	t.assert_true(Sets.save_set("Identity").success, "save identity fixture")
	ch.equipment_tokens.saber = "different-physical-item"
	t.assert_true(not Sets.recall(0).success, "same legacy ID from another character is not original gear")
	ch.equipment_tokens.saber = original_token
	for index in 7: t.assert_true(Sets.save_set("Set %d" % index).success, "remaining slots can be saved")
	t.assert_true(not Sets.save_set("Ninth").success, "ninth set refused")
	t.assert_true(not Sets.rename_set(0, "   ").success, "empty name refused")
	t.assert_true(Sets.save_set("Replacement", 0).success, "replacement allowed when full")
	t.assert_eq(Sets.list_sets().size(), 8, "replacement does not append")
	var new_gear = Inventory.add_weapon("sword")
	ch.weapon_grinds[new_gear] = 7
	var properties = preload("res://scripts/utils/equipment_instance.gd").capture(ch, new_gear)
	var receiver = {"weapon_grinds": {new_gear: 99}}
	preload("res://scripts/utils/equipment_instance.gd").restore(receiver, new_gear, properties)
	t.assert_eq(receiver.weapon_grinds[new_gear], 7, "bank transfer carries original grind to another character")
	t.assert_eq(receiver.equipment_tokens[new_gear], ch.equipment_tokens[new_gear], "bank transfer retains physical identity")
	var old_level = ch.level
	ch.level = 100
	var progress = CharacterManager.get_exp_progress()
	t.assert_true(progress.maxed and progress.percent == 1.0, "max-level EXP is a full bar without division by zero")
	ch.level = old_level

static func _full_equipment(t: Node, ch: Dictionary) -> void:
	Inventory.add_item("ace_hp")
	ch.equipment.unit1 = "ace_hp"
	ch.armor_slots.normal_frame = 1
	ch.mag_states.mag.stats.power = 23
	t.assert_true(Sets.save_set("Full gear", 0).success, "save frame, unit and Mag configuration")
	ch.equipment.unit1 = ""
	t.assert_true(Sets.recall(0).success, "recall restores attached unit")
	t.assert_eq(ch.equipment.unit1, "ace_hp", "correct unit occupies correct slot")
	t.assert_eq(ch.mag_states.mag.stats.power, 23, "Mag progression retained")
	ch.armor_slots.normal_frame = 0
	var carried = Inventory._items.duplicate(true)
	var equipped = ch.equipment.duplicate(true)
	t.assert_true(not Sets.recall(0).success, "frame slot loss rejects full set")
	t.assert_eq(Inventory._items, carried, "slot rejection leaves inventory intact")
	t.assert_eq(ch.equipment, equipped, "slot rejection leaves equipment intact")
	ch.armor_slots.normal_frame = 1
	ch.equipment_sets[0].equipment.unit2 = "ace_hp"
	t.assert_true(not Sets.recall(0).success, "one unit cannot fill two slots")
	ch.equipment_sets[0].equipment.unit2 = ""
	var class_id = ch.class_id
	ch.class_id = "fomar"
	ch.equipment_sets[0].equipment.weapon = "sword"
	t.assert_true(not Sets.recall(0).success, "recall respects class weapon eligibility")
	ch.class_id = class_id
