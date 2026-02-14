extends RefCounted
## GridGenerator — generates 5x5 grid layouts with branches and key-gates.
## Faithfully ports psz-sketch's GridViewer.tsx algorithm.
## Area-agnostic: reads portal directions from *_config.json when available,
## falls back to hardcoded GATES for valley (s01).

const DIRECTIONS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const DIR_OFFSET := {
	"north": Vector2i(-1, 0), "south": Vector2i(1, 0),
	"east": Vector2i(0, 1), "west": Vector2i(0, -1),
}


## Rotate a direction clockwise by the given degrees (0, 90, 180, 270).
## CW from above: 90 → N→E, E→S, S→W, W→N.
static func _rotate_direction(dir: String, rotation: int) -> String:
	if rotation == 0:
		return dir
	var idx: int = DIRECTIONS.find(dir)
	if idx < 0:
		return dir
	var steps: int = (rotation / 90) % 4
	return DIRECTIONS[(idx + steps) % 4]


## Get gate directions in grid-space for a cell, applying its rotation.
func _get_rotated_gates(cell: Dictionary) -> Array[String]:
	var stage_id: String = str(cell.get("stage_id", ""))
	var rotation: int = int(cell.get("rotation", 0))
	var original: Array[String] = _get_gates(stage_id)
	if rotation == 0:
		return original
	var rotated: Array[String] = []
	for g in original:
		rotated.append(_rotate_direction(g, rotation))
	return rotated

## Area configuration: maps area_id → prefix, folder, display name.
const AREA_CONFIG := {
	"gurhacia": {"prefix": "s01", "folder": "valley", "name": "Gurhacia Valley"},
	"ozette":   {"prefix": "s02", "folder": "wetlands", "name": "Ozette Wetlands"},
	"rioh":     {"prefix": "s03", "folder": "snowfield", "name": "Rioh Snowfield"},
	"makara":   {"prefix": "s04", "folder": "makara", "name": "Makara Ruins"},
	"paru":     {"prefix": "s05", "folder": "paru", "name": "Paru Waterfall"},
	"arca":     {"prefix": "s06", "folder": "arca", "name": "Arca Plant"},
	"dark":     {"prefix": "s07", "folder": "shrine", "name": "Dark Shrine"},
	"tower":    {"prefix": "s08", "folder": "tower", "name": "Eternal Tower"},
}

## Tower-specific constants.
const TOWER_FLOOR_STYLES := ["s081", "s082", "s083", "s084", "s085", "s086"]
const TOWER_ROOM_TYPES := ["ga1", "sa1", "ib1", "lb1"]
const TOWER_DIFFICULTY_PARAMS := {
	"normal":     {"tower_floors": 2, "tower_rooms_per_floor": 3},
	"hard":       {"tower_floors": 4, "tower_rooms_per_floor": 4},
	"super-hard": {"tower_floors": 6, "tower_rooms_per_floor": 4},
}

## Gate definitions per stage (original directions).
## Used as fallback for areas without *_config.json files (valley/s01).
const GATES := {
	# s01a_ stages
	"s01a_sa1": ["south"],
	"s01a_ga1": ["north", "south"],
	"s01a_ib1": ["north", "south"],
	"s01a_ib2": ["north", "south"],
	"s01a_ic1": ["north", "south"],
	"s01a_ic3": ["north", "south"],
	"s01a_lb1": ["north", "west"],
	"s01a_lb3": ["north", "west"],
	"s01a_lc1": ["north", "west"],
	"s01a_lc2": ["north", "west"],
	"s01a_na1": ["south"],
	"s01a_nb2": ["south"],
	"s01a_nc2": ["south"],
	"s01a_tb3": ["east", "south", "west"],
	"s01a_tc3": ["east", "south", "west"],
	"s01a_td1": ["east", "south", "west"],
	"s01a_td2": ["east", "south", "west"],
	"s01a_xb2": ["north", "east", "south", "west"],
	# s01b_ stages
	"s01b_sa1": ["north", "south"],
	"s01b_ga1": ["south"],
	"s01b_ib1": ["north", "south"],
	"s01b_ib2": ["north", "south"],
	"s01b_ic1": ["north", "south"],
	"s01b_ic3": ["north", "south"],
	"s01b_lb1": ["north", "west"],
	"s01b_lb3": ["north", "west"],
	"s01b_lc1": ["north", "west"],
	"s01b_lc2": ["north", "west"],
	"s01b_na1": ["west"],
	"s01b_nb2": ["south"],
	"s01b_nc2": ["south"],
	"s01b_tb3": ["east", "south", "west"],
	"s01b_tc3": ["east", "south", "west"],
	"s01b_td1": ["east", "south", "west"],
	"s01b_td2": ["east", "south", "west"],
	"s01b_xb2": ["north", "east", "south", "west"],
	# s01e_ stages
	"s01e_ia1": ["north", "south"],
}

## Cache for dynamically loaded gates (avoids re-reading JSON each generation).
var _gates_cache: Dictionary = {}

## Active gates dict for the current generation run.
var _active_gates: Dictionary = GATES


## Load gates dict for an area by reading *_config.json files from the assets folder.
## Falls back to hardcoded GATES for areas without config JSONs (valley/s01).
func load_gates(area_id: String) -> Dictionary:
	if _gates_cache.has(area_id):
		return _gates_cache[area_id]

	var cfg: Dictionary = AREA_CONFIG.get(area_id, {})
	if cfg.is_empty():
		_gates_cache[area_id] = GATES
		return GATES

	var prefix: String = cfg["prefix"]
	var folder: String = cfg["folder"]
	var base_path := "res://assets/environments/%s/" % folder

	# Check if config JSONs exist for this area
	var test_path := "%s%sa_sa1_config.json" % [base_path, prefix]
	if not FileAccess.file_exists(test_path):
		# No config JSONs — use hardcoded GATES (valley)
		_gates_cache[area_id] = GATES
		return GATES

	var gates := {}
	# Scan for all config JSONs in the folder
	var dir := DirAccess.open(base_path)
	if not dir:
		_gates_cache[area_id] = GATES
		return GATES

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.ends_with("_config.json"):
			var stage_id: String = file_name.replace("_config.json", "")
			var json_path := base_path + file_name
			var fa := FileAccess.open(json_path, FileAccess.READ)
			if fa:
				var json := JSON.new()
				if json.parse(fa.get_as_text()) == OK:
					var data: Dictionary = json.data
					var portals: Array = data.get("portals", [])
					var dirs: Array[String] = []
					for portal in portals:
						var d: String = str(portal.get("direction", ""))
						if not d.is_empty() and d not in dirs:
							dirs.append(d)
					if not dirs.is_empty():
						gates[stage_id] = dirs
				fa.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	if gates.is_empty():
		_gates_cache[area_id] = GATES
		return GATES

	_gates_cache[area_id] = gates
	return gates

## ── TUNING PARAMETERS ──
##
## grid_size (int, default 5):
##   The NxN grid dimensions. Stages are placed on this grid. Larger grids
##   allow longer, more winding paths but may feel sparse. Range: 3–7.
##
## path_length (int):
##   Number of cells on the MAIN path from start to end (including start/end).
##   This is the critical path the player must follow to complete the section.
##   More cells = longer section. Must be >= 3, max = grid_size * grid_size.
##   Normal: 5, Hard: 7, Super-Hard: 9.
##
## key_gates (int):
##   Number of locked gates placed on the main path. Each gate blocks forward
##   progress until the player finds the corresponding key. Keys are placed on
##   earlier cells or branch dead-ends (80% prefer branches to reward exploration).
##   0 = no locked gates, 1–2 is typical. More than 2 can feel tedious.
##
## branches (int):
##   Number of dead-end side rooms branching off the main path. These encourage
##   exploration and are prime locations for key items. The generator tries to
##   place them but may place fewer if the grid is too constrained. Range: 0–4.
##
## Each difficulty defines separate params for area "a" and area "b" sections.
## The "e" (transition) and "z" (boss) sections are always single rooms.

const DIFFICULTY_PARAMS := {
	"normal": {
		"a": {"path_length": 5, "key_gates": 0, "branches": 1},
		"b": {"path_length": 5, "key_gates": 0, "branches": 1},
	},
	"hard": {
		"a": {"path_length": 7, "key_gates": 1, "branches": 2},
		"b": {"path_length": 7, "key_gates": 1, "branches": 2},
	},
	"super-hard": {
		"a": {"path_length": 9, "key_gates": 1, "branches": 2},
		"b": {"path_length": 9, "key_gates": 1, "branches": 2},
	},
}

var grid_size: int = 5


## Load grid generation parameters from config file.
## Priority: user://field_config.cfg > res://data/field_config.cfg > hardcoded DIFFICULTY_PARAMS.
static func load_params() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("user://field_config.cfg") != OK:
		if cfg.load("res://data/field_config.cfg") != OK:
			return DIFFICULTY_PARAMS
	var params := {}
	for difficulty in ["normal", "hard", "super-hard"]:
		if not cfg.has_section(difficulty):
			params[difficulty] = DIFFICULTY_PARAMS.get(difficulty, DIFFICULTY_PARAMS["normal"])
			continue
		params[difficulty] = {
			"a": {
				"path_length": cfg.get_value(difficulty, "a_path_length", 5),
				"key_gates": cfg.get_value(difficulty, "a_key_gates", 0),
				"branches": cfg.get_value(difficulty, "a_branches", 1),
			},
			"b": {
				"path_length": cfg.get_value(difficulty, "b_path_length", 5),
				"key_gates": cfg.get_value(difficulty, "b_key_gates", 0),
				"branches": cfg.get_value(difficulty, "b_branches", 1),
			},
		}
	return params


## Load grid size from config file.
static func load_grid_size() -> int:
	var cfg := ConfigFile.new()
	if cfg.load("user://field_config.cfg") != OK:
		cfg.load("res://data/field_config.cfg")
	return cfg.get_value("grid", "grid_size", 5)


## Get gate directions for a stage from the active gates dict.
func _get_gates(stage_id: String) -> Array[String]:
	var original: Array = _active_gates.get(stage_id, [])
	var result: Array[String] = []
	for g in original:
		result.append(str(g))
	return result


## Generate a complete field with 4 sections: a (grid), e (transition), b (grid), z (boss).
## area_id: "gurhacia", "ozette", etc. Defaults to "gurhacia" for backwards compatibility.
func generate_field(difficulty: String, area_id: String = "gurhacia") -> Dictionary:
	var all_params: Dictionary = load_params()
	var params: Dictionary = all_params.get(difficulty, all_params.get("normal", DIFFICULTY_PARAMS["normal"]))
	grid_size = load_grid_size()

	var area_cfg: Dictionary = AREA_CONFIG.get(area_id, AREA_CONFIG["gurhacia"])
	var prefix: String = area_cfg["prefix"]
	_active_gates = load_gates(area_id)
	var sections: Array[Dictionary] = []

	# Section 1: Area A grid
	var a_result: Dictionary = generate("a", params["a"], prefix)
	sections.append({
		"type": "grid", "area": "a", "cells": a_result["cells"],
		"start_pos": a_result["start_pos"], "end_pos": a_result.get("end_pos", ""),
	})

	# Section 2: Area E transition (single room)
	var e_stage := "%se_ia1" % prefix
	var e_cell := _make_output_cell(Vector2i(0, 0), e_stage, 0, true, true, false, 0)
	e_cell["warp_edge"] = "south"
	sections.append({
		"type": "transition", "area": "e", "cells": [e_cell],
		"start_pos": "0,0", "end_pos": "0,0",
	})

	# Section 3: Area B grid
	var b_result: Dictionary = generate("b", params["b"], prefix)
	sections.append({
		"type": "grid", "area": "b", "cells": b_result["cells"],
		"start_pos": b_result["start_pos"], "end_pos": b_result.get("end_pos", ""),
	})

	# Section 4: Area Z boss arena (single room)
	# Prefer {prefix}z_na1 (wetlands has s02z_na1), fall back to {prefix}a_na1 (valley lacks s01z_na1)
	var z_stage := "%sz_na1" % prefix
	if not _active_gates.has(z_stage):
		z_stage = "%sa_na1" % prefix
	var z_cell := _make_output_cell(Vector2i(0, 0), z_stage, 0, true, true, false, 0)
	z_cell["warp_edge"] = "south"
	sections.append({
		"type": "boss", "area": "z", "cells": [z_cell],
		"start_pos": "0,0", "end_pos": "0,0",
	})

	return {"sections": sections}


## Generate a linear tower field: entrance → floor rooms → transition → floor rooms → boss.
## tower_floors and tower_rooms_per_floor are read from config, falling back to difficulty defaults.
func generate_tower_field(difficulty: String) -> Dictionary:
	var tower_floors: int
	var tower_rooms_per_floor: int

	# Try config file first
	var cfg := ConfigFile.new()
	var has_cfg := false
	if cfg.load("user://field_config.cfg") == OK:
		has_cfg = true
	elif cfg.load("res://data/field_config.cfg") == OK:
		has_cfg = true

	if has_cfg and cfg.has_section("tower"):
		var defaults: Dictionary = TOWER_DIFFICULTY_PARAMS.get(difficulty, TOWER_DIFFICULTY_PARAMS["normal"])
		tower_floors = int(cfg.get_value("tower", "tower_floors", defaults["tower_floors"]))
		tower_rooms_per_floor = int(cfg.get_value("tower", "tower_rooms_per_floor", defaults["tower_rooms_per_floor"]))
	else:
		var params: Dictionary = TOWER_DIFFICULTY_PARAMS.get(difficulty, TOWER_DIFFICULTY_PARAMS["normal"])
		tower_floors = int(params["tower_floors"])
		tower_rooms_per_floor = int(params["tower_rooms_per_floor"])

	tower_floors = clampi(tower_floors, 1, 100)
	tower_rooms_per_floor = clampi(tower_rooms_per_floor, 1, 4)

	var sections: Array[Dictionary] = []
	var section_idx := 0

	# Entrance
	var entrance_cell := _make_output_cell(Vector2i(0, 0), "s080_sa0", 0, true, false, false, 0)
	entrance_cell["warp_edge"] = "south"
	sections.append({
		"type": "tower", "area": "entrance", "cells": [entrance_cell],
		"start_pos": "0,0", "end_pos": "0,0",
	})
	section_idx += 1

	# Split floors into pre-transition and post-transition halves
	var mid_floor: int = ceili(tower_floors / 2.0)

	# First half of floors
	for f in range(mid_floor):
		var style: String = TOWER_FLOOR_STYLES[f % TOWER_FLOOR_STYLES.size()]
		for r in range(tower_rooms_per_floor):
			var room_type: String = TOWER_ROOM_TYPES[r]
			var stage_id := "%s_%s" % [style, room_type]
			var warp: String = "west" if room_type == "lb1" else "south"
			var cell := _make_output_cell(Vector2i(0, 0), stage_id, 0, false, false, false, section_idx)
			cell["warp_edge"] = warp
			sections.append({
				"type": "tower", "area": "floor", "cells": [cell],
				"start_pos": "0,0", "end_pos": "0,0",
			})
			section_idx += 1

	# Mid-tower transition
	var trans_cell := _make_output_cell(Vector2i(0, 0), "s08e_ib1", 0, false, false, false, section_idx)
	trans_cell["warp_edge"] = "south"
	sections.append({
		"type": "transition", "area": "e", "cells": [trans_cell],
		"start_pos": "0,0", "end_pos": "0,0",
	})
	section_idx += 1

	# Second half of floors
	for f in range(mid_floor, tower_floors):
		var style: String = TOWER_FLOOR_STYLES[f % TOWER_FLOOR_STYLES.size()]
		for r in range(tower_rooms_per_floor):
			var room_type: String = TOWER_ROOM_TYPES[r]
			var stage_id := "%s_%s" % [style, room_type]
			var warp: String = "west" if room_type == "lb1" else "south"
			var cell := _make_output_cell(Vector2i(0, 0), stage_id, 0, false, false, false, section_idx)
			cell["warp_edge"] = warp
			sections.append({
				"type": "tower", "area": "floor", "cells": [cell],
				"start_pos": "0,0", "end_pos": "0,0",
			})
			section_idx += 1

	# Boss
	var boss_cell := _make_output_cell(Vector2i(0, 0), "s087_na1", 0, false, true, false, section_idx)
	boss_cell["warp_edge"] = ""
	sections.append({
		"type": "boss", "area": "z", "cells": [boss_cell],
		"start_pos": "0,0", "end_pos": "0,0",
	})

	return {"sections": sections}


## Generate a single grid section.
## area: "a" or "b"
## params: {"path_length": int, "key_gates": int, "branches": int}
## area_prefix: e.g. "s01" or "s02". Defaults to "s01" for backwards compatibility.
func generate(area: String, params: Dictionary, area_prefix: String = "s01") -> Dictionary:
	if grid_size <= 0:
		grid_size = load_grid_size()
	var path_length: int = int(params.get("path_length", 5))
	var key_gates: int = int(params.get("key_gates", 0))
	var branches: int = int(params.get("branches", 0))
	path_length = clampi(path_length, 3, grid_size * grid_size)

	for attempt in range(200):
		var result: Dictionary = _try_generate(area, path_length, key_gates, branches, area_prefix)
		if not result.is_empty():
			return result

	push_warning("GridGenerator: Failed to generate after 200 attempts, using fallback")
	return _generate_fallback(area, area_prefix)


## Single attempt at generating a valid grid.
func _try_generate(area: String, path_length: int, key_gates_count: int,
		branches_count: int, area_prefix: String = "s01") -> Dictionary:
	var grid: Dictionary = {}  # "row,col" → cell dict
	var path: Array[Vector2i] = []
	var prefix: String = "%s%s_" % [area_prefix, area]
	var start_stage: String = prefix + "sa1"

	if not _active_gates.has(start_stage):
		return {}

	# Place sa1 at top-center, exiting south
	var sa1_row := 0
	var sa1_col: int = grid_size / 2

	# Check sa1's original gates: must have south, other gates must point outside grid
	var sa1_gates: Array[String] = _get_gates(start_stage)
	if "south" not in sa1_gates:
		return {}
	var sa1_valid := true
	for gate in sa1_gates:
		if gate == "south":
			continue
		var offset: Vector2i = DIR_OFFSET[gate]
		if _is_valid_pos(sa1_row + offset.x, sa1_col + offset.y):
			sa1_valid = false
			break
	if not sa1_valid:
		return {}

	# Place start cell
	var start_key := _pos_key(Vector2i(sa1_row, sa1_col))
	grid[start_key] = {
		"stage_id": start_stage, "rotation": 0,
		"entry_direction": "", "is_start": true, "is_end": false,
		"is_branch": false, "has_key": false, "key_for_cell": "",
		"is_key_gate": false, "key_gate_direction": "",
		"path_order": 0,
	}
	path.append(Vector2i(sa1_row, sa1_col))

	# Build linear path
	var current_row: int = sa1_row
	var current_col: int = sa1_col
	var last_exit_dir := "south"

	var all_stages: Array[String] = []
	for stage_id in _active_gates:
		if str(stage_id).begins_with(prefix) and stage_id != start_stage:
			all_stages.append(str(stage_id))

	while path.size() < path_length:
		var offset: Vector2i = DIR_OFFSET[last_exit_dir]
		var next_row: int = current_row + offset.x
		var next_col: int = current_col + offset.y
		var entry_dir: String = OPPOSITE[last_exit_dir]

		if not _is_valid_pos(next_row, next_col):
			break

		var next_key := _pos_key(Vector2i(next_row, next_col))
		if grid.has(next_key):
			break

		var is_last_cell: bool = path.size() == path_length - 1

		# Find valid stages for this position
		var candidates: Array[Dictionary] = []
		for stage_id in all_stages:
			var gates: Array[String] = _get_gates(stage_id)
			if entry_dir not in gates:
				continue
			var other_gates: Array[String] = []
			for g in gates:
				if g != entry_dir:
					other_gates.append(g)

			if is_last_cell:
				# End cell: exactly 1 other gate pointing outside grid
				if other_gates.size() != 1:
					continue
				var eo: Vector2i = DIR_OFFSET[other_gates[0]]
				if _is_valid_pos(next_row + eo.x, next_col + eo.y):
					continue
				candidates.append({
					"stage": stage_id, "rotation": 0,
					"exit_dir": other_gates[0],
				})
			else:
				# Middle cell: exactly 1 other gate → empty cell inside grid
				if other_gates.size() != 1:
					continue
				var eo: Vector2i = DIR_OFFSET[other_gates[0]]
				var er: int = next_row + eo.x
				var ec: int = next_col + eo.y
				if not _is_valid_pos(er, ec):
					continue
				if grid.has(_pos_key(Vector2i(er, ec))):
					continue
				candidates.append({
					"stage": stage_id, "rotation": 0,
					"exit_dir": other_gates[0],
				})

		if candidates.is_empty():
			# Try to end early if we have enough cells
			if path.size() >= 3:
				if _try_place_end_cell(grid, path, all_stages, next_row, next_col, entry_dir):
					break
			break

		var chosen: Dictionary = candidates[randi() % candidates.size()]

		grid[next_key] = {
			"stage_id": str(chosen["stage"]),
			"rotation": 0,
			"entry_direction": entry_dir,
			"is_start": false,
			"is_end": is_last_cell,
			"is_branch": false,
			"has_key": false,
			"key_for_cell": "",
			"is_key_gate": false,
			"key_gate_direction": str(chosen["exit_dir"]) if is_last_cell else "",
			"path_order": path.size(),
		}
		path.append(Vector2i(next_row, next_col))

		if is_last_cell:
			break

		current_row = next_row
		current_col = next_col
		last_exit_dir = str(chosen["exit_dir"])

	if path.size() < 3:
		return {}

	# Verify end cell has warp exit
	var end_pos: Vector2i = path[path.size() - 1]
	var end_key := _pos_key(end_pos)
	var end_cell: Dictionary = grid[end_key]

	if not end_cell.get("is_end", false) or str(end_cell.get("key_gate_direction", "")).is_empty():
		if not _fix_end_cell(grid, end_cell, end_pos, all_stages):
			return {}

	# Add dead-end branches
	var branch_cells: Array[Vector2i] = []
	if branches_count > 0:
		branch_cells = _add_branches(grid, path, all_stages, branches_count)

	# Add key-gates
	if key_gates_count > 0:
		_add_key_gates(grid, path, branch_cells, key_gates_count)

	# Validate: all gates match neighbors (no orphans)
	if not _validate_gates(grid):
		return {}

	# BFS: verify end reachable from start
	var start_pos: Vector2i = path[0]
	if not _validate_reachability(grid, start_pos, end_pos):
		return {}

	return _to_output(grid, path, branch_cells, start_pos, end_pos)


## Try to place an end cell at the given position.
func _try_place_end_cell(grid: Dictionary, path: Array[Vector2i],
		all_stages: Array[String], row: int, col: int, entry_dir: String) -> bool:
	var key := _pos_key(Vector2i(row, col))
	for stage_id in all_stages:
		var gates: Array[String] = _get_gates(stage_id)
		if entry_dir not in gates:
			continue
		var other: Array[String] = []
		for g in gates:
			if g != entry_dir:
				other.append(g)
		if other.size() != 1:
			continue
		var eo: Vector2i = DIR_OFFSET[other[0]]
		if _is_valid_pos(row + eo.x, col + eo.y):
			continue
		grid[key] = {
			"stage_id": stage_id, "rotation": 0,
			"entry_direction": entry_dir, "is_start": false,
			"is_end": true, "is_branch": false,
			"has_key": false, "key_for_cell": "",
			"is_key_gate": false, "key_gate_direction": other[0],
			"path_order": path.size(),
		}
		path.append(Vector2i(row, col))
		return true
	return false


## Fix the last cell to be a valid end cell with warp exit.
func _fix_end_cell(grid: Dictionary, end_cell: Dictionary, end_pos: Vector2i,
		all_stages: Array[String]) -> bool:
	var entry_dir: String = str(end_cell.get("entry_direction", ""))
	if entry_dir.is_empty():
		return false

	for stage_id in all_stages:
		var gates: Array[String] = _get_gates(stage_id)
		if entry_dir not in gates:
			continue
		var warp_dir := ""
		var has_orphan := false
		for gate in gates:
			if gate == entry_dir:
				continue
			var offset: Vector2i = DIR_OFFSET[gate]
			var nr: int = end_pos.x + offset.x
			var nc: int = end_pos.y + offset.y
			if not _is_valid_pos(nr, nc):
				warp_dir = gate
			elif grid.has(_pos_key(Vector2i(nr, nc))):
				var neighbor: Dictionary = grid[_pos_key(Vector2i(nr, nc))]
				var n_gates: Array[String] = _get_gates(str(neighbor["stage_id"]))
				if OPPOSITE[gate] not in n_gates:
					has_orphan = true
					break
		if has_orphan or warp_dir.is_empty():
			continue
		end_cell["stage_id"] = stage_id
		end_cell["rotation"] = 0
		end_cell["is_end"] = true
		end_cell["key_gate_direction"] = warp_dir
		return true
	return false


## Add dead-end branches off the main path.
func _add_branches(grid: Dictionary, path: Array[Vector2i],
		all_stages: Array[String], target_count: int) -> Array[Vector2i]:
	var branch_cells: Array[Vector2i] = []

	var candidates: Array[Dictionary] = []
	for path_pos in path:
		var cell: Dictionary = grid[_pos_key(path_pos)]
		if cell.get("is_start", false) or cell.get("is_end", false):
			continue

		var current_gates: Array[String] = _get_gates(str(cell["stage_id"]))
		var entry_dir: String = str(cell.get("entry_direction", ""))
		# Find exit direction (the gate that's not entry)
		var exit_dir := ""
		for g in current_gates:
			if g != entry_dir:
				exit_dir = g
				break
		if exit_dir.is_empty():
			continue

		for dir in DIRECTIONS:
			if dir == entry_dir or dir == exit_dir:
				continue
			var offset: Vector2i = DIR_OFFSET[dir]
			var br: int = path_pos.x + offset.x
			var bc: int = path_pos.y + offset.y
			if not _is_valid_pos(br, bc):
				continue
			if grid.has(_pos_key(Vector2i(br, bc))):
				continue

			if dir in current_gates:
				# Current cell already has gate here — no replacement needed
				candidates.append({
					"path_pos": path_pos, "branch_dir": dir,
					"branch_pos": Vector2i(br, bc), "needs_replacement": false,
				})
			else:
				# Need replacement stage with entry + exit + branch gates
				_find_branch_replacement(candidates, grid, path_pos, all_stages,
					entry_dir, exit_dir, dir, Vector2i(br, bc))

	candidates.shuffle()
	var placed := 0

	for c in candidates:
		if placed >= target_count:
			break
		var branch_pos: Vector2i = c["branch_pos"]
		var bkey := _pos_key(branch_pos)
		if grid.has(bkey):
			continue

		if c.get("needs_replacement", false):
			var old_cell: Dictionary = grid[_pos_key(c["path_pos"])]
			old_cell["stage_id"] = str(c["replacement_stage"])
			old_cell["rotation"] = 0

		var branch_entry: String = OPPOSITE[str(c["branch_dir"])]
		if _place_dead_end(grid, bkey, branch_entry, all_stages):
			branch_cells.append(branch_pos)
			placed += 1

	return branch_cells


## Find a replacement stage that maintains entry/exit while adding a branch gate.
func _find_branch_replacement(candidates: Array[Dictionary], grid: Dictionary,
		path_pos: Vector2i, all_stages: Array[String],
		entry_dir: String, exit_dir: String, branch_dir: String,
		branch_pos: Vector2i) -> void:
	for stage_id in all_stages:
		var gates: Array[String] = _get_gates(stage_id)
		if entry_dir not in gates or exit_dir not in gates or branch_dir not in gates:
			continue
		# Check extra gates don't create orphans
		var valid := true
		for gate in gates:
			if gate == entry_dir or gate == exit_dir or gate == branch_dir:
				continue
			var offset: Vector2i = DIR_OFFSET[gate]
			var gr: int = path_pos.x + offset.x
			var gc: int = path_pos.y + offset.y
			if _is_valid_pos(gr, gc) and grid.has(_pos_key(Vector2i(gr, gc))):
				valid = false
				break
		if not valid:
			continue
		candidates.append({
			"path_pos": path_pos, "branch_dir": branch_dir,
			"branch_pos": branch_pos, "needs_replacement": true,
			"replacement_stage": stage_id, "replacement_rotation": 0,
		})
		break


## Place a dead-end (1-gate) stage at the given position.
## For single-gate stages, tries rotations [0, 90, 180, 270] so that the
## original gate direction rotates to match entry_dir.
func _place_dead_end(grid: Dictionary, pos_key: String, entry_dir: String,
		all_stages: Array[String]) -> bool:
	var shuffled: Array[String] = all_stages.duplicate()
	shuffled.shuffle()
	for stage_id in shuffled:
		var gates: Array[String] = _get_gates(stage_id)
		if gates.size() != 1:
			continue
		# Try each rotation to see if the single gate maps to entry_dir
		for rot in [0, 90, 180, 270]:
			if _rotate_direction(gates[0], rot) == entry_dir:
				grid[pos_key] = {
					"stage_id": stage_id, "rotation": rot,
					"entry_direction": entry_dir, "is_start": false,
					"is_end": false, "is_branch": true,
					"has_key": false, "key_for_cell": "",
					"is_key_gate": false, "key_gate_direction": "",
					"path_order": -1,
				}
				return true
	return false


## Add key-gates and place keys with reachability constraints.
func _add_key_gates(grid: Dictionary, path: Array[Vector2i],
		branch_cells: Array[Vector2i], target_count: int) -> void:
	# Map branch cells to the path order of their connected main-path cell
	var branch_to_path_order: Dictionary = {}
	for bp in branch_cells:
		var bcell: Dictionary = grid[_pos_key(bp)]
		var entry_dir: String = str(bcell.get("entry_direction", ""))
		if entry_dir.is_empty():
			continue
		var offset: Vector2i = DIR_OFFSET[entry_dir]
		var pkey := _pos_key(Vector2i(bp.x + offset.x, bp.y + offset.y))
		if grid.has(pkey):
			branch_to_path_order[_pos_key(bp)] = int(grid[pkey].get("path_order", -1))

	# Key-gate candidates: path cells after index 2, not end cell
	var gate_candidates: Array[Vector2i] = []
	for i in range(3, path.size()):
		var cell: Dictionary = grid[_pos_key(path[i])]
		if not cell.get("is_end", false):
			gate_candidates.append(path[i])
	gate_candidates.shuffle()

	var placed := 0
	for gate_pos in gate_candidates:
		if placed >= target_count:
			break

		var gate_cell: Dictionary = grid[_pos_key(gate_pos)]
		var gate_order: int = int(gate_cell.get("path_order", -1))

		# Key candidates: earlier main-path cells (not start, not already used)
		var main_candidates: Array[Vector2i] = []
		for p in path:
			var c: Dictionary = grid[_pos_key(p)]
			var order: int = int(c.get("path_order", -1))
			if order > 0 and order < gate_order and not c.get("has_key", false) \
					and not c.get("is_key_gate", false):
				main_candidates.append(p)

		# Branch cells reachable before the gate
		var branch_candidates: Array[Vector2i] = []
		for bp in branch_cells:
			var c: Dictionary = grid[_pos_key(bp)]
			if c.get("has_key", false):
				continue
			var connected_order: int = branch_to_path_order.get(_pos_key(bp), -1)
			if connected_order >= 0 and connected_order < gate_order:
				branch_candidates.append(bp)

		# Prefer branch cells (80% chance if available)
		var key_candidates: Array[Vector2i]
		if not branch_candidates.is_empty() and randf() < 0.8:
			key_candidates = branch_candidates
		elif not main_candidates.is_empty():
			key_candidates = main_candidates
		elif not branch_candidates.is_empty():
			key_candidates = branch_candidates
		else:
			continue

		var key_pos: Vector2i = key_candidates[randi() % key_candidates.size()]

		# Find which gate direction to lock
		var gates: Array[String] = _get_gates(str(gate_cell["stage_id"]))
		var exit_gates: Array[String] = []
		for g in gates:
			if g != str(gate_cell.get("entry_direction", "")):
				exit_gates.append(g)
		if exit_gates.is_empty():
			continue

		var locked_dir: String = exit_gates[randi() % exit_gates.size()]
		gate_cell["is_key_gate"] = true
		gate_cell["key_gate_direction"] = locked_dir

		var key_cell: Dictionary = grid[_pos_key(key_pos)]
		key_cell["has_key"] = true
		key_cell["key_for_cell"] = _pos_key(gate_pos)

		placed += 1


## Validate all gates have matching neighbors (no orphans).
func _validate_gates(grid: Dictionary) -> bool:
	for key in grid:
		var cell: Dictionary = grid[key]
		var pos: Vector2i = _parse_pos(key)
		var gates: Array[String] = _get_rotated_gates(cell)
		for dir in gates:
			var offset: Vector2i = DIR_OFFSET[dir]
			var nr: int = pos.x + offset.x
			var nc: int = pos.y + offset.y
			if not _is_valid_pos(nr, nc):
				continue
			var nkey := _pos_key(Vector2i(nr, nc))
			if not grid.has(nkey):
				return false
			var neighbor: Dictionary = grid[nkey]
			var n_gates: Array[String] = _get_rotated_gates(neighbor)
			if OPPOSITE[dir] not in n_gates:
				return false
	return true


## BFS from start to end, respecting key-gate locks. Returns true if reachable.
func _validate_reachability(grid: Dictionary, start_pos: Vector2i,
		end_pos: Vector2i) -> bool:
	var visited: Dictionary = {}
	var keys: Dictionary = {}
	var queue: Array[Vector2i] = [start_pos]

	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		var key := _pos_key(pos)
		if visited.has(key):
			continue
		visited[key] = true

		if not grid.has(key):
			continue
		var cell: Dictionary = grid[key]

		# Collect key
		if cell.get("has_key", false):
			var kfc: String = str(cell.get("key_for_cell", ""))
			if not kfc.is_empty():
				keys[kfc] = true

		var gates: Array[String] = _get_rotated_gates(cell)
		for dir in gates:
			if cell.get("is_key_gate", false) \
					and str(cell.get("key_gate_direction", "")) == dir \
					and not keys.has(key):
				continue

			var offset: Vector2i = DIR_OFFSET[dir]
			var npos := Vector2i(pos.x + offset.x, pos.y + offset.y)
			if not _is_valid_pos(npos.x, npos.y):
				continue
			var nkey := _pos_key(npos)
			if visited.has(nkey) or not grid.has(nkey):
				continue

			var neighbor: Dictionary = grid[nkey]
			var n_gates: Array[String] = _get_rotated_gates(neighbor)
			if OPPOSITE[dir] not in n_gates:
				continue

			queue.append(npos)

	return visited.has(_pos_key(end_pos))


## Convert internal grid to output cell list format.
func _to_output(grid: Dictionary, path: Array[Vector2i],
		branch_cells: Array[Vector2i], start_pos: Vector2i,
		end_pos: Vector2i) -> Dictionary:
	var cells: Array[Dictionary] = []

	for key in grid:
		var cell: Dictionary = grid[key]
		var pos: Vector2i = _parse_pos(key)
		var gates: Array[String] = _get_rotated_gates(cell)

		var connections: Dictionary = {}
		for dir in gates:
			var offset: Vector2i = DIR_OFFSET[dir]
			var nkey := _pos_key(Vector2i(pos.x + offset.x, pos.y + offset.y))
			if grid.has(nkey):
				connections[dir] = nkey

		var warp_edge := ""
		if cell.get("is_end", false):
			warp_edge = str(cell.get("key_gate_direction", ""))

		cells.append({
			"pos": key,
			"stage_id": str(cell["stage_id"]),
			"rotation": int(cell.get("rotation", 0)),
			"connections": connections,
			"is_start": cell.get("is_start", false),
			"is_end": cell.get("is_end", false),
			"is_branch": cell.get("is_branch", false),
			"has_key": cell.get("has_key", false),
			"key_for_cell": str(cell.get("key_for_cell", "")),
			"is_key_gate": cell.get("is_key_gate", false),
			"key_gate_direction": str(cell.get("key_gate_direction", "")),
			"warp_edge": warp_edge,
			"path_order": int(cell.get("path_order", -1)),
		})

	return {
		"cells": cells,
		"start_pos": _pos_key(start_pos),
		"end_pos": _pos_key(end_pos),
	}


## Fallback: generate a minimal straight-line grid.
func _generate_fallback(area: String, area_prefix: String = "s01") -> Dictionary:
	var prefix: String = "%s%s_" % [area_prefix, area]
	var cells: Array[Dictionary] = []

	# Start cell
	cells.append(_make_output_cell(
		Vector2i(0, 2), prefix + "sa1", 0, true, false, false, 0))

	# 3 middle cells (straight N/S stages)
	var mid_stages: Array[String]
	if area == "a":
		mid_stages = [prefix + "ga1", prefix + "ib1", prefix + "ib2"]
	else:
		mid_stages = [prefix + "ib1", prefix + "ib2", prefix + "ic1"]
	for i in range(3):
		cells.append(_make_output_cell(
			Vector2i(i + 1, 2), mid_stages[i], 0, false, false, false, i + 1))

	# End cell at row 4 — uses a N/S stage, south exits outside grid
	var end_stage: String = prefix + "ga1" if area == "a" else prefix + "sa1"
	var end := _make_output_cell(Vector2i(4, 2), end_stage, 0, false, true, false, 4)
	end["warp_edge"] = "south"
	cells.append(end)

	# Build connections
	for i in range(cells.size()):
		if i > 0:
			cells[i]["connections"]["north"] = str(cells[i - 1]["pos"])
		if i < cells.size() - 1:
			cells[i]["connections"]["south"] = str(cells[i + 1]["pos"])

	return {"cells": cells, "start_pos": "0,2", "end_pos": "4,2"}


func _make_output_cell(pos: Vector2i, stage_id: String, rotation: int,
		is_start: bool, is_end: bool, is_branch: bool, path_order: int) -> Dictionary:
	return {
		"pos": _pos_key(pos),
		"stage_id": stage_id,
		"rotation": rotation,
		"connections": {},
		"is_start": is_start,
		"is_end": is_end,
		"is_branch": is_branch,
		"has_key": false,
		"key_for_cell": "",
		"is_key_gate": false,
		"key_gate_direction": "",
		"warp_edge": "",
		"path_order": path_order,
	}


func _is_valid_pos(row: int, col: int) -> bool:
	return row >= 0 and row < grid_size and col >= 0 and col < grid_size


func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func _parse_pos(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
