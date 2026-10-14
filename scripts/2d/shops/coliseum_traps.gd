extends RefCounted
## One hazard per visit, with an unconditional return route beside the entrance.
const ROWS := [
	{"id":"needle", "name":"Needle Trap", "trap_kind":"needle_trap", "hint":"Needles extend for 1 second, then retract safely for 3 seconds. Step off between pulses."},
	{"id":"bear", "name":"Bear Trap", "trap_kind":"capture_trap", "hint":"Step in, then escape before it closes. A free player can destroy the active trap with one hit. Trap Vision reveals it."},
	{"id":"gun1", "name":"Gun Trap · Type 1", "trap_kind":"gun_trap", "model":"o0c_gun01", "hint":"Approach from the front. Dodge the warning shot or attack to disable it."},
	{"id":"gun2", "name":"Gun Trap · Type 2", "trap_kind":"gun_trap", "model":"o0c_gun02", "hint":"Approach from the front. Dodge the warning shot or attack to disable it."},
	{"id":"clay", "name":"Clay / Needler Trap", "trap_kind":"needler_trap", "hint":"Approach or attack to trigger its directional sweep. Try its sides and rear."},
	{"id":"bomb", "name":"Bomb Container", "trap_kind":"burn_trap", "hint":"Attack the container, then escape the blast. Walking into it is safe."},
	{"id":"poison", "name":"Poison Needle Trap", "trap_kind":"poison_trap", "hint":"Needles apply poison only while extended. Step off during the 3-second retracted interval."},
	{"id":"heat", "name":"Heat Ball", "trap_kind":"heat_trap", "hint":"Approach to reveal and arm it. Escape the fuse or test the burn payload."},
	{"id":"ice", "name":"Ice Ball", "trap_kind":"ice_trap", "hint":"Approach to arm it. Test the freeze payload or attack to disarm it."},
	{"id":"light", "name":"Light Ball", "trap_kind":"light_trap", "hint":"Approach to arm it. Test the stun payload or escape the fuse."},
	{"id":"heal", "name":"Heal Ball", "trap_kind":"heal_trap", "hint":"Approach to trigger healing. Missing HP makes the result easier to see."},
]

static func groups() -> Array:
	return [{"name":"Trap Tests", "rows":ROWS.duplicate(true)}]

static func sections(row: Dictionary) -> Array:
	var trap := {"type":str(row.trap_kind), "position":[0.0, 0.0, -3.0]}
	if row.has("model"): trap.model = row.model
	return ColiseumRoster._one_cell_section("s00a_nr2", "a", "city", [
		trap,
		{"type":"telepipe", "spawn_condition":"immediate", "position":[5.0, 0.0, 13.0]},
	], false)
