class_name BossDamageRules extends RefCounted
## Narrow original damage-hook rules. Call after HP subtraction, before death.
## This is not the boss scheduler. Directional history needs source/part context.

class ReyburnBudgets extends RefCounted:
	var part_budget: int # controller+94: only packet byte 9 == 1
	var modifier_budget: int # controller+98: all hits, positive guarded

	func _init(base_stat_hp: int) -> void:
		part_budget = (base_stat_hp * 819 + 2048) >> 12
		modifier_budget = (base_stat_hp * 1638 + 2048) >> 12

	# Signed short delta from ov20:0219A114; damage is negative.
	# Return true exactly when the part callback 021986BC must run.
	func hit(delta: int, part: int) -> bool:
		var part_depleted := false
		if part == 1:
			if part_budget > 0:
				part_budget += delta
				part_depleted = part_budget <= 0
		if modifier_budget > 0:
			modifier_budget += delta
		return part_depleted


static func octo_hp_after_hook(hp_after_subtraction: int, max_hp: int, entity_mode: int) -> int:
	# ov21:0219A340. Clamp depends on mode, not the transition latch.
	@warning_ignore("integer_division")
	var half := max_hp / 2
	return maxi(hp_after_subtraction, half) if entity_mode == 0 else hp_after_subtraction
