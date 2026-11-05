extends RefCounted
## Authored levels are a remake extension of the original difficulty-tier model.
const Original = preload("res://data/re_reference/enemy_combat_stats.json")
const AREA_LEVELS := {"gurhacia": 1, "rioh": 5, "ozette": 10, "paru": 15, "makara": 20, "arca": 25, "dark": 30}
const DIFFICULTY_LEVELS := {"normal": 0, "hard": 30, "super-hard": 60}

static func level_for(session: Dictionary, authored: int = 0, current_area: String = "") -> int:
	var coliseum := int(session.get("coliseum_enemy_level", 0))
	if coliseum > 0:
		return clampi(coliseum, 1, 100)
	var base: int = authored if authored > 0 else int(session.get("enemy_level", 0))
	if base <= 0:
		var area := current_area if not current_area.is_empty() else str(session.get("area_id", "gurhacia"))
		base = int(AREA_LEVELS.get(area, 1))
	return clampi(base + int(DIFFICULTY_LEVELS.get(session.get("difficulty", "normal"), 0)), 1, 100)

## Independently spawned boss components can supply their own recovered tier rows.
static func scaled(source: EnemyData, level: int, difficulty: String = "normal", rows_override: Array = []) -> EnemyData:
	var result: EnemyData = source.duplicate()
	var rows: Array = rows_override if not rows_override.is_empty() else Original.data.enemies.get(source.id, [])
	if not rows.is_empty():
		var tier: int = {"normal": 0, "hard": 1, "super-hard": 2}.get(difficulty, 0)
		var row: Array = rows[tier]
		result.hp_base = int(row[0])
		result.attack_base = int(row[1])
		result.attack_min = int(row[2])
		result.defense_base = int(row[3])
		result.evasion_base = int(row[7])
		result.original_attack_stats = true
	# Tier rows already incorporate difficulty; only scale authored normal-area levels.
	var growth := float(maxi(level - int(DIFFICULTY_LEVELS.get(difficulty, 0)) - 1, 0))
	# Paru is one shared encounter pool; retail tier HP already budgets both robots.
	if source.id != "chaos_mobius":
		result.hp_base = maxi(1, int(result.hp_base * (1.0 + growth * 0.08)))
	result.attack_base = maxi(1, int(result.attack_base * (1.0 + growth * 0.05)))
	result.attack_min = int(result.attack_min * (1.0 + growth * 0.05))
	result.defense_base = int(result.defense_base * (1.0 + growth * 0.08))
	result.evasion_base = int(result.evasion_base * (1.0 + growth * 0.025))
	result.exp_reward = maxi(1, int(source.exp_reward * (1.0 + float(level - 1) * 0.1)))
	return result
