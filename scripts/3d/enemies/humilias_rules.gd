class_name HumiliasRules extends RefCounted
const DATA = preload("res://data/re_reference/robot_controller_contract.json")
static func split_due(phase: int, ticks: int, hp: int, maximum: int, tier: int) -> bool:
	if phase >= 3 or ticks < int(DATA.data.parameters[tier][5])*30: return false
	var fraction := hp*4096/maxi(1,maximum)
	return fraction <= int([3072,2048,1024][phase])

static func split_duration(tier: int) -> int:
	return int(DATA.data.parameters[tier][7])*30
