extends RefCounted
## GridGenerator — generates 5x5 grid layouts with branches and key-gates.
## Faithfully ports psz-sketch's GridViewer.tsx algorithm.
## Area-agnostic: reads portal directions from *_config.json when available,
## falls back to hardcoded GATES for valley (s01).

## One RNG per generator instance so a field's layout and its fights come from
## the same stream. EVERY random choice in this file must go through it —
## Array.shuffle(), randi() and randf() read Godot's global RNG, which cannot be
## seeded per generator, and a single one of them left in makes the whole field
## irreproducible. That matters because reproducing a field from a seed is how
## we compare our output against the game's own generation.
var _rng := RandomNumberGenerator.new()

## Cells the retile pass could not make exact, from the last generate() call.
## Non-zero means a door somewhere still leads nowhere — see
## `_retile_no_spare_doors`, which explains the one case that is expected
## (the `b`-area start tile) and why it is counted rather than hidden.
var _spare_door_cells: int = 0


## Reproduce a specific field. Same seed + same area + same params = same field,
## rooms, rotations, gates, keys and enemy waves included.
func set_seed(value: int) -> void:
	_rng.seed = value


## Fisher-Yates through _rng — Array.shuffle() would use the global RNG.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

const DIRECTIONS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const DIR_OFFSET := {
	"north": Vector2i(-1, 0), "south": Vector2i(1, 0),
	"east": Vector2i(0, 1), "west": Vector2i(0, -1),
}


## {game_direction: portal_id} for a placed cell — the same shape the static
## field files carry. The field controller can fall back to the stage config
## without this, but the autopilot reads cell["portals"] directly to choose an
## exit, so a generated cell that omits them cannot be driven.
func _baked_portals(stage_id: String, rotation_deg: int) -> Dictionary:
	_ensure_unified_config()
	var cfg: Dictionary = _unified_config.get(stage_id, {})
	var out: Dictionary = {}
	for portal in cfg.get("portals", []):
		var base_dir: String = str(portal.get("direction", ""))
		if base_dir.is_empty():
			continue
		out[StageRotation.rotate_dir(base_dir, rotation_deg)] = str(portal.get("id", ""))
	if not cfg.get("defaultSpawn", {}).is_empty():
		out["default"] = "default"
	return out


## Gate directions a stage presents at each rotation, as {rotation: [dirs]}.
##
## Room models have a FIXED door set; the layout picks a rotation whose doors
## cover the connections the cell needs. The static builder in
## scripts/tools/refield does exactly this ("rotate config doors until they
## cover the needed slots"), but the runtime generator never rotated while
## laying the main path — it only accepted rooms whose authored orientation
## already matched, which is why every attempt failed for every area.
func _gates_at_rotation(stage_id: String, steps: int) -> Array[String]:
	var out: Array[String] = []
	for g in _get_gates(stage_id):
		out.append(StageRotation.rotate_dir(g, steps * 90))
	return out


## Rotations (0..3) at which `stage_id` has a door on `entry_dir` and exactly one
## usable exit, plus that exit direction. `exit_outside` picks whether the exit
## must leave the grid (end cell) or land on an empty in-grid cell (middle).
##
## Extra doors beyond entry+exit are allowed HERE, and then removed. This runs
## while the path is still being laid, when a cell's final degree is not yet
## known — branches attach later — so it accepts any rotation that COVERS what
## the cell needs. `_retile_no_spare_doors` runs once the topology is final and
## swaps each tile for one whose doors are exactly its connections.
##
## The old comment said a spare door is "inert geometry, which is already true
## of the static fields", and that it was a divergence we were choosing. Both
## halves are retired. It is not inert to a player: no gate, no loading trigger,
## nothing behind it, and no way to tell it apart from a real exit until you
## walk into it — 182 door-slots across the 392-cell dump carried one.
##
## psz-re's sys.field-doorways.json exists to answer exactly this (it cites our
## #581): there is never a spare door. Room shape comes from the cell's DEGREE
## and nothing else — 4 -> x, 3 -> t, 2 -> l or i, 1 -> s/g/n — and the degree
## counter is incremented in the same function that links two neighbours,
## bumping parent and child together, so doors == connections by construction.
## Nothing is ever sealed; what the game closes is a GATE, always on a live
## connection (417 of 417 gated doorways still hold their neighbour).
## See /states/field-gates.
func _fitting_rotations(stage_id: String, entry_dir: String, row: int, col: int,
		grid: Dictionary, exit_outside: bool) -> Array[Dictionary]:
	var fits: Array[Dictionary] = []
	for steps in range(4):
		var gates: Array[String] = _gates_at_rotation(stage_id, steps)
		if entry_dir not in gates:
			continue
		for g in gates:
			if g == entry_dir:
				continue
			var off: Vector2i = DIR_OFFSET[g]
			var er: int = row + off.x
			var ec: int = col + off.y
			var inside: bool = _is_valid_pos(er, ec)
			if exit_outside:
				if inside:
					continue
			else:
				if not inside or grid.has(_pos_key(Vector2i(er, ec))):
					continue
			fits.append({"stage": stage_id, "rotation": steps, "exit_dir": g})
	return fits


## Get gate directions in grid-space for a cell, applying its rotation.
func _get_rotated_gates(cell: Dictionary) -> Array[String]:
	var stage_id: String = str(cell.get("stage_id", ""))
	var rotation: int = int(cell.get("rotation", 0))
	var original: Array[String] = _get_gates(stage_id)
	if rotation == 0:
		return original
	var rotated: Array[String] = []
	for g in original:
		rotated.append(StageRotation.rotate_dir(g, rotation))
	return rotated

## Area configuration: maps area_id → prefix, folder, display name.
const AREA_CONFIG := {
	"gurhacia": {"prefix": "s01", "folder": "valley", "name": "Valley"},
	"ozette":   {"prefix": "s02", "folder": "wetlands", "name": "Wetlands"},
	"rioh":     {"prefix": "s03", "folder": "snowfield", "name": "Snowfield"},
	"makara":   {"prefix": "s04", "folder": "makara", "name": "Ruins"},
	"paru":     {"prefix": "s05", "folder": "paru", "name": "Forgotten City"},
	"arca":     {"prefix": "s06", "folder": "arca", "name": "Moon Facility"},
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


## Static cache for unified stage config (loaded once, shared across all generators).
static var _unified_config: Dictionary = {}


## Load the unified config file on first access.
static func _ensure_unified_config() -> void:
	if not _unified_config.is_empty():
		return
	var path := "res://data/stage_configs/unified-stage-configs.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_unified_config = json.data as Dictionary
	file.close()


## Load gates dict for an area from the unified stage config.
## Falls back to hardcoded GATES if no portal data found.
func load_gates(area_id: String) -> Dictionary:
	if _gates_cache.has(area_id):
		return _gates_cache[area_id]

	var cfg: Dictionary = AREA_CONFIG.get(area_id, {})
	if cfg.is_empty():
		_gates_cache[area_id] = GATES
		return GATES

	var prefix: String = cfg["prefix"]

	# Load unified config
	_ensure_unified_config()
	if _unified_config.is_empty():
		_gates_cache[area_id] = GATES
		return GATES

	# Extract gate directions from portal data for stages matching this area's prefix
	var gates := {}
	for stage_id in _unified_config:
		if not str(stage_id).begins_with(prefix):
			continue
		var stage_cfg: Dictionary = _unified_config[stage_id]
		var portals: Array = stage_cfg.get("portals", [])
		var dirs: Array[String] = []
		for portal in portals:
			var d: String = str(portal.get("direction", ""))
			if not d.is_empty() and d not in dirs:
				dirs.append(d)
		if not dirs.is_empty():
			gates[stage_id] = dirs

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
	# ENTER FROM THE SOUTH, LEAVE TO THE NORTH. The transition room is a
	# straight corridor between area A and area B, and it always runs the same
	# way round: you arrive at its south door and walk out its north one.
	#
	# `warp_edge` is the EXIT, and the spawn resolver puts the player at the
	# OPPOSITE portal (valley_field_controller: "opposite of warp_edge"). So
	# "south" here meant arriving at the north door and walking back out south,
	# i.e. through the corridor backwards — which is what kion hit in play.
	e_cell["warp_edge"] = "north"
	e_cell["objects"] = FieldPopulation.objects_for_single_room(e_stage, _rng)
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
	_ensure_unified_config()
	if not _unified_config.has(z_stage):
		z_stage = "%sa_na1" % prefix
	var z_cell := _make_output_cell(Vector2i(0, 0), z_stage, 0, true, true, false, 0)
	z_cell["warp_edge"] = "south"
	# The boss is read from the assignment table, not picked: s01z_na1 names
	# boss_dragon, s02z_na1 boss_octopus, s05z_na1 boss_robot, and so on.
	z_cell["objects"] = FieldPopulation.objects_for_single_room(z_stage, _rng)
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
func _try_generate(area: String, path_length: int, _key_gates_count: int,
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
			# End cell exits the grid (that edge becomes the section warp);
			# a middle cell exits onto the next empty cell.
			candidates.append_array(_fitting_rotations(
				stage_id, entry_dir, next_row, next_col, grid, is_last_cell))

		if candidates.is_empty():
			# Try to end early if we have enough cells
			if path.size() >= 3:
				if _try_place_end_cell(grid, path, all_stages, next_row, next_col, entry_dir):
					break
			break

		var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]

		grid[next_key] = {
			"stage_id": str(chosen["stage"]),
			"rotation": int(chosen["rotation"]) * 90,
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

	# No spare doors: retile so every door leads somewhere. Runs after the
	# topology is final (path, end cell, branches) because it needs each cell's
	# finished connection set, and before validation because it changes which
	# tile a cell shows.
	var unfixed: int = _retile_no_spare_doors(grid, all_stages)
	if unfixed > 0:
		_spare_door_cells = unfixed

	# The gate economy (#595). AFTER the retile, because a gate is always on a
	# live connection and the retile is what settles which doors those are.
	#
	# `key_gates_count` from the difficulty config is NO LONGER READ. The budget
	# is (rooms - 2) * 35 / 100 off the section's own room count, which is the
	# measured rule, and it supersedes a hand-set count that had normal
	# difficulty at zero key gates in both sections — the original has them at
	# every difficulty. The config key is left in place because the field
	# editor and the static builders still carry it.
	if not _assign_door_attributes(grid, _pos_key(path[0])):
		return {}

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
		var fits: Array[Dictionary] = _fitting_rotations(
			stage_id, entry_dir, row, col, grid, true)
		if fits.is_empty():
			continue
		var fit: Dictionary = fits[_rng.randi_range(0, fits.size() - 1)]
		grid[key] = {
			"stage_id": stage_id, "rotation": int(fit["rotation"]) * 90,
			"entry_direction": entry_dir, "is_start": false,
			"is_end": true, "is_branch": false,
			"has_key": false, "key_for_cell": "",
			"is_key_gate": false, "key_gate_direction": str(fit["exit_dir"]),
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
		for steps in range(4):
			var gates: Array[String] = _gates_at_rotation(stage_id, steps)
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
					if OPPOSITE[gate] not in _get_rotated_gates(neighbor):
						has_orphan = true
						break
			if has_orphan or warp_dir.is_empty():
				continue
			end_cell["stage_id"] = stage_id
			end_cell["rotation"] = steps * 90
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

	_shuffle(candidates)
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
	_shuffle(shuffled)
	for stage_id in shuffled:
		var gates: Array[String] = _get_gates(stage_id)
		if gates.size() != 1:
			continue
		# Try each rotation to see if the single gate maps to entry_dir
		for rot in [0, 90, 180, 270]:
			if StageRotation.rotate_dir(gates[0], rot) == entry_dir:
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


# ── The gate economy (#595) ────────────────────────────────────────────────
# Implements /states/field-gates. The contract page is normative; this is the
# code that has to match it, and the seeded tests are pinned against the page
# rather than against this function.

## Door attributes, one per direction. The values are the original's, at cell
## +0x14+dir — kept as its numbers rather than an enum of our own so a capture
## and a generated field can be compared without a translation table.
const ATTR_OPEN := 0
const ATTR_ONE_KEY := 1
const ATTR_TWO_KEY := 2
const ATTR_ENEMY_DEFEAT := 4

## params[5]: budget = (rooms - 2) * 35 / 100, integer division, a HARD cap.
const KEY_GATE_BUDGET_PCT := 35

## params[7]: chance a key gate is a TWO-key gate.
##
## The original rolls params[6] = 30 instead for a room carrying flag 0x20, and
## we have no equivalent of that flag: psz-re's topology reads 0x20 as marking a
## cell created as one of a PAIR during the frontier walk, and this generator
## does not build pairs. Rather than invent a mapping, every room takes the
## non-0x20 arm. Recorded as a divergence in /states/field-gates, not hidden —
## the visible effect is that two-key gates are rarer here than in the original.
const TWO_KEY_CHANCE := 10

## params[8], the RUNTIME value.
##
## NOT the 10 that level_topology_builder.json lists as the table default. The
## runtime block reads 75, and the capture split — 268 rooms gating every
## eligible exit, 106 gating none, 0 mixed — is 72%, which is 75 with sampling
## noise and nothing like 10.
const ENEMY_DEFEAT_CHANCE := 75

## Keys scatter within BFS depth < 2 of the gated room, and a room drops out of
## the pool once it holds 2 — which is why no captured room ever holds more.
const KEY_SCATTER_DEPTH := 2
const KEYS_PER_ROOM := 2


## Assign a door attribute to every doorway in the section.
##
## Runs AFTER the retile, because it needs each cell's final connection set: a
## gate is always on a live connection, and before the retile a cell can still
## be showing a door that leads nowhere.
##
## Returns false when the result is not solvable, so `_try_generate` can discard
## the attempt and roll again rather than shipping a field that cannot be
## finished. That is the backstop; the placement below is meant to keep it
## solvable by construction, and the seeded sweep is what proves it does.
func _assign_door_attributes(grid: Dictionary, start_key: String,
		allow_key_gates: bool = true) -> bool:
	for key in grid:
		grid[key]["door_attributes"] = {}
		grid[key]["key_count"] = 0

	if allow_key_gates:
		_place_key_gates(grid)
	_place_enemy_defeat_gates(grid)
	_sync_legacy_gate_fields(grid)
	return _field_is_solvable(grid, start_key)


## The connections a cell actually has, as {dir: neighbour_key}.
func _cell_connections(grid: Dictionary, key: String) -> Dictionary:
	var cell: Dictionary = grid[key]
	var pos: Vector2i = _parse_pos(key)
	var out: Dictionary = {}
	for dir in _get_rotated_gates(cell):
		var off: Vector2i = DIR_OFFSET[dir]
		var nkey := _pos_key(Vector2i(pos.x + off.x, pos.y + off.y))
		if grid.has(nkey):
			out[dir] = nkey
	return out


## The direction that leads back toward the start, or "" for the start itself.
##
## The original never gates this door — 0 of 592 rooms — and an implementation
## has to preserve that, because it is what makes a key detour possible: you
## must always be able to walk back out of a room to fetch what it wants.
func _way_back_dir(grid: Dictionary, key: String) -> String:
	return str(grid[key].get("entry_direction", ""))


## Every room whose route from the start passes through `key`'s door `dir`.
## In a tree that is exactly the neighbour's subtree, and it is what a key must
## NOT be placed in: a key behind its own gate cannot be fetched.
func _behind_door(grid: Dictionary, key: String, dir: String) -> Dictionary:
	var conns: Dictionary = _cell_connections(grid, key)
	if not conns.has(dir):
		return {}
	var out: Dictionary = {}
	var queue: Array[String] = [str(conns[dir])]
	out[str(conns[dir])] = true
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for ndir in _cell_connections(grid, cur):
			var nkey: String = str(_cell_connections(grid, cur)[ndir])
			if nkey == key or out.has(nkey):
				continue
			out[nkey] = true
			queue.append(nkey)
	return out


## Rooms within BFS depth < 2 of the gated room, skipping start and goal, and
## skipping anything behind the gate being placed.
func _key_scatter_pool(grid: Dictionary, gate_key: String, locked_dir: String) -> Array[String]:
	var blocked: Dictionary = _behind_door(grid, gate_key, locked_dir)
	var pool: Array[String] = []
	var seen: Dictionary = {gate_key: 0}
	var queue: Array[String] = [gate_key]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var depth: int = int(seen[cur])
		var cell: Dictionary = grid[cur]
		var skip: bool = blocked.has(cur) \
			or cell.get("is_start", false) or cell.get("is_end", false)
		if not skip and int(cell.get("key_count", 0)) < KEYS_PER_ROOM:
			pool.append(cur)
		if depth + 1 >= KEY_SCATTER_DEPTH:
			continue
		for ndir in _cell_connections(grid, cur):
			var nkey: String = str(_cell_connections(grid, cur)[ndir])
			if seen.has(nkey) or blocked.has(nkey):
				continue
			seen[nkey] = depth + 1
			queue.append(nkey)
	return pool


## The key-gate pass: budget, eligibility, the one-vs-two roll, then scatter.
func _place_key_gates(grid: Dictionary) -> void:
	var budget: int = int((grid.size() - 2) * KEY_GATE_BUDGET_PCT / 100.0)
	if budget <= 0:
		return

	var candidates: Array[String] = []
	for key in grid:
		var cell: Dictionary = grid[key]
		if cell.get("is_start", false) or cell.get("is_end", false):
			continue
		candidates.append(key)
	_shuffle(candidates)

	var spent: int = 0
	for key in candidates:
		if spent >= budget:
			break
		if not _gate_is_eligible(grid, key):
			continue

		# Only a FORWARD door can be gated — never the way back.
		var forward: Array[String] = []
		var way_back: String = _way_back_dir(grid, key)
		for dir in _cell_connections(grid, key):
			if dir != way_back:
				forward.append(dir)
		if forward.is_empty():
			continue
		var locked_dir: String = forward[_rng.randi_range(0, forward.size() - 1)]

		# One key or two. A two-key gate additionally requires that two keys can
		# actually be placed for it, so the roll can be overruled by the pool.
		var want: int = ATTR_TWO_KEY if _rng.randi_range(0, 99) < TWO_KEY_CHANCE else ATTR_ONE_KEY
		var pool: Array[String] = _key_scatter_pool(grid, key, locked_dir)
		if pool.is_empty():
			continue
		var capacity: int = 0
		for pkey in pool:
			capacity += KEYS_PER_ROOM - int(grid[pkey].get("key_count", 0))
		if want > capacity:
			want = ATTR_ONE_KEY
		if want > capacity:
			continue

		# Commit: the door, then exactly as many keys as it demands.
		grid[key]["door_attributes"][locked_dir] = want
		_scatter_keys(grid, pool, want, key)
		spent += 1


## A room may carry at most one gate, and NEVER next to another gated room —
## which is what stops a field turning into a corridor of locks.
func _gate_is_eligible(grid: Dictionary, key: String) -> bool:
	if not _gates_on(grid, key).is_empty():
		return false
	for dir in _cell_connections(grid, key):
		var nkey: String = str(_cell_connections(grid, key)[dir])
		if not _gates_on(grid, nkey).is_empty():
			return false
	return true


## Directions of this room that carry a KEY gate (enemy-defeat does not count
## toward the never-adjacent rule — it is a different pass with no budget).
func _gates_on(grid: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	var attrs: Dictionary = grid[key].get("door_attributes", {})
	for dir in attrs:
		var a: int = int(attrs[dir])
		if a == ATTR_ONE_KEY or a == ATTR_TWO_KEY:
			out.append(str(dir))
	return out


## Place `count` keys across the pool, at most KEYS_PER_ROOM in any one room.
func _scatter_keys(grid: Dictionary, pool: Array[String], count: int, gate_key: String) -> void:
	var shuffled: Array[String] = pool.duplicate()
	_shuffle(shuffled)
	var placed: int = 0
	while placed < count:
		var progressed := false
		for key in shuffled:
			if placed >= count:
				break
			if int(grid[key].get("key_count", 0)) >= KEYS_PER_ROOM:
				continue
			grid[key]["key_count"] = int(grid[key].get("key_count", 0)) + 1
			grid[key]["has_key"] = true
			# Kept for the runtime, which is still key-gate-per-cell. Step 3 of
			# /states/field-gates replaces this with the attribute table.
			if str(grid[key].get("key_for_cell", "")).is_empty():
				grid[key]["key_for_cell"] = gate_key
			placed += 1
			progressed = true
		if not progressed:
			break


## The enemy-defeat pass. ONE roll per ROOM, not per door.
##
## If it passes, every direction that has a neighbour, is not the way back, and
## is not already attributed gets attribute 4. So a room's forward exits are all
## gated or none are — 268 / 106 / 0 mixed in the capture set. A per-door roll
## would look similar in play and be wrong.
func _place_enemy_defeat_gates(grid: Dictionary) -> void:
	for key in grid:
		var cell: Dictionary = grid[key]
		if cell.get("is_start", false) or cell.get("is_end", false):
			continue
		if _rng.randi_range(0, 99) >= ENEMY_DEFEAT_CHANCE:
			continue
		var way_back: String = _way_back_dir(grid, key)
		var attrs: Dictionary = cell["door_attributes"]
		for dir in _cell_connections(grid, key):
			if dir == way_back or attrs.has(dir):
				continue
			attrs[dir] = ATTR_ENEMY_DEFEAT


## Keep the pre-#595 per-cell fields in step with the attribute table.
##
## The runtime still reads `is_key_gate` / `key_gate_direction` / `has_key`, and
## replacing that is step 3 of /states/field-gates rather than this PR. Deriving
## them here means the generator has ONE source of truth and the old consumers
## keep working unchanged.
func _sync_legacy_gate_fields(grid: Dictionary) -> void:
	for key in grid:
		var cell: Dictionary = grid[key]
		var key_gates: Array[String] = _gates_on(grid, key)
		cell["is_key_gate"] = not key_gates.is_empty()
		cell["required_keys"] = int(cell["door_attributes"][key_gates[0]]) \
			if not key_gates.is_empty() else 0
		# The end cell's `key_gate_direction` is its warp edge and is load-bearing
		# elsewhere; never overwrite it.
		if not cell.get("is_end", false):
			cell["key_gate_direction"] = key_gates[0] if not key_gates.is_empty() else ""
		cell["has_key"] = int(cell.get("key_count", 0)) > 0


## Can the field actually be finished? A real traversal, not an accounting rule.
##
## Walks from the start with a key purse, opening what it can afford and
## re-walking whenever a key is picked up, until nothing new opens. The field is
## solvable when the goal is reachable. This is the headline assertion
## /states/field-gates asks for, and it is deliberately a SIMULATION rather than
## the original's chain-balance check: the chain rule is what the game uses to
## keep itself honest while placing, and this is the independent question of
## whether the result can be played.
func _field_is_solvable(grid: Dictionary, start_key: String) -> bool:
	if not grid.has(start_key):
		return false
	var goal_key: String = ""
	for key in grid:
		if grid[key].get("is_end", false):
			goal_key = key
			break
	if goal_key.is_empty():
		return true

	var reached: Dictionary = {start_key: true}
	var keys_held: int = 0
	var changed := true
	while changed:
		changed = false
		keys_held = 0
		for key in reached:
			keys_held += int(grid[key].get("key_count", 0))
		var spent: int = 0
		for key in reached.keys():
			var attrs: Dictionary = grid[key].get("door_attributes", {})
			for dir in _cell_connections(grid, key):
				var nkey: String = str(_cell_connections(grid, key)[dir])
				if reached.has(nkey):
					continue
				var attr: int = int(attrs.get(dir, ATTR_OPEN))
				# An enemy-defeat gate always opens: clearing the room is
				# something the player can always do, so it never blocks
				# solvability. Only key gates can.
				var cost: int = attr if attr == ATTR_ONE_KEY or attr == ATTR_TWO_KEY else 0
				if cost > keys_held - spent:
					continue
				spent += cost
				reached[nkey] = true
				changed = true
	return reached.has(goal_key)


## Retile every cell so its doors are EXACTLY its connections. Returns how many
## cells could not be fixed (0 = no spare doors anywhere).
##
## A spare door is a door with nothing behind it: no gate, no loading trigger,
## no neighbouring room. `_validate_gates` called that "inert, not a failure",
## and `_fitting_rotations` accepted any rotation that COVERED the directions a
## cell needed. Measured over the committed dump of this generator, that left a
## door leading nowhere in 234 of 392 cells — 60% — and in play it reads as a
## broken exit, because the player cannot tell it apart from a real one.
##
## The original has no such thing. psz-re's sys.field-doorways: room shape comes
## from the cell's DEGREE and nothing else, and the degree counter is bumped in
## the same function that links two neighbours, so doors == connections BY
## CONSTRUCTION. Nothing is ever sealed either — what the game closes is a gate,
## always on a live connection. See /states/field-gates.
##
## THIS PASS PRESERVES THE GRAPH EXACTLY. `needed` is the cell's existing
## connections — the doors it already has that lead to a placed cell — never raw
## adjacency, so a door is only ever DROPPED, never added. Two cells that sit
## side by side without a door between them keep their wall. That matters:
## adding doors on adjacency would create edges, and an edge that closes a loop
## breaks the "layout is a tree" invariant every field is validated against.
##
## The goal keeps its warp exit, which is a door with no cell behind it on
## purpose — it leaves the field rather than leading nowhere.
##
## START CELLS ARE RETILED TOO, with one exception that is about spawning rather
## than doors: a stage carrying a `defaultSpawn` is where the player materialises
## when they warp into the section from outside, and no other tile has one, so
## swapping it would leave them with nowhere to stand. Only `sNNa_sa1` and
## `sNNz_na1` carry one, and `sNNa_sa1` has a single south door, so it is already
## exact and never needs retiling. `sNNb_sa1` carries north+south and sits on row
## 0, which used to leave its north door hanging off-grid in every `b` section —
## it has no default spawn (a `b` section is entered by warp from the transition
## room), so it retiles like anything else.
func _retile_no_spare_doors(grid: Dictionary, all_stages: Array[String]) -> int:
	var unfixed: int = 0

	for key in grid:
		var cell: Dictionary = grid[key]
		if _carries_default_spawn(str(cell.get("stage_id", ""))):
			if not _spare_dirs(grid, key, cell).is_empty():
				unfixed += 1
			continue

		var needed: Array[String] = []
		for dir in _get_rotated_gates(cell):
			if _leads_somewhere(grid, key, cell, dir):
				needed.append(dir)
		if _spare_dirs(grid, key, cell).is_empty():
			continue

		var pick: Dictionary = _tile_with_exact_doors(
			all_stages, needed, str(cell.get("stage_id", "")))
		if pick.is_empty():
			unfixed += 1
			continue
		cell["stage_id"] = str(pick["stage"])
		# DEGREES, not steps. `_tile_with_exact_doors` works in quarter turns
		# because `_gates_at_rotation` does, but every consumer of a cell's
		# `rotation` treats it as degrees — `StageRotation.rotate_dir` divides by
		# 90, the field controller reads it into `_rotation_deg`, and the static
		# field JSONs built from RE data carry 0/90/180/270. Storing steps here
		# silently placed the tile unrotated.
		cell["rotation"] = int(pick["rotation"]) * 90
	return unfixed


## Is this stage the one the player warps INTO for its section? Those keep their
## tile no matter what their doors look like — see `_retile_no_spare_doors`.
func _carries_default_spawn(stage_id: String) -> bool:
	if stage_id.is_empty():
		return false
	_ensure_unified_config()
	var cfg: Dictionary = _unified_config.get(stage_id, {})
	return not cfg.get("defaultSpawn", {}).is_empty()


## Doors on this cell that lead nowhere — the ones this pass exists to remove.
func _spare_dirs(grid: Dictionary, key: String, cell: Dictionary) -> Array[String]:
	var spare: Array[String] = []
	for dir in _get_rotated_gates(cell):
		if not _leads_somewhere(grid, key, cell, dir):
			spare.append(dir)
	return spare


## True when a door opens onto a placed cell, or is one of the section's two
## warps — the goal's way out, or the start's way back.
func _leads_somewhere(grid: Dictionary, key: String, cell: Dictionary, dir: String) -> bool:
	if cell.get("is_end", false) and dir == str(cell.get("key_gate_direction", "")):
		return true
	if dir == _entry_warp_dir(grid, key, cell):
		return true
	var pos: Vector2i = _parse_pos(key)
	var off: Vector2i = DIR_OFFSET[dir]
	return grid.has(_pos_key(Vector2i(pos.x + off.x, pos.y + off.y)))


## The start room's way BACK, or "" when the section has none.
##
## A `b` section is entered by warp from the transition room, and the room you
## land in has to show you where you came from — kion's rule from play: "the B
## section should ALWAYS start with a room with a door that implies leading back
## to valley E". That door has no cell behind it, but it is not a dead door: it
## is the arrival warp, the mirror of the goal's exit warp, and the spawn
## resolver already puts the player at it (valley_field_controller's "fallback
## north portal, facing gate"). Treating it as a spare and retiling it away is
## what dropped players into a dead end.
##
## An `a` section has none — it is entered from the city through `sa1`'s
## defaultSpawn, and that tile carries a single south door.
func _entry_warp_dir(grid: Dictionary, key: String, cell: Dictionary) -> String:
	if not cell.get("is_start", false):
		return ""
	var pos: Vector2i = _parse_pos(key)
	for dir in _get_rotated_gates(cell):
		var off: Vector2i = DIR_OFFSET[dir]
		if not grid.has(_pos_key(Vector2i(pos.x + off.x, pos.y + off.y))):
			return dir
	return ""


## A stage + rotation whose doors are exactly `needed`, or {} if none exists.
## The cell's current stage is tried first so a room keeps its look when only
## the rotation was wrong; otherwise the pool is shuffled, so which tile stands
## in is part of the seeded roll rather than dictated by dictionary order.
func _tile_with_exact_doors(all_stages: Array[String], needed: Array[String],
		prefer_stage: String) -> Dictionary:
	var want: Array[String] = needed.duplicate()
	want.sort()

	var pool: Array[String] = []
	if not prefer_stage.is_empty():
		pool.append(prefer_stage)
	var rest: Array = all_stages.duplicate()
	_shuffle(rest)
	for s in rest:
		if str(s) != prefer_stage:
			pool.append(str(s))

	for stage_id in pool:
		for steps in range(4):
			var doors: Array[String] = _gates_at_rotation(stage_id, steps)
			if doors.size() != want.size():
				continue
			doors.sort()
			if doors == want:
				return {"stage": stage_id, "rotation": steps}
	return {}


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
				# Nothing placed there — the door leads nowhere and the runtime
				# builds no trigger for it (gate triggers come from `connections`
				# only). Inert, not a failure.
				continue
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
func _to_output(grid: Dictionary, _path: Array[Vector2i],
		_branch_cells: Array[Vector2i], start_pos: Vector2i,
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
			# The gate economy's own output: {direction: attribute}, using the
			# original's values (0 open, 1 one-key, 2 two-key, 4 enemy-defeat).
			# The three legacy fields above are DERIVED from this — see
			# _sync_legacy_gate_fields — and step 3 of /states/field-gates
			# retires them once portal_gate_manager reads the table directly.
			"door_attributes": cell.get("door_attributes", {}).duplicate(),
			"key_count": int(cell.get("key_count", 0)),
			# How many keys this cell's gate demands. The runtime already honours
			# it — valley_field_controller reads it into KeyGate.required_keys and
			# portal_gate_manager spawns that many pickups sharing one key id — so
			# a TWO-key gate is a real two-key gate today rather than waiting for
			# step 3 of /states/field-gates.
			"required_keys": int(cell.get("required_keys", 0)),
			"warp_edge": warp_edge,
			# The start room's way back to wherever the player warped in from.
			# "" for an `a` section, which is entered through a defaultSpawn.
			"entry_warp_edge": _entry_warp_dir(grid, key, cell),
			"path_order": int(cell.get("path_order", -1)),
			"portals": _baked_portals(str(cell["stage_id"]), int(cell.get("rotation", 0))),
			"objects": FieldPopulation.objects_for_cell(
				str(cell["stage_id"]),
				cell.get("is_start", false),
				cell.get("is_end", false),
				_rng,
				int(cell.get("path_order", -1)),
			),
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
		"portals": _baked_portals(stage_id, rotation),
		# Transition / boss / tower rooms: the caller fills these where the RE
		# assignment has a row for them; a bare cell carries an empty list so
		# the spawner never sees a missing key.
		"objects": [],
	}


func _is_valid_pos(row: int, col: int) -> bool:
	return row >= 0 and row < grid_size and col >= 0 and col < grid_size


func _pos_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func _parse_pos(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
