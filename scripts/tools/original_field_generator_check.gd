extends SceneTree
## Headless check: OriginalFieldGenerator against the 14 console fixtures.
##
## Stage 1 (growth) runs the generator from each fixture's
## generation_start_state and compares target, branches, room count and the
## normalized cell set — the same assertions the Python reference
## (scripts/tools/field_gen_reference.py) scores 14/14 on.
## Stage 2 (transcription) anchors the draw stream on the fixture's first
## per-room seed (the unmodelled gate stage's cost is searched from the
## growth-end state, exactly like the Python anchor) and verifies every seed
## and layout category, including the picker-room variant-draw skip.
##
## Run: godot --headless --path . --script res://scripts/tools/original_field_generator_check.gd

const SHAPE_LETTERS := "iltxnsg"
const CLASS_LETTERS := "abcdr"
const VARIANTS := [
	[[1, 1], [1, 2], [2, 1], [2, 3]],
	[[1, 1], [1, 3], [2, 1], [2, 2]],
	[[1, 3], [2, 3], [3, 1], [3, 2]],
	[[1, 2]],
	[[0, 1], [1, 2], [2, 2]],
	[[0, 1]],
	[[0, 1]],
]
const LAYOUT_BANDS := [[50, 20, 20, 10], [40, 20, 20, 20], [25, 25, 25, 25]]
const PICKER_CODES := ["na1", "nc2", "nr1", "nr2", "nr3", "nr4", "nr5", "nr6"]


func _init() -> void:
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/re_reference/field_fixtures.json"))["fixtures"]
	var growth_ok := 0
	var transcribed := 0
	var seeds_ok := 0
	var layouts_ok := 0
	var total_rooms := 0
	var fails := 0
	for f in fixtures:
		var state: int = int(f["input"]["generation_start_state"].hex_to_int())
		var lo := state & 0xFFFFFFFF
		var hi := state >> 32
		var params: Array = f["input"]["params"]
		var gen := OriginalFieldGenerator.new(lo, hi, f["stage"], params)
		gen.run()
		var want_cells := {}
		for r in f["rooms"]:
			want_cells[Vector2i(r["xy"][0], r["xy"][1])] = true
		var origin := gen.normalized_origin()
		var cells_match := gen.list.size() == f["rooms"].size()
		if cells_match:
			for room in gen.list:
				if not want_cells.has(Vector2i(room.x - origin.x, room.y - origin.y)):
					cells_match = false
					break
		var target_match: bool = gen.target == f["drawn"]["target"] \
			and gen.branches_drawn == f["drawn"]["branches"]
		if cells_match and target_match:
			growth_ok += 1
		else:
			fails += 1
			push_error("%s: growth mismatch (target %d want %s, rooms %d want %d, cells %s)" % [
				f["id"], gen.target, str(f["drawn"]["target"]), gen.list.size(),
				f["rooms"].size(), str(cells_match)])
			continue
		var res := _anchor(f, gen)
		if res == null:
			fails += 1
			push_error("%s: transcription not anchored" % f["id"])
			continue
		transcribed += 1
		seeds_ok += res["seeds"]
		layouts_ok += res["layouts"]
		total_rooms += f["transcription_order"].size()
	print("original_field_generator_check: growth %d/%d, transcription %d/%d, seeds %d/%d, layouts %d/%d" % [
		growth_ok, fixtures.size(), transcribed, fixtures.size(), seeds_ok,
		total_rooms, layouts_ok, total_rooms])
	quit(0 if fails == 0 else 1)


func _anchor(f, gen):
	# Position: growth end (the generator's rng state), then search the
	# unmodelled gate stage's draw cost k before the per-room chain.
	var base: Array = gen.get_rng_state()
	var rooms_by_index := {}
	for r in f["rooms"]:
		rooms_by_index[r["index"]] = r
	var order: Array = f["transcription_order"]
	var depth_by_index := {}
	var adj_by_index := {}
	for room in gen.list:
		depth_by_index[room.index] = room.depth
		adj_by_index[room.index] = room.adj
	for skip_set in _skip_candidates(f):
		for k in 300:
			var rng := FieldRng.new(base[0], base[1])
			for i in k:
				rng.draw(0)   # step without consuming a bounded value
			var res := _chain(rng, order, rooms_by_index, depth_by_index,
				adj_by_index, skip_set)
			if res != null and res["seeds"] == order.size():
				return res
	return null


func _chain(rng: FieldRng, order, rooms_by_index, depth_by_index,
		adj_by_index, skip_set) -> Dictionary:
	var seeds := 0
	var layouts := 0
	var variant_of := {}
	var done: Array = []
	for idx in order:
		var rec: Dictionary = rooms_by_index[idx]
		var shape: int = SHAPE_LETTERS.find(rec["shape"])
		if shape < 0:
			return {"seeds": -1, "layouts": 0}
		if shape == 3:
			rng.draw(4)
		elif shape == 0:
			rng.draw(2)
		if shape <= 4 and shape != 3 and shape != 5 and shape != 6:
			if not skip_set.has(idx):
				rng.draw(_pool_size(shape, idx, done, rooms_by_index,
					variant_of, adj_by_index))
		variant_of[idx] = _variant_of_code(rec["code"])
		done.append(idx)
		if int(rec.get("keys", 0)) > 0:
			rng.draw(2)
			rng.draw(2)
		if rng.draw(0xFFFFFFFF) != int(rec["seed"], 16):
			return null
		seeds += 1
		var roll: int = rng.draw(100)
		var depth: int = depth_by_index[idx]
		var band := 0 if depth < 4 else (1 if depth < 7 else 2)
		var acc := 0
		var cat := 3
		for i in LAYOUT_BANDS[band].size():
			acc += LAYOUT_BANDS[band][i]
			if roll < acc:
				cat = i
				break
		if cat == int(rec.get("layout", -1)):
			layouts += 1
	return {"seeds": seeds, "layouts": layouts}


func _pool_size(shape: int, idx, done: Array, rooms_by_index, variant_of,
		adj_by_index) -> int:
	var cands: int = VARIANTS[shape].size()
	var adj: Array = adj_by_index[idx]
	var used := {}
	for earlier in done:
		for d in 4:
			if adj[d] == earlier:
				var eshape: int = SHAPE_LETTERS.find(rooms_by_index[earlier]["shape"])
				if variant_of.has(earlier):
					used["%d_%d" % [eshape, variant_of[earlier]]] = true
	var pool := 0
	for i in cands:
		if not used.has("%d_%d" % [shape, i]):
			pool += 1
	return pool if pool > 0 else cands


func _variant_of_code(code: String) -> int:
	var suffix: String = code.split("_")[1]
	var shape: int = SHAPE_LETTERS.find(suffix[0])
	var cls: int = CLASS_LETTERS.find(suffix[1])
	var digit: int = int(suffix.substr(2))
	for i in VARIANTS[shape].size():
		if VARIANTS[shape][i][0] == cls and VARIANTS[shape][i][1] == digit:
			return i
	return 0


func _skip_candidates(f) -> Array:
	var out: Array = [{}]
	for r in f["rooms"]:
		if PICKER_CODES.has(r["code"].split("_")[1]):
			out.append({r["index"]: true})
	return out
