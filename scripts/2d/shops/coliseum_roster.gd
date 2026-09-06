class_name ColiseumRoster
## Pure logic for the Coliseum Master debug lab (#629 follow-up): the synthesized
## 1:1 arena sections, the warp payload, and the grouped roster listing the picker
## renders. Kept static + node-free (the EnemyAttackLogic pattern) so test_runner
## can pin it directly without pulling the shop UI into its compile chain.

## Game-area progression order — roster groups are ordered by the earliest area
## their enemies appear in (matched on the first token: location strings vary,
## e.g. "Ozette Wetlands" vs "Ozette Wetland").
const AREA_ORDER := ["Gurhacia", "Ozette", "Rioh", "Makara", "Paru", "Arca", "Dark", "Eternal"]

## The player's coliseum spawn (local to the stage): the warp-in lands here, a
## clear run-up north to the enemy at (0, 6). Kion playtest.
const ARENA_SPAWN := [0.0, 0.5, 15.0]


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


## The goto_scene payload for a coliseum warp — the picker and the headless probe
## both use this so the spawn point stays in one place.
static func warp_data() -> Dictionary:
	return {
		"current_cell_pos": "0,0",
		"spawn_edge": "",
		"keys_collected": {},
		"spawn_position": ARENA_SPAWN,
	}


## One picker row per roster enemy: display name, element, HP, behavior archetype,
## delivery kinds, and the areas it appears in (what you're about to fight).
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
			"areas": _areas_of(e),
			"area_rank": _area_rank(_areas_of(e)),
		})
	return rows


## Grouped listing for one tab (kion playtest: grouped by type, ordered by the
## areas they appear in; normal enemies and bosses live on separate tabs).
## Returns [{archetype, area_rank, rows}] — groups sorted by earliest area then
## archetype name; rows within a group by (area rank, name).
static func grouped_roster(is_boss: bool) -> Array:
	var by_archetype := {}
	for row in roster_rows():
		if bool(row["is_boss"]) != is_boss:
			continue
		var arch: String = str(row["archetype"])
		if not by_archetype.has(arch):
			by_archetype[arch] = []
		by_archetype[arch].append(row)
	var groups: Array = []
	for arch in by_archetype:
		var rows: Array = by_archetype[arch]
		var rank: int = 99
		for r in rows:
			rank = mini(rank, int(r["area_rank"]))
		rows.sort_custom(_area_then_name)
		groups.append({"archetype": str(arch), "area_rank": rank, "rows": rows})
	groups.sort_custom(_area_then_name)
	return groups


## Shared ordering: area rank first, then the entry's display name (rows use
## "name"; groups fall back to their archetype).
static func _area_then_name(a: Dictionary, b: Dictionary) -> bool:
	if int(a["area_rank"]) != int(b["area_rank"]):
		return int(a["area_rank"]) < int(b["area_rank"])
	var an := str(a.get("name", a.get("archetype", ""))).to_lower()
	var bn := str(b.get("name", b.get("archetype", ""))).to_lower()
	return an < bn


static func _areas_of(e) -> Array:
	var out: Array = []
	for loc in e.get("locations"):
		out.append(str(loc))
	return out


## Earliest progression position of an enemy's areas; 99 = outside the known flow.
static func _area_rank(areas: Array) -> int:
	var best := 99
	for area in areas:
		var token: String = String(area).split(" ")[0]
		var idx: int = AREA_ORDER.find(token)
		if idx >= 0:
			best = mini(best, idx)
	return best
