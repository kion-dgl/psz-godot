class_name BossPhaseRules extends RefCounted
## Narrow ports of ov19:0219B154 and ov31:0219BE30. See boss-behavior-analysis.md.

class FalzDamage extends RefCounted:
	var flags := 0
	var budget := 0

	func hit(hp_after: int, max_hp: int, signed_delta: int) -> int:
		var request := 0
		if hp_after * 4 < max_hp:
			if not flags & 4:
				flags |= 4
				request = 3
		elif hp_after * 2 < max_hp and not flags & 2:
			flags |= 2
			request = 2
		if request == 0:
			budget -= signed_delta
			if budget * 16 >= max_hp:
				budget = 0 # The original does NOT send request 1 here.
		return request


static func trinity_piece_request(previous: int, remaining: int, flags: int) -> int:
	if flags & 2 or remaining >= previous:
		return 0
	return 4 if remaining < 2 and not flags & 1 else 3
