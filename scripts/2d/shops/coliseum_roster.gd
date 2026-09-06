class_name ColiseumRoster
## Pure logic for the Coliseum Master debug lab (#629 follow-up): the synthesized
## 1:1 arena sections and the roster listing the picker renders. Kept static +
## node-free (the EnemyAttackLogic pattern) so test_runner can pin it directly
## without pulling the shop UI into its compile chain.

## The 1:1 arena cell: one chosen enemy + a telepipe home on room clear. Same shape
## as data/quests/debug_coliseum.json's section (stage s00a_nr2, city area), so the
## field controller, spawner, and quest-complete flow all take their normal paths.
static func make_sections(enemy_id: String) -> Array:
	return [{
		"type": "grid", "area": "a", "area_id": "city",
		"start_pos": "0,0", "end_pos": "0,0", "entry_direction": "south",
		"cells": [{
			"pos": "0,0", "stage_id": "s00a_nr2", "rotation": 0,
			"connections": {}, "portals": {"default": "default"},
			"is_start": true, "is_end": true, "is_branch": false,
			"has_key": false, "key_for_cell": "", "is_key_gate": false,
			"key_gate_direction": "", "key_gate_directions": [], "key_drop": "",
			"required_keys": 0, "warp_edge": "", "path_order": 0,
			"objects": [
				{"type": "enemy", "enemy_id": enemy_id, "position": [0.0, 0.0, 6.0]},
				{"type": "telepipe", "spawn_condition": "room_clear", "position": [0.0, 0.0, -7.0]},
			],
		}],
	}]


## One picker row per roster enemy: display name, element, HP, behavior archetype,
## and the delivery kinds its authored table carries (what you're about to fight).
## Sorted by display name so the list is stable and scannable.
static func roster_rows() -> Array:
	var rows: Array = []
	for id in EnemyRegistry.get_enemy_ids():
		var e = EnemyRegistry.get_enemy(str(id))
		if e == null:
			continue
		var kinds := {}
		for a in EnemyAttackRegistry.get_attacks(str(id), e.attack_range):
			kinds[str(a.get("kind", "melee_arc"))] = true
		rows.append({
			"id": str(id),
			"name": str(e.name),
			"element": String(EnemyData.Element.keys()[e.element]).to_lower(),
			"hp": int(e.hp_base),
			"archetype": EnemyAttackRegistry.get_archetype(str(id)),
			"kinds": kinds.keys(),
			"is_boss": bool(e.is_boss),
			"is_rare": bool(e.is_rare),
		})
	rows.sort_custom(_row_name_less)
	return rows


static func _row_name_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a["name"]).to_lower() < str(b["name"]).to_lower()
