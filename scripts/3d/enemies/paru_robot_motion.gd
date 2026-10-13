extends RefCounted
## Authored spatial adapters inside the recovered 299/54-tick controller spans.
static func drill_mode(cycle_index: int) -> String:
	return "burrow" if cycle_index == 2 else "hover"

static func submerged(tick: int) -> bool:
	return tick >= 60 and tick < 180

static func burrow_position(start: Vector3, goal: Vector3, tick: int) -> Vector3:
	var down := Vector3(0,-5,0)
	if tick < 15: return start
	if tick < 60: return start.lerp(start+down,(tick-15)/45.0)
	if tick < 180: return (start+down).lerp(goal+down,(tick-60)/120.0)
	if tick < 210: return (goal+down).lerp(goal,(tick-180)/30.0)
	return goal

static func hover_position(start: Vector3, goal: Vector3, tick: int) -> Vector3:
	var up := Vector3(0,2,0)
	if tick < 30: return start.lerp(start+up,tick/30.0)
	if tick < 90: return (start+up).lerp(goal+up,(tick-30)/60.0)
	if tick < 140: return (goal+up).lerp(goal,(tick-90)/50.0)
	return goal

static func followup_shot(cycle_index: int, tick: int, tier: int) -> bool:
	return cycle_index % 3 == 0 and tick >= 30 and tick < 30+(2+2*tier)*4 and (tick-30)%4 == 0
