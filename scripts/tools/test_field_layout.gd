extends Node
## Headless invariant check for the RE-measured Valley free field
## (data/field_quests/valley_field.json) and the Reyburn boss data.
## Seeded/deterministic layer for issue #562 / #563 (spec /states/free-field).
##   Run: godot --headless res://scripts/tools/test_field_layout.tscn
##
## Verifies the same invariants psz-re measured out of the ROM survive the
## build: every layout is a tree, door directions line up with the room's
## rotated config portals, keys balance their gates, every spawn resolves to a
## real enemy, and the boss room holds Reyburn at the measured HP.

const CW := {"north": "east", "east": "south", "south": "west", "west": "north"}

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("\n══════ VALLEY FREE-FIELD LAYOUT TESTS ══════")
	var field := _load_json("res://data/field_quests/valley_field.json")
	var cfg := _load_json("res://data/stage_configs/unified-stage-configs.json")
	if field.is_empty() or cfg.is_empty():
		_fail += 1
		print("  FAIL: could not load field or config")
		_finish()
		return

	_check("area_id is gurhacia", field.get("area_id") == "gurhacia")
	var sections: Array = field.get("sections", [])
	_check("has 4 sections (a/e/b/z)", sections.size() == 4)
	var types := []
	for s in sections: types.append(str(s.get("type")))
	_check("section order grid/transition/grid/boss",
		types == ["grid", "transition", "grid", "boss"])

	for sec in sections:
		if sec.get("type") == "grid":
			_check_grid_section(sec, cfg)
		elif sec.get("type") == "boss":
			_check_boss_section(sec)

	_check_reyburn_data()
	_finish()


func _check_grid_section(sec: Dictionary, cfg: Dictionary) -> void:
	var area: String = str(sec.get("area"))
	var cells: Array = sec.get("cells", [])
	var by_pos := {}
	for c in cells:
		by_pos[c["pos"]] = c

	# tree: edges == V - 1
	var edge_count := 0
	for c in cells:
		edge_count += (c.get("connections", {}) as Dictionary).size()
	edge_count /= 2
	_check("area %s is a tree (E=V-1)" % area, edge_count == cells.size() - 1)

	# exactly one start and one goal
	var starts := 0
	var goal_shape_g := 0
	for c in cells:
		if c.get("is_start"): starts += 1
		if str(c.get("stage_id")).split("_")[1].begins_with("g"): goal_shape_g += 1
	_check("area %s has exactly one start" % area, starts == 1)
	_check("area %s has exactly one goal room" % area, goal_shape_g == 1)

	# adjacency symmetric + rotation covers every connection direction
	var sym_ok := true
	var rot_ok := true
	for c in cells:
		var code: String = str(c.get("stage_id"))
		var rotation: int = int(c.get("rotation", 0)) / 90
		var cfg_dirs: Array = []
		for p in (cfg.get(code, {}) as Dictionary).get("portals", []):
			cfg_dirs.append(_rot(str(p.get("direction")), rotation))
		for dir in (c.get("connections", {}) as Dictionary):
			var to: String = c["connections"][dir]
			if dir not in cfg_dirs:
				rot_ok = false
			var back: Dictionary = by_pos.get(to, {})
			if not back.get("connections", {}).values().has(c["pos"]):
				sym_ok = false
	_check("area %s adjacency symmetric" % area, sym_ok)
	_check("area %s rotations cover connections" % area, rot_ok)

	# keys balance gates
	var keys := 0
	var req := 0
	for c in cells:
		keys += int(c.get("key_count", 0))
		if c.get("is_key_gate"):
			req += int(c.get("required_keys", 0))
	_check("area %s keys balance gates (keys=%d req=%d)" % [area, keys, req], keys == req)

	# every enemy resolves
	var enemy_ok := true
	for c in cells:
		for o in c.get("objects", []):
			if o.get("type") == "enemy":
				if not EnemyRegistry.get_enemy(str(o.get("enemy_id"))):
					enemy_ok = false
					print("    unresolved enemy_id: %s" % o.get("enemy_id"))
	_check("area %s all enemies resolve in registry" % area, enemy_ok)


func _check_boss_section(sec: Dictionary) -> void:
	var cells: Array = sec.get("cells", [])
	var found_reyburn := false
	for c in cells:
		_check("boss room is s01z_na1", str(c.get("stage_id")) == "s01z_na1")
		for o in c.get("objects", []):
			if o.get("type") == "enemy" and o.get("enemy_id") == "reyburn":
				found_reyburn = true
	_check("boss room spawns Reyburn", found_reyburn)


func _check_reyburn_data() -> void:
	var edata = EnemyRegistry.get_enemy("reyburn")
	_check("reyburn data exists", edata != null)
	if edata:
		_check("reyburn HP is 1650 (measured)", edata.hp_base == 1650)
		_check("reyburn is flagged boss", edata.is_boss)
		_check("reyburn model is boss_dragon", str(edata.model_id) == "boss_dragon")
	# boss kit present + parseable
	var kit := _load_json("res://data/boss_arenas.json")
	var bosses: Dictionary = kit.get("bosses", kit)
	_check("boss_arenas has reyburn kit", bosses.has("reyburn"))
	if bosses.has("reyburn"):
		_check("reyburn kit has attacks", (bosses["reyburn"].get("attacks", []) as Array).size() > 0)


func _rot(d: String, steps: int) -> String:
	for _i in range(steps % 4):
		d = CW[d]
	return d


func _load_json(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		return {}
	var data: Variant = JSON.parse_string(fa.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ FAIL: %s" % label)


func _finish() -> void:
	print("\n  RESULTS: %d passed, %d failed\n" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
