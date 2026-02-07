extends Node
## TechniqueManager — manages technique definitions, disk creation, and character technique learning.
## Ported from psz-sketch technique system.

const TECHNIQUES := {
	"foie":     {"name": "Foie",     "element": "fire",      "power": 50,  "pp": 5,  "target": "single", "tier": "basic", "group": "foieBartaZonde"},
	"gifoie":   {"name": "Gifoie",   "element": "fire",      "power": 120, "pp": 20, "target": "area",   "tier": "mid",   "group": "foieBartaZonde"},
	"rafoie":   {"name": "Rafoie",   "element": "fire",      "power": 200, "pp": 30, "target": "area",   "tier": "advanced", "group": "foieBartaZonde"},
	"barta":    {"name": "Barta",    "element": "ice",       "power": 55,  "pp": 6,  "target": "single", "tier": "basic", "group": "foieBartaZonde"},
	"gibarta":  {"name": "Gibarta",  "element": "ice",       "power": 130, "pp": 22, "target": "area",   "tier": "mid",   "group": "foieBartaZonde"},
	"rabarta":  {"name": "Rabarta",  "element": "ice",       "power": 220, "pp": 35, "target": "area",   "tier": "advanced", "group": "foieBartaZonde"},
	"zonde":    {"name": "Zonde",    "element": "lightning",  "power": 45,  "pp": 4,  "target": "single", "tier": "basic", "group": "foieBartaZonde"},
	"gizonde":  {"name": "Gizonde",  "element": "lightning",  "power": 110, "pp": 18, "target": "area",   "tier": "mid",   "group": "foieBartaZonde"},
	"razonde":  {"name": "Razonde",  "element": "lightning",  "power": 180, "pp": 28, "target": "area",   "tier": "advanced", "group": "foieBartaZonde"},
	"grants":   {"name": "Grants",   "element": "light",     "power": 300, "pp": 50, "target": "single", "tier": "advanced", "group": "grants"},
	"megid":    {"name": "Megid",    "element": "dark",      "power": 0,   "pp": 40, "target": "single", "tier": "advanced", "group": "megid"},
	"resta":    {"name": "Resta",    "element": "none",      "power": 100, "pp": 10, "target": "party",  "tier": "basic", "group": "restaReverser"},
	"anti":     {"name": "Anti",     "element": "none",      "power": 0,   "pp": 8,  "target": "self",   "tier": "basic", "group": "restaReverser"},
	"reverser": {"name": "Reverser", "element": "none",      "power": 0,   "pp": 20, "target": "single", "tier": "mid",   "group": "restaReverser"},
	"shifta":   {"name": "Shifta",   "element": "none",      "power": 0,   "pp": 15, "target": "party",  "tier": "basic", "group": "shiftaDeband"},
	"deband":   {"name": "Deband",   "element": "none",      "power": 0,   "pp": 15, "target": "party",  "tier": "basic", "group": "shiftaDeband"},
	"jellen":   {"name": "Jellen",   "element": "none",      "power": 0,   "pp": 12, "target": "area",   "tier": "basic", "group": "jellenZalure"},
	"zalure":   {"name": "Zalure",   "element": "none",      "power": 0,   "pp": 12, "target": "area",   "tier": "basic", "group": "jellenZalure"},
}

## Area-based technique pools for disk drops
const AREA_TECHNIQUE_POOLS := {
	"gurhacia": ["foie", "barta", "zonde", "resta"],
	"rioh":     ["barta", "gibarta", "deband", "anti"],
	"ozette":   ["zonde", "gizonde", "jellen", "shifta"],
	"paru":     ["foie", "gifoie", "shifta", "zalure"],
	"makara":   ["rafoie", "rabarta", "razonde", "reverser"],
	"arca":     ["zonde", "barta", "anti", "zalure"],
	"dark":     ["megid", "grants", "reverser", "resta"],
}

## Disk level ranges by difficulty
const DISK_LEVEL_RANGES := {
	"normal":     {"min": 1, "max": 10},
	"hard":       {"min": 8, "max": 20},
	"super-hard": {"min": 15, "max": 30},
}

const BOSS_LEVEL_BONUS := 5
const RARE_LEVEL_BONUS := 3


func _ready() -> void:
	pass


## Create a disk dictionary for a given technique and level
func create_disk(technique_id: String, level: int) -> Dictionary:
	if not TECHNIQUES.has(technique_id):
		return {}
	var tech: Dictionary = TECHNIQUES[technique_id]
	var disk_id := "disk_%s_%d" % [technique_id, level]
	var disk_name := "Disk: %s Lv.%d" % [tech["name"], level]
	var sell_price := int(float(_get_base_price(technique_id)) * 0.25)
	return {
		"id": disk_id,
		"name": disk_name,
		"technique_id": technique_id,
		"level": level,
		"sell_price": sell_price,
	}


## Check if a character can learn a technique at a given level
func can_learn(character: Dictionary, technique_id: String, level: int) -> Dictionary:
	if not TECHNIQUES.has(technique_id):
		return {"allowed": false, "reason": "Unknown technique"}

	var class_id: String = str(character.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data == null:
		return {"allowed": false, "reason": "Unknown class"}

	var tech: Dictionary = TECHNIQUES[technique_id]
	var group: String = tech["group"]
	var technique_limits: Dictionary = class_data.technique_limits

	# Empty technique_limits means no technique access (CASTs)
	if technique_limits.is_empty():
		return {"allowed": false, "reason": "%s cannot use techniques" % class_data.name}

	# Check if the class has access to this technique group
	if not technique_limits.has(group):
		return {"allowed": false, "reason": "%s cannot learn %s techniques" % [class_data.name, tech["name"]]}

	var max_level: int = int(technique_limits.get(group, 0))
	if max_level <= 0:
		return {"allowed": false, "reason": "%s cannot learn %s" % [class_data.name, tech["name"]]}

	if level > max_level:
		return {"allowed": false, "reason": "%s can only learn %s up to Lv.%d" % [class_data.name, tech["name"], max_level]}

	# Check current level — reject downgrades
	var techniques: Dictionary = character.get("techniques", {})
	var current_level: int = int(techniques.get(technique_id, 0))
	if current_level >= level:
		return {"allowed": false, "reason": "Already know %s Lv.%d (disk is Lv.%d)" % [tech["name"], current_level, level]}

	return {"allowed": true, "reason": ""}


## Use a disk to learn/upgrade a technique
func use_disk(character: Dictionary, disk: Dictionary) -> Dictionary:
	var technique_id: String = str(disk.get("technique_id", ""))
	var level: int = int(disk.get("level", 0))

	var check := can_learn(character, technique_id, level)
	if not check["allowed"]:
		return {"success": false, "message": str(check["reason"]), "technique_id": technique_id, "old_level": 0, "new_level": 0}

	if not character.has("techniques"):
		character["techniques"] = {}

	var old_level: int = int(character["techniques"].get(technique_id, 0))
	character["techniques"][technique_id] = level

	var tech_name: String = TECHNIQUES[technique_id]["name"]
	var message: String
	if old_level > 0:
		message = "Upgraded %s from Lv.%d to Lv.%d!" % [tech_name, old_level, level]
	else:
		message = "Learned %s Lv.%d!" % [tech_name, level]

	return {"success": true, "message": message, "technique_id": technique_id, "old_level": old_level, "new_level": level}


## Get current technique level for a character (0 if not learned)
func get_technique_level(character: Dictionary, technique_id: String) -> int:
	var techniques: Dictionary = character.get("techniques", {})
	return int(techniques.get(technique_id, 0))


## Generate a random disk based on difficulty, area, boss/rare flags
func generate_random_disk(difficulty: String, area_id: String, is_boss: bool, is_rare: bool) -> Dictionary:
	var pool: Array = AREA_TECHNIQUE_POOLS.get(area_id, ["foie", "barta", "zonde", "resta"])
	var technique_id: String = pool[randi() % pool.size()]

	var range_data: Dictionary = DISK_LEVEL_RANGES.get(difficulty, DISK_LEVEL_RANGES["normal"])
	var min_level: int = range_data["min"]
	var max_level: int = range_data["max"]

	if is_boss:
		max_level += BOSS_LEVEL_BONUS
	if is_rare:
		max_level += RARE_LEVEL_BONUS

	# Cap at 30 (max technique level)
	max_level = mini(max_level, 30)

	var level := randi_range(min_level, max_level)
	return create_disk(technique_id, level)


## Get the base shop price for a technique
func _get_base_price(technique_id: String) -> int:
	if not TECHNIQUES.has(technique_id):
		return 100
	var tech: Dictionary = TECHNIQUES[technique_id]
	var tier: String = tech["tier"]
	var group: String = tech["group"]

	match group:
		"foieBartaZonde":
			match tier:
				"basic": return 100
				"mid": return 400
				"advanced": return 800
		"grants": return 1000
		"megid": return 1000
		"restaReverser":
			match tier:
				"basic": return 150
				"mid": return 300
		"shiftaDeband": return 200
		"jellenZalure": return 200

	return 100


## Calculate shop price for a disk at a given level
func get_disk_price(technique_id: String, level: int) -> int:
	var base := _get_base_price(technique_id)
	return int(float(base) * (1.0 + float(level - 1) * 0.5))


## Get technique info by ID
func get_technique(technique_id: String) -> Dictionary:
	return TECHNIQUES.get(technique_id, {})


## Get all technique IDs
func get_all_technique_ids() -> Array:
	return TECHNIQUES.keys()
