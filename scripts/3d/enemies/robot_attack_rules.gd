class_name RobotAttackRules extends RefCounted
## Recovered counter boundaries, independent of provisional attack selection.
static func orbit_shoot(tick: int) -> bool:
	return tick >= 0 and tick < 150 and tick % 22 == 0

static func contact(state: int, tick: int) -> bool:
	match state:
		11: return tick >= 7 and tick < 24
		13: return tick >= 120 and tick < 149
	return false

static func duration(state: int) -> int:
	return int({8:150,11:54,12:299,13:149}.get(state,90))

static func parameters(hp: int, maximum: int, tier: int) -> Array[int]:
	var rows: Array = preload("res://data/re_reference/robot_controller_contract.json").data.parameters
	var row: Array = rows[clampi(tier,0,2)]
	var fraction := hp * 4096 / maxi(1,maximum)
	var result: Array[int] = []
	for i in 6:
		result.append(int(row[14+i])+(int(row[8+i])-int(row[14+i]))*fraction/4096)
	return result
