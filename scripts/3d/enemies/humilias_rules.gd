class_name HumiliasRules extends RefCounted
const DATA = preload("res://data/re_reference/robot_controller_contract.json")
static func split_due(phase: int, ticks: int, hp: int, maximum: int, _tier: int) -> bool:
	if phase >= 3 or ticks < 240: return false
	var fraction := hp*4096/maxi(1,maximum)
	return fraction <= int([3072,2048,1024][phase])

static func split_duration(_tier: int) -> int:
	return 240

static func floor_pattern(round_index: int) -> Array:
	# Five dangerous panels, four safe panels; alternate cross and diagonals.
	return [[0,2,4,6,8],[1,3,4,5,7],[0,1,4,7,8]][posmod(round_index,3)]
