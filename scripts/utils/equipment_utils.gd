class_name EquipmentUtils
## Shared equipment-slot compatibility check. Deduplicated from the identical
## `_item_fits_slot` in equipment_screen.gd (2D) and pso_start_menu.gd (3D) — #294.


## True if `item_id` can be equipped into `slot_key`.
## Slots: "weapon", "frame", "unit1".."unit4", "mag".
static func item_fits_slot(item_id: String, slot_key: String) -> bool:
	match slot_key:
		"weapon":
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				return false
			var character = CharacterManager.get_active_character()
			if character:
				var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
				if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
					return false
			return true
		"frame":
			return ArmorRegistry.has_armor(item_id)
		"unit1", "unit2", "unit3", "unit4":
			return UnitRegistry.get_unit(item_id) != null
		"mag":
			return MagManager.is_mag(item_id)
	return false
