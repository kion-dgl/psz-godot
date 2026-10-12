extends RefCounted
## One transaction shared by the Tekker UI and live probe. Existing economy retained.
const GRINDER_FOR_RARITY := {1: "monogrinder", 2: "monogrinder", 3: "monogrinder", 4: "digrinder", 5: "digrinder", 6: "trigrinder", 7: "trigrinder"}
const GRIND_AMOUNT := {"monogrinder": 1, "digrinder": 2, "trigrinder": 3}
const RARITY_COST_MULT := {1: 1.0, 2: 1.5, 3: 2.0, 4: 3.0, 5: 4.0, 6: 6.0, 7: 10.0}

static func quote(instance_id: String) -> Dictionary:
	var ch = CharacterManager.get_active_character()
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(instance_id))
	if ch == null or weapon == null or not Inventory.has_item(instance_id):
		return {"success": false, "message": "Weapon is no longer in inventory."}
	var grind: int = int(ch.get("weapon_grinds", {}).get(instance_id, 0))
	if grind < 0 or grind >= weapon.max_grind:
		return {"success": false, "message": "Weapon is at its grind limit."}
	if weapon.get_attack_at_grind(grind + 1) <= weapon.get_attack_at_grind(grind):
		return {"success": false, "message": "This weapon has no supported grind bonus yet."}
	return {"success": true, "grind": grind, "name": weapon.name,
		"grinder": GRINDER_FOR_RARITY.get(weapon.rarity, "monogrinder"),
		"cost": int((200 + grind * 100) * RARITY_COST_MULT.get(weapon.rarity, 1.0))}

static func apply(instance_id: String) -> Dictionary:
	var q := quote(instance_id)
	if not q.success:
		return q
	if not Inventory.has_item(q.grinder):
		return {"success": false, "message": "Need a %s." % str(q.grinder).capitalize()}
	if GameState.meseta < int(q.cost):
		return {"success": false, "message": "Need %d meseta." % int(q.cost)}
	# No yields or callbacks between validation and committing the upgrade.
	var ch = CharacterManager.get_active_character()
	if not ch.has("weapon_grinds"):
		ch.weapon_grinds = {}
	ch.weapon_grinds[instance_id] = int(q.grind) + 1
	GameState.meseta -= int(q.cost)
	ch.meseta = GameState.meseta
	Inventory.remove_item(q.grinder, 1)
	return {"success": true, "message": "%s +%d (-%d M)" % [q.name, int(q.grind) + 1, int(q.cost)]}

## Inventory grinders apply directly to the equipped instance without a shop fee.
static func equipped_quote(grinder_id: String) -> Dictionary:
	var tiers := {"monogrinder": 3, "digrinder": 5, "trigrinder": 7}
	var ch = CharacterManager.get_active_character()
	if ch == null or not tiers.has(grinder_id) or not Inventory.has_item(grinder_id):
		return {"success": false}
	var instance_id: String = str(ch.get("equipment", {}).get("weapon", ""))
	var q := quote(instance_id)
	if not q.success:
		return q
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(instance_id))
	if weapon.rarity > int(tiers[grinder_id]):
		return {"success": false, "message": "Grinder tier is too low."}
	q["instance_id"] = instance_id
	q["next_grind"] = mini(weapon.max_grind, int(q.grind) + int(GRIND_AMOUNT[grinder_id]))
	return q

static func use_equipped(grinder_id: String) -> bool:
	var q := equipped_quote(grinder_id)
	if not q.success:
		return false
	var ch = CharacterManager.get_active_character()
	if not ch.has("weapon_grinds"):
		ch.weapon_grinds = {}
	ch.weapon_grinds[q.instance_id] = int(q.next_grind)
	Inventory.remove_item(grinder_id, 1)
	return true
