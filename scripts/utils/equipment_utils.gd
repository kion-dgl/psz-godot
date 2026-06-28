class_name EquipmentUtils
## Shared equipment-slot compatibility check. Deduplicated from the identical
## `_item_fits_slot` in equipment_screen.gd (2D) and pso_start_menu.gd (3D) — #294.


## True if `item_id` can be equipped into `slot_key`.
## Slots: "weapon", "frame", "unit1".."unit4", "mag".
static func item_fits_slot(item_id: String, slot_key: String) -> bool:
	# Strip the per-slot instance suffix ("frame#2" → "frame") before any
	# registry lookup — buying multiples gives each copy a unique instance id,
	# but the registries only know the base id. Without this, every duplicate
	# past the first failed its slot check and showed as a tool (#357).
	var base_id: String = Inventory.get_base_id(item_id)
	match slot_key:
		"weapon":
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				return false
			var character = CharacterManager.get_active_character()
			if character:
				var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
				if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type) and not DebugConfig.equip_all:
					return false
			return true
		"frame":
			var armor = ArmorRegistry.get_armor(base_id)
			if armor == null:
				return false
			# Armor legality is a per-item class restriction (ArmorData.usable_by,
			# e.g. robe = Newman-Hunter/Force) — the legitimate, non-drifted data,
			# and the ONLY source of armor legality (ClassData has no armor analog).
			# Mirror the weapon branch: gate by the active class, bypassed by
			# DebugConfig.equip_all. Empty usable_by = no restriction (all classes).
			# Spec /mechanics/equip-legality.
			var character = CharacterManager.get_active_character()
			if character:
				var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
				if class_data and not armor.can_be_used_by("%s %s" % [class_data.type, class_data.race]) and not DebugConfig.equip_all:
					return false
			return true
		"unit1", "unit2", "unit3", "unit4":
			return UnitRegistry.get_unit(base_id) != null
		"mag":
			return MagManager.is_mag(base_id)
	return false


## How many unit slots an armor *instance* provides.
## Unit slots are a per-instance rolled property (0–4): the count is recorded in
## `character["armor_slots"]` keyed by the full instance id (e.g. "frame#2").
## Instances with no recorded roll (starter gear, legacy saves, non-shop sources)
## fall back to the armor resource's `max_slots`. See spec /mechanics/inventory.
static func get_unit_slot_count(instance_id: String, character) -> int:
	if instance_id.is_empty():
		return 0
	if character != null:
		var armor_slots: Dictionary = character.get("armor_slots", {})
		if armor_slots.has(instance_id):
			return clampi(int(armor_slots[instance_id]), 0, 4)
	var armor = ArmorRegistry.get_armor(Inventory.get_base_id(instance_id))
	if armor == null:
		return 0
	return clampi(int(armor.max_slots), 0, 4)
