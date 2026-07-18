extends Node
## Autoload that loads data/enemy_attacks.json — the per-enemy attack tables (range
## bands, weights, damage_mult, windup/damage-window fractions, arc shape) that drive
## the frame-tied attack model in EnemyBase. Keyed by EnemyData `id`. The JSON is the
## authority for ATTACK TABLES + fsm params only; EnemyData .tres stays authoritative
## for stats (attack_base, ranges, cooldown). The JSON `stats` block is ignored here
## (it mirrors .tres for the web sim). Spec /mechanics/enemy-attacks. #509.

const ATTACKS_PATH := "res://data/enemy_attacks.json"

var _defaults: Dictionary = {}
var _enemies: Dictionary = {}


func _ready() -> void:
	var text := ""
	if FileAccess.file_exists(ATTACKS_PATH):
		text = FileAccess.get_file_as_string(ATTACKS_PATH)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed is Dictionary:
		_defaults = parsed.get("defaults", {})
		_enemies = parsed.get("enemies", {})
	else:
		push_warning("[EnemyAttackRegistry] could not parse %s" % ATTACKS_PATH)
	print("[EnemyAttackRegistry] Loaded %d enemies" % _enemies.size())


## Resolved attack list for an enemy id — each attack has every field present (its
## values merged over defaults.attack). A missing enemy yields a single basic melee
## attack so a non-empty table is always returned (mirrors types.ts missing-enemy path).
func get_attacks(enemy_id: String, attack_range: float = 2.0) -> Array:
	var entry: Dictionary = _enemies.get(enemy_id, {})
	var raw: Array = entry.get("attacks", [])
	if raw.is_empty():
		return [_merged_attack({"id": "basic", "clip": "atk", "max_range": attack_range})]
	var out: Array = []
	for a in raw:
		out.append(_merged_attack(a))
	return out


## Resolved fsm params for an enemy id (its `fsm` merged over defaults.fsm).
func get_fsm(enemy_id: String) -> Dictionary:
	var out: Dictionary = _defaults.get("fsm", {}).duplicate(true)
	var entry: Dictionary = _enemies.get(enemy_id, {})
	for k in entry.get("fsm", {}):
		out[k] = entry["fsm"][k]
	return out


func get_enemy_count() -> int:
	return _enemies.size()


func _merged_attack(a: Dictionary) -> Dictionary:
	var out: Dictionary = _defaults.get("attack", {}).duplicate(true)
	for k in a:
		out[k] = a[k]
	return out
