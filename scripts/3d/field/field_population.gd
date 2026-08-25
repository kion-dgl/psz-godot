extends RefCounted
class_name FieldPopulation
## Fills a generated field cell with objects.
##
## Free-roam fields used to come from a static data/field_quests/*.json — the
## same layout and the same fights every entry, because pick_field_quest always
## returns the first match. GridGenerator can roll a fresh layout, but its cells
## carried no `objects` key at all, so a generated field was empty rooms. This
## is the missing half.
##
## HOW GROUNDED EACH OBJECT TYPE IS — worth stating plainly, because it is not
## uniform and guessing here has already cost us once:
##
##   enemies  DECODED. data/re_reference/enemy_room_assignment.json gives, per
##            room code, the wave templates that room may roll and their
##            weights; enemy_wave_templates.json gives each template's exact
##            enemy list. Both cover every field area (s01..s07, a and b).
##            The RE internal name maps to a psz-godot enemy through the
##            `model_id` already on each data/enemies/*.tres — 65 of the 69
##            table entries resolve, the rest being the `sample` slot, the
##            documented empty slot at 64, and two boss sub-parts.
##
##   boxes    DECODED, and this replaces the ring. The earlier note here said
##            "the real placement weights are still unidentified" and put boxes
##            on a ring, because at the time the only reading of box COUNT
##            (2 x the byte at +0x31) had been refuted. That refutation stands
##            and it was the wrong question: there is no count formula because
##            there is no placement pass. Positions are AUTHORED per room in
##            set/<NN>/<v>/<room>/*.rel, and the byte at +0x31 is a layout
##            index that picks which of the file's six groups get built. The
##            table is data/re_reference/room_objects.json (290 rooms, every
##            cell of every field quest covered) and the selection rule is
##            `authored_objects()` below.
##
##   traps    DECODED, same table, same rule — and the traps are mostly in
##            GROUP 5, which is the one group the game rolls rather than
##            builds whole. A port that built groups 0..4 and stopped would
##            place almost no traps at all.
##
##   walls    DECODED and PLACED (#593). The autopilot skips them at spawn
##            time, not generation time, so the field data is the same
##            either way.
##
## Enemy positions are still ours: the game's enemy deploy table is a separate
## file that has not been decoded to positions, so enemies stay on a ring.

const RE_DIR := "res://data/re_reference/"
## Deploy set to roll from. The RE notes record that d/f1..f4/s draw from the
## same pool with near-identical size distributions, so the set does not
## meaningfully change which waves exist; "d" is the one validated against
## kion's observed Valley waves.
const DEPLOY_SET := "d"

## Box count for a room the authored table does not cover. Nothing in a shipped
## field hits this today — every cell of every field quest resolves — so it is
## the fallback for a room code invented later, not a placement policy.
const BOXES_PER_ROOM := 2

## The ring is now a FALLBACK, not the placement. Every room model the original
## ships carries 8 or 9 authored spawn slots, and standing enemies on those is
## the whole difference between a wave that fits its room and one that does not
## (#604 -- enemies on rocks, waves straddling a void). A ring is a shape; it
## knows nothing about the geometry it is drawn inside.
##
## Kept for room codes that have no authored slots, same as BOXES_PER_ROOM is
## kept for room codes with no authored object table. See /mechanics/enemy-placement.
const ENEMY_RING_RADIUS := 5.0
const BOX_RING_RADIUS := 8.0

## Authored walls ARE placed (#593), and the soft-lock fear that used to gate
## them here is measured away.
##
## The old gate lived in `_to_object()` — generation time — which was the wrong
## place twice over: the generated field DATA differed between an autopilot run
## and a player run, and a cell first entered under autopilot saved without its
## walls and restored that way forever. The skip now lives at spawn time in
## CellObjectSpawner, next to the one boxes already use.
##
## And the reason for the gate does not survive contact with psz-re's own
## measurement. Over all 964 authored wall records the smallest distance from a
## wall to any doorway mouth of its own room is 5.14 cells — with a control that
## the same ruler finds the room warp at 0.01 and `o0c_fence` at 1.31, so it
## does detect things that stand in a doorway. An authored wall never blocks a
## connection. `test_authored_walls_clear_doorways` re-derives that from our own
## copy of the data rather than trusting the number.

## The game's facing is 16 bits per turn, 0 = +Z increasing toward +X, which is
## exactly Godot's `rotation.y` about a +Z forward. So the conversion is a
## scale and nothing else (psz-re nodes/sys.facing-convention.json).
const FACING_PER_TURN := 65536.0

static var _assignment: Dictionary = {}
static var _waves: Array = []
static var _model_to_enemy: Dictionary = {}
static var _loaded := false

## Per-room wave-count range, room code -> [w3, w4] (min, max). From psz-re's
## enemy_room_assignment record; see the Enemy Waves spec.
static var _wave_counts: Dictionary = {}

## Wave count for a room the table does not cover. Every room in the imported
## table carries a pair, so this is only reachable for a code the original never
## shipped — a single wave, matching how a fightless room reads in play.
const DEFAULT_WAVE_COUNT := 1

## data/re_reference/room_objects.json, split out at load.
static var _rooms: Dictionary = {}

## Authored enemy spawn slots, room code -> Array of {x, y, z}. From
## room_reference.json, which is otherwise reference-only -- see the note there:
## its OBJECTS stay out of the game because an unhandled kind would eat a slot
## against the 20-object room cap, but spawn slots are positions, not objects,
## and cost nothing against that cap.
static var _enemy_slots: Dictionary = {}
static var _layout_masks: Array = []
static var _layout_weights: Dictionary = {}
static var _group5_weights: Array = []
static var _cap_per_group: int = 20
static var _cap_per_room: int = 20


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var assign_doc: Dictionary = _read_json(RE_DIR + "enemy_room_assignment.json")
	_assignment = assign_doc.get("assignment", {})
	_wave_counts = assign_doc.get("wave_counts", {})
	var wave_doc: Dictionary = _read_json(RE_DIR + "enemy_wave_templates.json")
	var deploy: Dictionary = wave_doc.get(DEPLOY_SET, {})
	_waves = deploy.get("waves", [])
	_build_model_map()

	var obj_doc: Dictionary = _read_json(RE_DIR + "room_objects.json")
	_rooms = obj_doc.get("rooms", {})
	_layout_masks = obj_doc.get("layout_masks", [])
	_layout_weights = obj_doc.get("layout_weights_by_depth", {})
	_group5_weights = obj_doc.get("group5_weights", [])
	var ref_doc: Dictionary = _read_json(RE_DIR + "room_reference.json")
	for code in ref_doc.get("rooms", {}):
		var slots: Array = ref_doc["rooms"][code].get("enemies", [])
		if not slots.is_empty():
			_enemy_slots[code] = slots

	var caps: Dictionary = obj_doc.get("caps", {})
	_cap_per_group = int(caps.get("per_group", 20))
	_cap_per_room = int(caps.get("per_room", 20))


static func _read_json(path: String) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		push_warning("FieldPopulation: missing " + path)
		return {}
	var json := JSON.new()
	if json.parse(fa.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("FieldPopulation: bad JSON in " + path)
		return {}
	return json.data


## RE internal names with no enemy of their own, and what to do about them.
##
## boss_robot_cmb is the only name in s06z's template, so dropping it would
## leave Arca's boss room empty. The RE roster files it under the boss_robot
## series and the name carries the prefix, so it resolves to the same enemy.
## That is an inference, flagged as one — every other name here comes straight
## off a model_id.
##
## boss_mother_piece is deliberately absent: the parts are spawned by the
## mother boss itself, not placed as separate room enemies.
const NAME_ALIASES := {
	"boss_robot_cmb": "boss_robot",
}
const DROPPED_NAMES := ["boss_mother_piece", "sample", ""]


## RE internal name -> psz-godot enemy id, read off each enemy's `model_id`.
## The repo already carries this mapping; nothing here guesses at it.
static func _build_model_map() -> void:
	_model_to_enemy.clear()
	var dir := DirAccess.open("res://data/enemies/")
	if not dir:
		push_warning("FieldPopulation: cannot list res://data/enemies/")
		return
	for file_name in dir.get_files():
		var res_name := file_name.trim_suffix(".remap")
		if not res_name.ends_with(".tres"):
			continue
		var data = load("res://data/enemies/" + res_name)
		if not data or data.model_id.is_empty():
			continue
		# First writer wins; there are no duplicate model_ids today, and a
		# stable pick beats whichever order DirAccess happens to return.
		if not _model_to_enemy.has(data.model_id):
			_model_to_enemy[data.model_id] = data.id


## Enemy ids for one room's rolled wave, or [] when the room code fights nobody.
##
## Area B reuses area A's assignment where it has no row of its own, matching
## what the static builder did.
static func roll_wave(room_code: String, rng: RandomNumberGenerator) -> Array:
	_load()
	var choices: Array = _assignment.get(room_code, [])
	if choices.is_empty():
		var parts := room_code.split("_", true, 1)
		if parts.size() == 2 and parts[0].length() >= 4:
			choices = _assignment.get("%sa_%s" % [parts[0].substr(0, 3), parts[1]], [])
	if choices.is_empty():
		return []

	var total: int = 0
	for entry in choices:
		total += int(entry.get("weight", 0))
	if total <= 0:
		return []
	# Weighted pick over the measured weights — the game rolls per room
	# instance, so this is a real roll rather than a hash of the cell.
	var roll: int = rng.randi_range(0, total - 1)
	var template_idx: int = int(choices[0].get("template", 0))
	for entry in choices:
		roll -= int(entry.get("weight", 0))
		if roll < 0:
			template_idx = int(entry.get("template", 0))
			break

	if template_idx < 0 or template_idx >= _waves.size():
		return []
	var names: Array = _waves[template_idx].get("names", [])
	var out: Array = []
	for n in names:
		out.append_array(_resolve(str(n)))
	return out


## RE internal name -> zero or one psz-godot enemy id.
static func _resolve(re_name: String) -> Array:
	if re_name in DROPPED_NAMES:
		return []
	var key: String = str(NAME_ALIASES.get(re_name, re_name))
	var enemy_id: String = str(_model_to_enemy.get(key, ""))
	if enemy_id.is_empty():
		push_warning("FieldPopulation: no enemy for RE name '%s'" % re_name)
		return []
	return [enemy_id]


## The authored objects one room instance gets, as psz-godot object dicts.
##
## THE RULE, transcribed from psz-re (docs/godot-field-parity.md §7 and §8.1 —
## the constants travel with the data in room_objects.json rather than being
## repeated here as free numbers):
##
##   1. A set file is SIX groups. One of five layout masks picks which of
##      groups 0..4 are built, and group 5's bit is forced into every mask.
##   2. The layout index is a rand(100) draw against a weight row chosen by the
##      room's depth in the tree. A mask is only eligible if every group it
##      names is non-empty; when the drawn index is not eligible the highest
##      eligible index at or below 3 wins, and failing that, 0.
##   3. Groups 0..4 are then built VERBATIM. Nothing is sampled from them.
##   4. Group 5 — the trap group — is ROLLED: rand(100) against [40,20,20,20]
##      gives a count of 0..3, the group is shuffled, and that many are taken.
##      So 40% of rooms roll no group-5 object at all.
##   5. A group is truncated at 20 records and a room stops at 20 objects.
##
## THERE ARE FIVE MASKS AND ONLY FOUR ARE REACHABLE, BY DESIGN — do not "fix"
## this. The layout index comes from the original's FUN_02082814, which psz-re
## reads as a weighted draw returning a category 0..3 against the table at
## 0x020f2e70 (twelve ints as three rows of four, every row summing to 100),
## validated on all 44 values across five captured fields being in 0..3. So
## mask 4 = 0x30 — the only one naming group 4 — is never selected here, and
## group 4's objects never spawn in a free field. 146 of set d's records sit
## there, and `s07a_ga1_d` is entirely group 4, which is why that room falls
## through to the ring. psz-re's own NOT_ESTABLISHED records a mission-guarded
## path that forces layout 4; it has not modelled it, and free-roam generation
## correctly never takes it. Widening the draw would spawn objects the original
## does not spawn.
##
## `depth` is the room's distance along the generated path; -1 means unknown
## and takes the middle weight row. Every draw goes through `rng`, so a seeded
## generator reproduces a field exactly.
static func authored_objects(room_code: String, depth: int, rng: RandomNumberGenerator) -> Array:
	_load()
	var entry: Dictionary = _rooms.get("%s_%s" % [room_code, DEPLOY_SET], {})
	var records: Array = entry.get("objects", [])
	if records.is_empty():
		return []

	var groups = entry.get("groups", null)
	var picked: Array = []
	if groups == null:
		# No recoverable group table: psz-re records that the loader falls back
		# and builds the file flat. Do the same rather than dropping the room.
		picked = _cap(records, _cap_per_group)
	else:
		var layout: int = _pick_layout(groups, depth, rng)
		var mask: int = int(_layout_masks[layout]) if layout < _layout_masks.size() else 0
		for g in range(5):
			if (mask >> g) & 1:
				picked.append_array(_cap(_in_group(records, g), _cap_per_group))
		picked.append_array(_roll_group_five(_in_group(records, 5), rng))

	var out: Array = []
	for rec in _cap(picked, _cap_per_room):
		var obj := _to_object(rec)
		if not obj.is_empty():
			out.append(obj)
	return _drop_unopenable_fences(out)


## A fence with no switch in the room is a sealed room, so drop it.
##
## The importer already refuses to emit a fence into a room whose TABLE has no
## switch, but that is not enough: groups 0..4 are selected by the layout mask,
## so a room can build the group holding its fence and skip the group holding
## its switch. Measured over the generated dump, that happened in 1 cell of the
## 21 that carry a fence — rare, and a hard stop for the player when it does.
##
## The check has to run here, on the objects a room actually builds, which is
## the only place both facts are known. When psz-re publishes the fence/switch
## pairing (it lives in the object parameter block, not in the per-room dump)
## this becomes "drop a fence whose switch was not built" instead.
static func _drop_unopenable_fences(objects: Array) -> Array:
	var has_switch := false
	var has_fence := false
	for o in objects:
		var t: String = str(o.get("type", ""))
		if t == "step_switch":
			has_switch = true
		elif t == "fence":
			has_fence = true
	if has_switch or not has_fence:
		return objects
	var kept: Array = []
	for o in objects:
		if str(o.get("type", "")) != "fence":
			kept.append(o)
	return kept


## Which of the five layout masks this room instance uses.
static func _pick_layout(groups: Array, depth: int, rng: RandomNumberGenerator) -> int:
	var occupied: int = 0
	for g in range(min(groups.size(), 6)):
		if int(groups[g]) > 0:
			occupied |= 1 << g
	# Group 5's bit is forced in: the mask names it whether or not the file has
	# one, because the roll may legitimately take nothing.
	occupied |= 0x20

	var eligible: Array[int] = []
	for i in range(_layout_masks.size()):
		var m: int = int(_layout_masks[i])
		if m == (m & occupied):
			eligible.append(i)
	if eligible.is_empty():
		return 0

	var drawn: int = _weighted_index(_layout_weights.get(_depth_band(depth), []), rng)
	if drawn in eligible:
		return drawn
	# Not eligible: the highest eligible index at or below 3, else 0.
	var best: int = -1
	for i in eligible:
		if i <= 3 and i > best:
			best = i
	return best if best >= 0 else 0


## The weight row keys room_objects.json publishes, by tree depth.
static func _depth_band(depth: int) -> String:
	if depth < 0:
		return "4_6"
	if depth < 4:
		return "lt4"
	return "4_6" if depth <= 6 else "ge7"


## rand(100) walked against a weight row, as the game walks it.
static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	if weights.is_empty():
		return 0
	var roll: int = rng.randi_range(0, 99)
	for i in range(weights.size()):
		roll -= int(weights[i])
		if roll < 0:
			return i
	return weights.size() - 1


## Group 5: a rolled count of 0..3, then a shuffle, then take that many.
static func _roll_group_five(records: Array, rng: RandomNumberGenerator) -> Array:
	if records.is_empty():
		return []
	var count: int = _weighted_index(_group5_weights, rng)
	if count <= 0:
		return []
	# Fisher-Yates over a copy, so the source order is never mutated.
	var pool: Array = records.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, min(count, pool.size()))


static func _in_group(records: Array, group: int) -> Array:
	var out: Array = []
	for rec in records:
		if rec.get("g", null) != null and int(rec["g"]) == group:
			out.append(rec)
	return out


static func _cap(records: Array, limit: int) -> Array:
	return records if records.size() <= limit else records.slice(0, limit)


## One authored record -> the object dict the spawner understands, or {} for a
## kind this build does not place.
static func _to_object(rec: Dictionary) -> Dictionary:
	var kind: String = str(rec.get("k", ""))
	var pos: Array = [
		snappedf(float(rec.get("x", 0.0)), 0.01),
		snappedf(float(rec.get("y", 0.0)), 0.01),
		snappedf(float(rec.get("z", 0.0)), 0.01),
	]
	var obj: Dictionary = {"type": kind, "position": pos, "authored": true}
	# A fence is opened by a switch, and the import links every fence in a room
	# to every switch in it (see import_re_objects.FENCE_LINK_ID — psz-re does
	# not publish the real pairing). The spawner already keys `_fence_links` on
	# this id for the static quests.
	if rec.has("link"):
		obj["link_id"] = str(rec["link"])
	# The source model, kept so four fence models and three switch models can
	# diverge in art later without a re-import.
	if rec.has("m"):
		obj["model"] = str(rec["m"])
	if kind == "wall":
		# OURS, and stated rather than inherited from the spawner's default.
		# psz-re's wall_placement_per_room.json is explicit that "no wall
		# BEHAVIOUR is decoded -- hit points, whether it breaks at all", so
		# there is no measured answer to port. Breakable is the failure-safe
		# reading: no authored wall blocks a connection today (5.14 cells of
		# clearance across the corpus), but if one ever did, a player can clear
		# a breakable wall and cannot clear a solid one.
		#
		# The thread to pull if this is ever settled: the container constructor
		# special-cases record byte +0x12 == 1 -- it additionally enables the
		# collider and stores 2 rather than 3 -- which is the likeliest
		# solid/breakable discriminator. This importer does not carry +0x12.
		obj["destructible"] = true
	# The spawner's `rotation` is degrees everywhere (it calls deg_to_rad), so
	# convert here rather than leaving a second unit in the object schema.
	var facing_deg: float = float(int(rec.get("a", 0))) / FACING_PER_TURN * 360.0
	if not is_zero_approx(facing_deg):
		obj["rotation"] = snappedf(facing_deg, 0.01)
	return obj


## Evenly spaced positions on a ring around the room centre (rooms are 44x44).
## Where a wave's enemies stand: the room's own authored slots.
##
## `count` may exceed the slot count -- slots are REUSED rather than the wave
## truncated, because the original reuses them too (a room with 8 slots was
## observed producing 11 enemies across three waves). It may also be smaller,
## in which case a seeded subset is taken so a given field always populates the
## same way rather than shuffling on every revisit.
##
## Returns [] when the room code has no authored slots, so the caller falls
## back to the ring.
## The room's authored slots as the data holds them. Exposed so a test can
## assert placement picks FROM this list rather than near it.
static func authored_enemy_slots(room_code: String) -> Array:
	_load()
	return _enemy_slots.get("%s_%s" % [room_code, DEPLOY_SET], [])


static func enemy_slot_positions(room_code: String, count: int,
		rng: RandomNumberGenerator) -> Array:
	_load()
	# Same keying as authored_objects: the data is per deploy set.
	var slots: Array = _enemy_slots.get("%s_%s" % [room_code, DEPLOY_SET], [])
	if slots.is_empty() or count <= 0:
		return []

	# Which slots go unused is OUR choice, not a measurement: the original
	# derives it from a per-room seed whose placement weights are still
	# undecoded (psz-re default_parameters bytes 4..8). The POSITIONS are
	# authored and exact; the selection among them is not claimed to match.
	var order: Array = []
	for i in range(slots.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t

	var out: Array = []
	for i in range(count):
		var slot: Dictionary = slots[order[i % order.size()]]
		out.append([
			snappedf(float(slot.get("x", 0.0)), 0.01),
			snappedf(float(slot.get("y", 0.0)), 0.01),
			snappedf(float(slot.get("z", 0.0)), 0.01),
		])
	return out


static func ring_positions(count: int, radius: float) -> Array:
	var out: Array = []
	for i in range(count):
		var a: float = TAU * float(i) / float(count)
		out.append([
			snappedf(radius * cos(a), 0.01), 0.0, snappedf(radius * sin(a), 0.01),
		])
	return out


## Objects for a single-room section (the `e` transition and `z` boss rooms).
## Both have their own rows in the assignment table — s01z_na1 names
## boss_dragon, s02z_na1 boss_octopus, s05z_na1 boss_robot, and so on — so the
## boss a generated field fights is read from the RE data rather than picked.
## No boxes: these rooms are a fight and a warp, not a loot round.
static func objects_for_single_room(room_code: String, rng: RandomNumberGenerator) -> Array:
	var wave: Array = roll_wave(room_code, rng)
	var spots: Array = enemy_slot_positions(room_code, wave.size(), rng)
	if spots.is_empty():
		spots = ring_positions(wave.size(), ENEMY_RING_RADIUS)
	var objects: Array = []
	for i in range(wave.size()):
		objects.append({
			"type": "enemy", "position": spots[i], "enemy_id": wave[i],
		})
	return objects


## Objects for one generated cell. Start and goal rooms stay empty so nobody
## spawns into a fight or onto loot they did not walk to.
##
## `depth` is the cell's path_order — how far along the generated route it sits
## — which is what the layout draw is banded on. Callers that do not track it
## may leave it at -1.
##
## How many waves a room runs — a count in [w3, w4] rolled per instance (Enemy
## Waves spec). Every imported room carries its measured w3/w4 pair; the area-A
## fallback covers a b-section code with no pair of its own, and a code the
## table never carried runs DEFAULT_WAVE_COUNT.
static func _wave_count(room_code: String, rng: RandomNumberGenerator) -> int:
	_load()
	var pair: Array = _wave_counts.get(room_code, [])
	if pair.is_empty():
		var parts := room_code.split("_", true, 1)
		if parts.size() == 2 and parts[0].length() >= 4:
			pair = _wave_counts.get("%sa_%s" % [parts[0].substr(0, 3), parts[1]], [])
	if pair.is_empty():
		return DEFAULT_WAVE_COUNT
	var lo: int = int(pair[0])
	var hi: int = int(pair[1]) if pair.size() > 1 else lo
	if hi < lo:
		hi = lo
	return rng.randi_range(lo, hi)


static func objects_for_cell(room_code: String, is_start: bool, _is_end: bool,
		rng: RandomNumberGenerator, depth: int = -1) -> Array:
	# Only the START room is unconditionally empty. is_end is NOT: the goal is
	# "not necessarily last" (free-field spec), so the last cell of a path is
	# often an ordinary combat room, and suppressing its wave left whole rooms
	# with no enemies. The actual goal room carries no assignment, so roll_wave
	# returns [] for it on its own — no need to special-case is_end here.
	if is_start:
		return []
	var objects: Array = []
	# A room runs a COUNT of waves (Enemy Waves spec), each an independent draw
	# from the room's pool. Each enemy is tagged with its wave number; the
	# spawner holds back wave > 1 until the prior wave is cleared. Slots are
	# reused across waves, so each wave re-picks positions.
	var wave_count: int = _wave_count(room_code, rng)
	for w in range(1, wave_count + 1):
		var wave: Array = roll_wave(room_code, rng)
		if wave.is_empty():
			continue  # room fights nobody (start/goal / no assignment)
		var enemy_spots: Array = enemy_slot_positions(room_code, wave.size(), rng)
		if enemy_spots.is_empty():
			enemy_spots = ring_positions(wave.size(), ENEMY_RING_RADIUS)
		for i in range(wave.size()):
			objects.append({
				"type": "enemy", "position": enemy_spots[i], "enemy_id": wave[i],
				"wave": w,
			})

	var authored: Array = authored_objects(room_code, depth, rng)
	if authored.is_empty():
		# No authored table for this room code. Fall back to the ring rather
		# than leaving the room bare — see BOXES_PER_ROOM.
		for spot in ring_positions(BOXES_PER_ROOM, BOX_RING_RADIUS):
			objects.append({"type": "box", "position": spot})
	else:
		objects.append_array(authored)
	return objects
