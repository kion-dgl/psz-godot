extends Node
## EnemySpawner — generates enemy waves based on area, difficulty, and stage.
## Ported from psz-sketch/src/systems/stage/enemy-pools.ts

## Enemy pools by area: { area_id: { common: [], uncommon: [], rare: [], bosses: [], elites: [] } }
var _enemy_pools: Dictionary = {}

## Difficulty settings
const ENEMY_COUNTS := {
	"normal": {"min": 3, "max": 6},
	"hard": {"min": 5, "max": 8},
	"super-hard": {"min": 7, "max": 12},
}

const SPAWN_WEIGHTS := {
	"normal": {"common": 70, "uncommon": 25, "rare": 5},
	"hard": {"common": 55, "uncommon": 35, "rare": 10},
	"super-hard": {"common": 40, "uncommon": 40, "rare": 20},
}

const DIFFICULTY_MULTIPLIERS := {
	"normal": 1.0,
	"hard": 1.5,
	"super-hard": 2.0,
}

## Base stats for generated enemy instances
const BASE_STATS := {
	"normal": {"hp": 50, "attack": 15, "defense": 8, "evasion": 50, "exp": 10, "meseta_min": 5, "meseta_max": 15},
	"elite": {"hp": 100, "attack": 25, "defense": 15, "evasion": 80, "exp": 30, "meseta_min": 15, "meseta_max": 40},
	"boss": {"hp": 500, "attack": 50, "defense": 30, "evasion": 120, "exp": 100, "meseta_min": 50, "meseta_max": 200},
}


func _ready() -> void:
	_init_enemy_pools()


func _init_enemy_pools() -> void:
	_enemy_pools = {
		"gurhacia": {
			"common": ["ghowl", "vulkure", "garapython"],
			"uncommon": ["garahadan", "grimble", "tormatible"],
			"rare": ["rappy", "booma-origin", "blaze-helion"],
			"bosses": ["reyburn"],
			"elites": ["helion"],
		},
		"rioh": {
			"common": ["usanny", "usanimere", "reyhound"],
			"uncommon": ["stagg", "hildeghana"],
			"rare": ["rappy", "booma-origin", "hildegigas"],
			"bosses": ["hildegao"],
			"elites": ["hildegigas"],
		},
		"ozette": {
			"common": ["porel", "pomarr", "hypao"],
			"uncommon": ["vespao", "pelcatraz"],
			"rare": ["rappy", "booma-origin", "pelcatobur"],
			"bosses": ["octo-diablo"],
			"elites": ["pelcatobur"],
		},
		"paru": {
			"common": ["pobomma", "bolix", "izhirak-s6"],
			"uncommon": ["goldix", "azherowa-b2", "froutang"],
			"rare": ["ar-rappy", "booma-origin", "frunaked"],
			"bosses": ["frunaked"],
			"elites": ["froutang"],
		},
		"makara": {
			"common": ["batt", "bullbatt", "rumole"],
			"uncommon": ["kapantha", "rohjade"],
			"rare": ["ar-rappy", "booma-origin", "rohcrysta"],
			"bosses": ["rohcrysta"],
			"elites": ["rohjade"],
		},
		"arca": {
			"common": ["korse", "akorse", "finjer-r"],
			"uncommon": ["finjer-g", "finjer-b"],
			"rare": ["rab-rappy", "booma-origin"],
			"bosses": ["blade-mother"],
			"elites": ["akorse"],
		},
		"dark": {
			"common": ["eulid", "eulidveil", "eulada"],
			"uncommon": ["euladaveil", "arkzein", "arkzein-r"],
			"rare": ["rab-rappy", "booma-origin", "derreo"],
			"bosses": ["dark-falz", "chaos-mobius"],
			"elites": ["derreo", "arkzein-r"],
		},
	}


## Generate a wave of enemies for the given area/difficulty/stage
func generate_wave(area_id: String, difficulty: String, stage: int, wave: int) -> Array:
	var pool: Dictionary = _enemy_pools.get(area_id, _enemy_pools.get("gurhacia", {}))
	var counts: Dictionary = ENEMY_COUNTS.get(difficulty, ENEMY_COUNTS["normal"])
	var weights: Dictionary = SPAWN_WEIGHTS.get(difficulty, SPAWN_WEIGHTS["normal"])
	var diff_mult: float = DIFFICULTY_MULTIPLIERS.get(difficulty, 1.0)

	var num_enemies := randi_range(int(counts["min"]), int(counts["max"]))

	# Last stage, last wave = boss
	if stage >= 3 and wave >= 3:
		var boss_list: Array = pool.get("bosses", [])
		if not boss_list.is_empty():
			var boss_wave: Array = []
			var boss_id: String = boss_list[randi() % boss_list.size()]
			boss_wave.append(_create_enemy_instance(boss_id, "boss", diff_mult, stage))
			# Add some regular enemies alongside boss
			for i in range(randi_range(2, 4)):
				var common_list: Array = pool.get("common", [])
				if not common_list.is_empty():
					var enemy_id: String = common_list[randi() % common_list.size()]
					boss_wave.append(_create_enemy_instance(enemy_id, "normal", diff_mult, stage))
			return boss_wave

	var enemies: Array = []
	for i in range(num_enemies):
		var roll := randi_range(0, 99)
		var tier := "common"
		if roll < int(weights.get("rare", 5)):
			tier = "rare"
		elif roll < int(weights.get("rare", 5)) + int(weights.get("uncommon", 25)):
			tier = "uncommon"

		var tier_list: Array = pool.get(tier, pool.get("common", []))
		if tier_list.is_empty():
			tier_list = pool.get("common", ["ghowl"])

		var enemy_id: String = tier_list[randi() % tier_list.size()]
		var stat_tier := "normal"
		if tier == "rare":
			stat_tier = "elite"
		enemies.append(_create_enemy_instance(enemy_id, stat_tier, diff_mult, stage))

	return enemies


## Create a single enemy instance dictionary
func _create_enemy_instance(enemy_id: String, stat_tier: String, diff_mult: float, stage: int) -> Dictionary:
	var base: Dictionary = BASE_STATS.get(stat_tier, BASE_STATS["normal"])
	var stage_mult := 1.0 + (stage - 1) * 0.15  # 15% more per stage

	var hp := int(float(base["hp"]) * diff_mult * stage_mult)
	var attack := int(float(base["attack"]) * diff_mult * stage_mult)
	var defense := int(float(base["defense"]) * diff_mult * stage_mult)
	var evasion := int(float(base["evasion"]) * diff_mult)

	return {
		"id": enemy_id,
		"name": _format_enemy_name(enemy_id),
		"hp": hp,
		"max_hp": hp,
		"attack": attack,
		"defense": defense,
		"evasion": evasion,
		"exp_reward": int(float(base["exp"]) * diff_mult * stage_mult),
		"meseta_reward": randi_range(int(base["meseta_min"]), int(base["meseta_max"])),
		"is_boss": stat_tier == "boss",
		"is_rare": stat_tier == "elite",
		"status_effects": [],
		"alive": true,
	}


func _format_enemy_name(enemy_id: String) -> String:
	return enemy_id.replace("-", " ").capitalize()


## Get the enemy pool for an area
func get_enemy_pool(area_id: String) -> Dictionary:
	return _enemy_pools.get(area_id, {})
