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
##   boxes    NOT decoded. level_generation_algorithm.json records that a
##            previous "boxes = 2 x byte at +0x31" reading was REFUTED (it was
##            a table index) and that the real placement weights are still
##            "unidentified". The per-cell counts in build_valley_field.py are
##            transcribed observations of one Valley area-A layout, which do
##            not transfer to a randomly generated layout. So a generated cell
##            gets BOXES_PER_ROOM, and that number is a placeholder, not a
##            measurement.
##
##   walls    No data at all, and no field places one today. Omitted rather
##            than invented — a wall blocks, so a wrong guess is a soft-lock
##            rather than a cosmetic complaint.
##
## Positions are ours either way: the game's placement formula is not decoded,
## so objects go on a ring and the spawner floor-snaps them.

const RE_DIR := "res://data/re_reference/"
## Deploy set to roll from. The RE notes record that d/f1..f4/s draw from the
## same pool with near-identical size distributions, so the set does not
## meaningfully change which waves exist; "d" is the one validated against
## kion's observed Valley waves.
const DEPLOY_SET := "d"

## Placeholder box count per combat room — see the note above. Matches what the
## static builder used for every area outside Valley area A.
const BOXES_PER_ROOM := 2

const ENEMY_RING_RADIUS := 5.0
const BOX_RING_RADIUS := 8.0

static var _assignment: Dictionary = {}
static var _waves: Array = []
static var _model_to_enemy: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var assign_doc: Dictionary = _read_json(RE_DIR + "enemy_room_assignment.json")
	_assignment = assign_doc.get("assignment", {})
	var wave_doc: Dictionary = _read_json(RE_DIR + "enemy_wave_templates.json")
	var deploy: Dictionary = wave_doc.get(DEPLOY_SET, {})
	_waves = deploy.get("waves", [])
	_build_model_map()


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


## Evenly spaced positions on a ring around the room centre (rooms are 44x44).
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
	var spots: Array = ring_positions(wave.size(), ENEMY_RING_RADIUS)
	var objects: Array = []
	for i in range(wave.size()):
		objects.append({
			"type": "enemy", "position": spots[i], "enemy_id": wave[i],
		})
	return objects


## Objects for one generated cell. Start and goal rooms stay empty so nobody
## spawns into a fight or onto loot they did not walk to.
static func objects_for_cell(room_code: String, is_start: bool, is_end: bool,
		rng: RandomNumberGenerator) -> Array:
	if is_start or is_end:
		return []
	var objects: Array = []
	var wave: Array = roll_wave(room_code, rng)
	var enemy_spots: Array = ring_positions(wave.size(), ENEMY_RING_RADIUS)
	for i in range(wave.size()):
		objects.append({
			"type": "enemy", "position": enemy_spots[i], "enemy_id": wave[i],
		})
	for spot in ring_positions(BOXES_PER_ROOM, BOX_RING_RADIUS):
		objects.append({"type": "box", "position": spot})
	return objects
