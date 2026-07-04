class_name WeaponComboConfig extends Resource
## Three-tier combo timing windows for one weapon type (#155,
## spec /mechanics/combos). All values are FRACTIONS of the current swing's
## animation, indexed by the combo step being chained FROM (index 0 = the
## window during attack 1 that chains into attack 2). The finisher has no
## entry — it can't chain.
##
##   [0, just_start)        miss-early → no-op, not buffered
##   [just_start, just_end) just-attack → chain + just_damage_mult bonus
##   [just_end, 1.0]        normal → chain, standard damage
##
## Starting values come from the PSO:BB motion frame counts (psobb-re,
## plymotion-profile.tsv) and are feel-tuning defaults — expected to move
## via playtest, per weapon.

## Just-window start per chain-from step.
@export var just_start: PackedFloat32Array = PackedFloat32Array([0.55, 0.55])

## Just-window end (= normal-window start) per chain-from step.
@export var just_end: PackedFloat32Array = PackedFloat32Array([0.70, 0.70])

## Damage multiplier applied to a swing chained via the just window.
@export var just_damage_mult: float = 1.3


## Timing dict for chaining FROM `from_step` (1-based combo_state), or {} if
## that step has no window (finisher / out of range).
func timing_for_step(from_step: int) -> Dictionary:
	var idx := from_step - 1
	if idx < 0 or idx >= just_start.size() or idx >= just_end.size():
		return {}
	return {
		"just_start": just_start[idx],
		"just_end": just_end[idx],
	}
