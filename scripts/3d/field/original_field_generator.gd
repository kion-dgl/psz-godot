class_name OriginalFieldGenerator
extends RefCounted
## Seed-exact port of the original PSZ field generator.
##
## Implements the decompiled generation path (see
## data/re_reference/level_generation_algorithm.json; growth ported from the
## psz-re oracle tools/generate.py) on the field LCG (scripts/utils/field_rng.gd).
## Validated against all 14 fixtures in data/re_reference/field_fixtures.json:
## 14/14 reproduce target, branches, room count and cell set via run(), and
## every per-room seed and layout category via transcribe() with the fixture
## order (see scripts/tools/original_field_generator_check.gd; the Python
## reference in scripts/tools/field_gen_reference.py scores 129/129 seeds and
## layouts across the same fixtures).
##
## NOT modelled: the gate stage (FUN_020b2xxx, params 4..8) that runs between
## growth and transcription — it decides gates/keys, the rare-room picker and
## the room-list shuffle. For a fresh field this generator draws its own list
## shuffle after goal selection (self-consistent); replaying a console field
## exactly needs the fixture's transcription order and goal passed in.

const GRID_W := 7
const GRID_H := 10
const DELTA := [[0, -1], [1, 0], [0, 1], [-1, 0]]   # 0x020f2ef8
const OPPOSITE := [2, 3, 0, 1]                       # 0x020f2ee8
const START_X := 3

const F_OCCUPIED := 2
const F_START := 4
const F_GOAL := 8
const F_EXTENDED := 0x10

const SHAPE_LETTERS := "iltxnsg"
const CLASS_LETTERS := "abcdr"
## variant table at 0x020f5978: shape -> (classId, digit) pairs
const VARIANTS := [
	[[1, 1], [1, 2], [2, 1], [2, 3]],   # i: b1 b2 c1 c3
	[[1, 1], [1, 3], [2, 1], [2, 2]],   # l: b1 b3 c1 c2
	[[1, 3], [2, 3], [3, 1], [3, 2]],   # t: b3 c3 d1 d2
	[[1, 2]],                            # x: b2
	[[0, 1], [1, 2], [2, 2]],            # n: a1 b2 c2
	[[0, 1]],                            # s: a1
	[[0, 1]],                            # g: a1
]
## layout (+0x31) weight rows by depth band, table 0x020f2e70
const LAYOUT_BANDS := [[50, 20, 20, 10], [40, 20, 20, 20], [25, 25, 25, 25]]

var _rng: FieldRng
var cells := {}          # Vector2i -> Room
var _queue: Array = []   # gen+0xc growth frontier, appended at placement time
var list: Array = []     # gen+0x60 room list, placement order
var target := 0
var branches_drawn := 0
var branch := 0
var linear := 0
var params: Array = []
var stage := "s01a"


class Room:
	extends RefCounted
	var x := 0
	var y := 0
	var flags := OriginalFieldGenerator.F_OCCUPIED
	var doors := 0
	var depth := 0
	var index := 0
	var adj: Array = [-1, -1, -1, -1]
	var wayback := -1
	var shape := -1
	var rotation := -1
	var variant := 0
	var keys := 0
	var seed := 0
	var layout := -1


func _init(seed_lo: int, seed_hi: int, stage_id: String, gen_params: Array) -> void:
	stage = stage_id
	params = gen_params
	_rng = FieldRng.new(seed_lo, seed_hi)
	_rng.draw(0)   # the generation_start_state is the state at FUN_02081ea8's
	# ENTRY; the first real draw (target) steps from it, so consume one step.


## FUN_02083590 shuffle: one draw per element; lists of <= 1 element are free.
func _shuffle(arr: Array) -> void:
	if arr.size() <= 1:
		return
	for i in arr.size():
		var j: int = _rng.draw(arr.size())
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## FUN_0208209c — pure grid bookkeeping, no draws.
func _place(parent: Room, direction: int) -> bool:
	if parent.x < 0 or parent.y < 0:
		return false
	var x := parent.x + DELTA[direction][0]
	var y := parent.y + DELTA[direction][1]
	if x < 0 or x >= GRID_W or y < 0 or y >= GRID_H:
		return false
	if cells.has(Vector2i(x, y)):
		return false
	var child := Room.new()
	child.x = x
	child.y = y
	child.index = list.size()
	child.depth = parent.depth + 1
	child.doors = 1
	child.wayback = OPPOSITE[direction]
	child.adj[OPPOSITE[direction]] = parent.index
	parent.adj[direction] = child.index
	parent.doors += 1
	cells[Vector2i(x, y)] = child
	_queue.append(child)
	list.append(child)
	return true


## FUN_020833ac
func _child_count(remaining: int) -> int:
	var a := branch
	var b := linear
	if a + b == 0:
		return 0
	if _rng.draw(a + b) >= a:
		return 0
	if a * 2 < remaining:
		if a < 2:
			return 1
		return 2 if _rng.draw(100) < 30 else 1
	return 2 if a > 2 else a


## FUN_0208340c
func _spend(n: int) -> void:
	if n == 0:
		if linear > 0:
			linear -= 1
	elif n <= branch:
		branch -= n


## FUN_02082050 — direction bag: shuffle [0..3] (4 draws), pop until placed.
func _spawn(room: Room, want: int) -> int:
	var bag := [0, 1, 2, 3]
	_shuffle(bag)
	var made := 0
	while not bag.is_empty():
		if target <= list.size():
			break
		if _place(room, bag.pop_back()):
			made += 1
			if made >= want:
				break
	return made


## FUN_020821d0 — shuffle the frontier, LIFO pop, place n+1 children.
func _grow() -> void:
	while not _queue.is_empty():
		_shuffle(_queue)
		var room: Room = _queue.pop_back()
		if target <= list.size():
			return
		var n := _child_count(target - list.size())
		var made := _spawn(room, n + 1)
		if made > 0:
			_spend(made - 1)


## FUN_02082228 — one extension attempt off the room list.
func _extend() -> void:
	_shuffle(list)
	for room in list:
		if not (room.flags & F_START) and room.doors < 4:
			var n := _child_count(target - list.size())
			if n == 0:
				n = 1
			var made := _spawn(room, n)
			if made > 0:
				_spend(made)
				room.flags |= F_EXTENDED
				return


## FUN_02081ea8 — target/branch draws, budgets, fixed start, growth.
func run() -> void:
	var lo: int = params[0]
	var hi: int = params[1]
	if lo < 2 or hi < lo or hi > 0x13:
		target = 10
	elif hi == lo:
		target = lo
	else:
		target = lo + _rng.draw(hi - lo)
	var s_lo: int = params[2]
	var s_hi: int = params[3]
	branches_drawn = 0
	if 0 <= s_lo and s_lo <= s_hi and s_hi < 9:
		branches_drawn = s_lo if s_hi == s_lo else s_lo + _rng.draw(s_hi - s_lo)
	branch = branches_drawn
	linear = maxi(0, target - branch * 2 - 1)   # FUN_02083378
	var start := Room.new()
	start.x = START_X
	start.y = 9 - int(params[9])
	start.index = 0
	start.depth = 0
	start.flags |= F_START
	cells[Vector2i(start.x, start.y)] = start
	list.append(start)
	_place(start, 0)   # the start's one deterministic north child, no bag
	_grow()
	if list.size() < target:
		_extend()
		_grow()


## FUN_020822ac with params[10] = 0: uniform among single-door rooms of
## depth > 3 (fallback: any single-door non-start room).
func select_goal() -> Room:
	var cands: Array = list.filter(
		func(r): return not (r.flags & F_START) and r.doors == 1 and r.depth > 3)
	if cands.is_empty():
		cands = list.filter(
			func(r): return not (r.flags & F_START) and r.doors == 1)
		if cands.is_empty():
			return null
	return cands[_rng.draw(cands.size())]


## Transcription draw chain per room: rotation (x/i), variant (i/l/t/n),
## key shuffle (2 draws when keys > 0), seed, layout category.
## order_override + goal_index reproduce a console field (the gate stage's
## room order and goal are inputs then); a fresh field draws its own shuffle
## right after goal selection.
func transcribe(order_override: Array = [], keys_by_index: Dictionary = {},
		goal_index: int = -1) -> void:
	var goal: Room = null
	if goal_index >= 0:
		goal = list[goal_index]
	else:
		goal = select_goal()
	if goal:
		goal.flags |= F_GOAL
	var order := list.duplicate()
	if not order_override.is_empty():
		order = order_override.map(func(i): return list[i])
	else:
		_shuffle(order)   # FUN_020b2698's list shuffle (gate-stage stand-in)
	var done: Array = []
	for room in order:
		room.keys = int(keys_by_index.get(room.index, 0))
		_shape_and_rotation(room)
		room.variant = _variant_for(room, done)
		if room.keys > 0:
			_rng.draw(2)
			_rng.draw(2)
		room.seed = _rng.draw(0xFFFFFFFF)
		room.layout = _layout_for(room.depth)
		done.append(room)


## FUN_020826ec — rotation is an orientation CODE, not a quarter-turn count.
func _shape_and_rotation(room: Room) -> void:
	if room.doors == 4:
		room.shape = 3
		room.rotation = _rng.draw(4)
	elif room.doors == 3:
		room.shape = 2
		room.rotation = _first_closed_dir(room)
	elif room.doors == 2:
		var dirs := _open_dirs(room)
		if (dirs[0] + dirs[1]) % 2 == 0:
			room.shape = 0
			# straight: rand(2)*2, +1 when the doors run east/west (north empty)
			room.rotation = _rng.draw(2) * 2 + (1 if room.adj[0] < 0 else 0)
		else:
			room.shape = 1
			room.rotation = _first_open_corner(room)
	else:
		var exit_dir: int = _open_dirs(room)[0]
		room.shape = 6 if (room.flags & F_GOAL) else (5 if (room.flags & F_START) else 4)
		room.rotation = (exit_dir + 2) % 4


func _open_dirs(room: Room) -> Array:
	var out := []
	for d in 4:
		if room.adj[d] >= 0:
			out.append(d)
	return out


func _first_closed_dir(room: Room) -> int:
	for d in 4:
		if room.adj[d] < 0:
			return d
	return 0


func _first_open_corner(room: Room) -> int:
	for i in 4:
		if room.adj[i] >= 0 and room.adj[(i + 1) % 4] >= 0:
			return i
	return 0


## FUN_02082628 — one draw over candidates whose (shape,class,digit) does not
## match an already-transcribed neighbour; over all candidates if none survive.
func _variant_for(room: Room, done: Array) -> int:
	var cands: Array = VARIANTS[room.shape]
	if cands.size() <= 1:
		return 0
	var used := {}
	for nb in done:
		for d in 4:
			if room.adj[d] == nb.index:
				used["%d_%d" % [nb.shape, nb.variant]] = true
	var pool := []
	for i in cands.size():
		if not used.has("%d_%d" % [room.shape, i]):
			pool.append(i)
	if pool.is_empty():
		for i in cands.size():
			pool.append(i)
	return pool[_rng.draw(pool.size())]


## FUN_02082814 — depth-banded layout category draw.
func _layout_for(depth: int) -> int:
	var band := 0 if depth < 4 else (1 if depth < 7 else 2)
	var roll: int = _rng.draw(100)
	var acc := 0
	for i in LAYOUT_BANDS[band].size():
		acc += LAYOUT_BANDS[band][i]
		if roll < acc:
			return i
	return 3


func room_code(room: Room) -> String:
	var cv: Array = VARIANTS[room.shape][room.variant]
	return "%s_%s%s%d" % [stage, SHAPE_LETTERS[room.shape], CLASS_LETTERS[cv[0]], cv[1]]


## Grid normalized to the field's own bounding box (the transcriber subtracts
## the generator's per-field origin).
func normalized_origin() -> Vector2i:
	var min_x := 99
	var min_y := 99
	for r in list:
		min_x = mini(min_x, r.x)
		min_y = mini(min_y, r.y)
	return Vector2i(min_x, min_y)


## The LCG state after run() — the anchor point for fixture transcription
## replay (the gate stage's draw cost is searched from here).
func get_rng_state() -> Array:
	return [_rng.get_state_lo(), _rng.get_state_hi()]


func to_records() -> Array:
	var origin := normalized_origin()
	var out := []
	for r in list:
		out.append({
			"index": r.index,
			"grid": Vector2i(r.x - origin.x, r.y - origin.y),
			"internal": Vector2i(r.x, r.y),
			"code": room_code(r),
			"shape": SHAPE_LETTERS[r.shape],
			"rotation": r.rotation,
			"depth": r.depth,
			"role": "start" if (r.flags & F_START) else ("goal" if (r.flags & F_GOAL) else ""),
			"adj": r.adj.duplicate(),
			"way_back": r.wayback,
			"keys": r.keys,
			"seed": r.seed,
			"layout": r.layout,
		})
	return out
