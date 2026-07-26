class_name WeaponComboConfig extends Resource
## Two-tier combo timing windows for one weapon type (#155/#461,
## spec /mechanics/combos). All values are FRACTIONS of the current swing's
## animation, indexed by the combo step being chained FROM (index 0 = the
## window during attack 1 that chains into attack 2). The finisher has no
## entry — it can't chain.
##
##   [0, chain_start)   miss-early → fumble, chain locked out for this swing
##   [chain_start, 1.0] chain → queue the next step, standard damage
##
## The #155 model carried a third "just-attack" tier with a damage bonus.
## Rozalin's #461 playtest established PSZ has no such tier — crit and damage
## bonuses come from stats and equipment, not combo timing — so what was
## `just_start` is now simply where the accept window opens. The accept
## window's extent is unchanged (it always ran [just_start, 1.0]); only the
## bonus sub-tier is gone.
##
## Starting values come from the PSO:BB motion frame counts (psobb-re,
## plymotion-profile.tsv) and are feel-tuning defaults — expected to move
## via playtest, per weapon.

## Accept-window start per chain-from step.
@export var chain_start: PackedFloat32Array = PackedFloat32Array([0.55, 0.55])


## Timing dict for chaining FROM `from_step` (1-based combo_state), or {} if
## that step has no window (finisher / out of range).
func timing_for_step(from_step: int) -> Dictionary:
	var idx := from_step - 1
	if idx < 0 or idx >= chain_start.size():
		return {}
	return {"chain_start": chain_start[idx]}
