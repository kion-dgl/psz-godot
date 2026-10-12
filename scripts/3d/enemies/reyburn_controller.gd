class_name ReyburnController extends RefCounted
## ov20:0219A114/A2BC/A3EC; single-target adapter supplies distance and bearing.
var budgets: BossDamageRules.ReyburnBudgets
var base_hp: int
var max_hp: int
var enhanced := false
var bite_blocked := false
var cumulative_damage := 0
var reaction_damage := 0
var head_damage := 0
var off_angle_damage := 0
var off_angle_hits := 0
var fallback_timer := 375
var flight_timer := 1500
var breath_timer := 150
var aerial_alternation := false

func _init(base: int, maximum: int) -> void:
	base_hp = base
	max_hp = maximum
	budgets = BossDamageRules.ReyburnBudgets.new(base)

func tick() -> void:
	fallback_timer -= 1
	flight_timer -= 1
	breath_timer -= 1

func hit(damage: int, part: int, bearing: float, source_known: bool) -> bool:
	var broken := budgets.hit(-damage,part)
	cumulative_damage += damage
	reaction_damage += damage
	if part == 1: head_damage += damage
	if source_known and absf(bearing) >= TAU * 0x2aaa / 65536.0:
		off_angle_damage += damage
		off_angle_hits += 1
	return broken

func notify(id: int) -> void:
	if id == 0: enhanced = true

func finish(id: int, flags: int = 0, retain_side_damage: bool = false) -> void:
	if id in [1,12]: reaction_damage = 0
	if id == 2: cumulative_damage = 0
	if id in [4,8,14]: off_angle_hits = 0
	if id in [8,14] and not (enhanced and retain_side_damage): off_angle_damage = 0
	if flags & 4: fallback_timer = 375
	if flags & 2: flight_timer = 1500
	if id in [0,6]: breath_timer = 150
	if id == 11: aerial_alternation = true
	if id in [9,10]: aerial_alternation = false

func priority(distance: float, bearing: float) -> Dictionary:
	if not enhanced and budgets.modifier_budget <= 0: return {"id":1}
	if off_angle_damage >= (base_hp * 410 + 2048) >> 12: return {"id":14 if enhanced else 8}
	if off_angle_hits >= 10: return {"id":4}
	if cumulative_damage >= (max_hp * 819 + 2048) >> 12:
		return {"id":2,"duration":240 if enhanced else 150}
	if not bite_blocked:
		if distance >= 12.5 and distance <= 17.5 and absf(bearing) <= TAU * 0x0555 / 65536.0:
			return {"id":5,"normal":0,"advance":1}
		if distance >= 8.0 and distance <= 10.0 and absf(bearing) <= TAU * 0x0471 / 65536.0:
			return {"id":5,"normal":1,"advance":0}
	if breath_timer <= 0 and distance >= 15.0 and distance <= 50.0 and absf(bearing) <= TAU / 8.0:
		return {"id":6,"types":[0],"counts":[1]}
	return {"id":-1}

func fallback(roll: int, secondary: int) -> Dictionary:
	match roll:
		0:
			if enhanced and secondary == 0: return {"id":15,"flags":5,"types":[0,1],"counts":[1,1]}
			return {"id":6,"flags":5,"types":[secondary],"counts":[3 if enhanced else 1]}
		1:
			if not bite_blocked: return {"id":5,"flags":5,"normal":2,"advance":1,"turn":0x01c7}
		2:
			return {"id":13 if enhanced else 7,"flags":5,"duration":150,"types":[secondary],"counts":[1]}
		3: return {"id":3,"flags":5}
	return {"id":-1}
