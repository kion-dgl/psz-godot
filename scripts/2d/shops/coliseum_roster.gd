class_name ColiseumRoster
## Pure logic for the Coliseum Master debug lab (#629 follow-up): the synthesized
## 1:1 arena sections, the warp payload, and the grouped roster listing the picker
## renders. Kept static + node-free (the EnemyAttackLogic pattern) so test_runner
## can pin it directly without pulling the shop UI into its compile chain.

## Game-area progression order — roster groups are ordered by the earliest area
## their enemies appear in (location aliases normalize to these area names).
const AREA_ORDER := ["Gurhacia", "Ozette", "Rioh", "Makara", "Paru", "Arca", "Dark", "Eternal"]
const AREA_NAMES := ["Gurhacia Valley", "Ozette Wetlands", "Rioh Snowfield", "Makara Ruins",
	"Oblivion City Paru", "Arca Plant", "Dark Shrine", "Eternal Tower"]

## The player's coliseum spawn (local to the stage): the warp-in lands here, a
## clear run-up north to the enemy at (0, 6). Kion playtest.
const ARENA_SPAWN := [0.0, 0.5, 15.0]


## Shared one-cell section builder (the debug_coliseum shape): the coliseum pass
## adds a room-clear telepipe; boss-section arenas rely on the boss-clear return
## warp the field controller already spawns, so they carry no telepipe object.
static func _one_cell_section(stage_id: String, area_variant: String, area_id: String,
		objects: Array, boss_section: bool) -> Array:
	return [{
		"type": "boss" if boss_section else "grid",
		"area": area_variant, "area_id": area_id,
		"start_pos": "0,0", "end_pos": "0,0", "entry_direction": "south",
		"cells": [{
			"pos": "0,0", "stage_id": stage_id, "rotation": 0,
			"connections": {}, "portals": {"default": "default"},
			"is_start": true, "is_end": true, "is_branch": false,
			"has_key": false, "key_for_cell": "", "is_key_gate": false,
			"key_gate_direction": "", "key_gate_directions": [], "key_drop": "",
			"required_keys": 0, "warp_edge": "", "path_order": 0,
			"objects": objects,
		}],
	}]


## The 1:1 coliseum cell: one chosen enemy + a telepipe home on room clear.
static func make_sections(enemy_id: String) -> Array:
	if MIXED_GROUPS.has(enemy_id):
		return make_group_sections(enemy_id)
	return _one_cell_section("s00a_nr2", "a", "city", [
		{"type": "enemy", "enemy_id": enemy_id, "position": [0.0, 0.0, 6.0]},
		{"type": "telepipe", "spawn_condition": "room_clear", "position": [0.0, 0.0, -7.0]},
	], false)


## A solo boss-variation battle in its own arena (one enemy, boss-section rules —
## the boss-clear return warp covers the exit).
static func make_arena_sections(row: Dictionary) -> Array:
	var arena: Dictionary = row["arena"]
	return _one_cell_section(str(arena["stage"]), str(arena["variant"]), str(arena["area_id"]), [
		{"type": "enemy", "enemy_id": str(row["id"]), "position": arena.get("position", [0.0, 0.0, 4.0])},
	], true)


## The goto_scene payload for a coliseum warp — the picker and the headless probe
## both use this so the spawn point stays in one place.
static func warp_data() -> Dictionary:
	return {
		"current_cell_pos": "0,0",
		"spawn_edge": "",
		"keys_collected": {},
		"spawn_position": ARENA_SPAWN,
		# Face into the arena (the spawn sits at the south wall — without this
		# the player materialises looking at the wall behind them).
		"spawn_rotation": PI,
	}


## One picker row per roster enemy: display/model names, attribute, HP, behavior archetype,
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
			"model": str(e.model_id),
			"element": String(EnemyData.Element.keys()[e.element]).to_lower(),
			"hp": int(e.hp_base),
			"archetype": EnemyAttackRegistry.get_archetype(str(id)),
			"kinds": kinds.keys(),
			"is_boss": bool(e.is_boss),
			"is_rare": bool(e.is_rare),
			"areas": _areas_of(e),
			"area_rank": _area_rank(_areas_of(e)),
			# Bosses load their own arena (a debug_boss_* quest) when one exists —
			# their scripted actions only make sense there (kion playtest). The
			# mother variations get synthesized SOLO cells in the tower arena.
			"quest_id": boss_quest_for(str(id)) if bool(e.is_boss) else "",
			"arena": MOTHER_VARIATIONS.get(str(id), {}),
			"boss_tab": bool(e.is_boss) or MOTHER_VARIATIONS.has(str(id)),
		})
	return rows


## Each enemy appears once, under its earliest area. Imported PSO models have
## their own section, independent of any area metadata.
static func grouped_roster(is_boss: bool) -> Array:
	var by_area := {}
	for row in roster_rows():
		if bool(row["boss_tab"]) != is_boss:
			continue
		var rank := int(row["area_rank"])
		var area := str(AREA_NAMES[rank]) if rank < AREA_NAMES.size() else "Other"
		if str(row["id"]).begins_with("pso_") or str(row["model"]).begins_with("pso_") or "PSO Coliseum" in row["areas"]:
			area = "PSO Enemies"
			rank = AREA_NAMES.size()
		if not by_area.has(area):
			by_area[area] = {"name": area, "area_rank": rank, "rows": []}
		by_area[area]["rows"].append(row)
	var groups: Array = by_area.values()
	for group in groups:
		group["rows"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	groups.sort_custom(_area_then_name)
	return groups


## Shared ordering: area rank first, then the entry's display name (rows use
## "name", as do area groups).
static func _area_then_name(a: Dictionary, b: Dictionary) -> bool:
	if int(a["area_rank"]) != int(b["area_rank"]):
		return int(a["area_rank"]) < int(b["area_rank"])
	var an := str(a.get("name", "")).to_lower()
	var bn := str(b.get("name", "")).to_lower()
	return an < bn


static func _areas_of(e) -> Array:
	var out: Array = []
	for loc in e.get("locations"):
		out.append(str(loc))
	return out


## Explicit arena picks for bosses whose own quest doesn't place THEM (kion:
## mother_trinity fights in the Eternal Tower boss arena s087_na1 — its quest
## stages the three mothers there, which is the trinity fight's arena).
const ARENA_QUEST_OVERRIDES := {
	"mother_trinity": "debug_boss_heavens_mother",
}

## Mother Trinity's variations are each their own Bosses-tab option, fighting
## SOLO in the tower arena (kion) — not is_boss in data, so they're pinned here
## (positions from the authored three-mother encounter).
const MOTHER_VARIATIONS := {
	"blade_mother": {"stage": "s087_na1", "variant": "z", "area_id": "tower", "position": [0.0, 0.0, 4.0]},
	"force_mother": {"stage": "s087_na1", "variant": "z", "area_id": "tower", "position": [-4.0, 0.0, -3.0]},
	"shot_mother": {"stage": "s087_na1", "variant": "z", "area_id": "tower", "position": [4.0, 0.0, -3.0]},
}

## The debug_boss_* quest that stages this boss in its own arena, if any (bosses
## without one fall back to the coliseum cell). Scanned once from data/quests:
## first quest that places the enemy.
static var _boss_quests: Dictionary = {}

static func boss_quest_for(enemy_id: String) -> String:
	if ARENA_QUEST_OVERRIDES.has(enemy_id):
		return str(ARENA_QUEST_OVERRIDES[enemy_id])
	if _boss_quests.is_empty():
		_boss_quests = _scan_boss_quests()
	return str(_boss_quests.get(enemy_id, ""))


static func _scan_boss_quests() -> Dictionary:
	var map := {}
	var dir := DirAccess.open("res://data/quests")
	if dir == null:
		return map
	for fname in dir.get_files():
		var f := str(fname)
		if not f.begins_with("debug_boss_") or not f.ends_with(".json"):
			continue
		var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + f))
		if not q is Dictionary:
			continue
		for s in q.get("sections", []):
			for c in s.get("cells", []):
				for o in c.get("objects", []):
					if str(o.get("type", "")) != "enemy":
						continue
					var eid := str(o.get("enemy_id", ""))
					if not eid.is_empty() and not map.has(eid):
						map[eid] = str(q.get("id", ""))
	return map


## Earliest progression position of an enemy's areas; 99 = outside the known flow.
static func _area_rank(areas: Array) -> int:
	var best := 99
	for area in areas:
		var token: String = "Paru" if "Paru" in String(area) else String(area).split(" ")[0]
		var idx: int = AREA_ORDER.find(token)
		if idx >= 0:
			best = mini(best, idx)
	return best


## Authored mixed pressure tests; positions are separated by at least four metres.
const MIXED_GROUPS := {
	"mixed_bats": {"name":"Bats + Helion", "enemies":["batt", "bullbatt", "helion"]},
	"mixed_finjers": {"name":"Finjer Trio", "enemies":["finjer_r", "finjer_b", "finjer_g"]},
	"mixed_machines": {"name":"Tanks + Swordmen", "enemies":["phobos", "arkzein", "zaphobos"]},
	"mixed_mothers": {"name":"Mother Trio", "enemies":["blade_mother", "shot_mother", "force_mother"]},
	"mixed_pressure": {"name":"Combined Pressure", "enemies":["batt", "finjer_r", "zaphobos", "arkzein", "force_mother"]},
}
const GROUP_POSITIONS := [[-5.0,0.0,4.0], [5.0,0.0,4.0], [0.0,0.0,0.0], [-5.0,0.0,-4.0], [5.0,0.0,-4.0]]

static func make_group_sections(group_id: String) -> Array:
	var objects: Array = []
	var ids: Array = MIXED_GROUPS[group_id].enemies
	for i in ids.size():
		objects.append({"type":"enemy", "enemy_id":ids[i], "position":GROUP_POSITIONS[i].duplicate()})
	objects.append({"type":"telepipe", "spawn_condition":"room_clear", "position":[0.0,0.0,-7.0]})
	return _one_cell_section("s00a_nr2", "a", "city", objects, false)

static func mixed_roster() -> Array:
	var rows: Array = []
	for id in MIXED_GROUPS:
		var names: Array = []
		var hp := 0
		for enemy_id in MIXED_GROUPS[id].enemies:
			var enemy = EnemyRegistry.get_enemy(enemy_id)
			names.append(enemy.name)
			hp += enemy.hp_base
		rows.append({"id":id, "name":MIXED_GROUPS[id].name, "is_rare":false,
			"element":"%d enemies" % names.size(), "hp":hp, "areas":names,
			"archetype":"mixed group", "kinds":["melee", "ranged", "room clear"]})
	return [{"name":"Mixed Groups", "area_rank":0, "rows":rows}]
