class_name OctoController extends RefCounted
## ov21:02199F84/A340/A458. Request IDs are not descriptor actions.
var mode := 0
var transition_latch := false
var transition_step := 0
var timers: Array[int] = [0,0,0,0] # C4, C8, CC, D0
var hit_count := 0
var absorption_level := 0

func tick() -> void:
	var offset := mode * 2
	timers[offset] += 1
	timers[offset + 1] += 1

func clamp_hp(hp: int, maximum: int) -> int:
	return BossDamageRules.octo_hp_after_hook(hp,maximum,mode)

func latch(hp: int, maximum: int) -> void:
	if mode == 0 and hp <= maximum / 2: transition_latch = true

func boundary(limbs_idle: bool) -> int:
	if not transition_latch: return 0
	match transition_step:
		0: transition_step = 2
		2:
			if limbs_idle: transition_step = 14
		14:
			if mode == 1: transition_step = 18
		18:
			transition_step = 0
			transition_latch = false
	return transition_step

func change_mode() -> void:
	mode = 1
	hit_count = 0

func select_request(spatial: bool, short_predicate: bool, limb_index: int, limbs_busy: bool) -> int:
	if mode == 0:
		if timers[0] > 1800: return 5
		if short_predicate: return 17
		if timers[1] > 750: return 11
		return 4 if spatial else 3
	if limb_index != -1: return 15
	if timers[2] > 1800 - absorption_level * 600: return 6
	if hit_count >= 11 and not limbs_busy: return 13
	if timers[3] >= 601 and not limbs_busy: return 12
	return 4 if spatial else 1

static func projectile_variant(row: int, roll: int) -> int:
	return row if roll < 90 else 2
