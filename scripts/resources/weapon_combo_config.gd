class_name WeaponComboConfig extends Resource
## Two-tier combo timing for one weapon type (#461, spec /mechanics/combos).
## Values are FRACTIONS of the current swing's animation, indexed by the combo
## step being chained FROM (index 0 = the window during attack 1 that chains
## into attack 2). The finisher has no entry — it can't chain.
##
##   [0, just_start)  miss-early → FUMBLE (no chain; locks out this swing)
##   [just_start, 1.0] chain-accept → queue a normal chain
##
## `just_start` is the single chain-accept boundary: a press before it fumbles,
## a press at/after it queues the next step. There is no just-attack tier —
## crit/damage bonuses come from stats + equipment, not combo timing (#461).
##
## Starting values come from the PSO:BB motion frame counts (psobb-re,
## plymotion-profile.tsv) and are feel-tuning defaults — expected to move
## via playtest, per weapon.

## Chain-accept boundary per chain-from step: press before = fumble,
## press at/after = queue a normal chain. (Serialized name kept as
## `just_start` for .tres stability — it is the accept threshold, #461.)
@export var just_start: PackedFloat32Array = PackedFloat32Array([0.55, 0.55])


## Timing dict for chaining FROM `from_step` (1-based combo_state), or {} if
## that step has no window (finisher / out of range).
func timing_for_step(from_step: int) -> Dictionary:
	var idx := from_step - 1
	if idx < 0 or idx >= just_start.size():
		return {}
	return {
		"just_start": just_start[idx],
	}
