class_name ReyburnPacing extends RefCounted
## Authored playtest pacing around the recovered selector, in 30 Hz ticks.
const REST_TICKS := 75
const BITE_TICKS := 180
var rest_ticks := REST_TICKS
var bite_ticks := 0

func tick() -> void:
	rest_ticks = maxi(0, rest_ticks - 1)
	bite_ticks = maxi(0, bite_ticks - 1)

func completed(sequence: int) -> void:
	rest_ticks = REST_TICKS
	if sequence == 5: bite_ticks = BITE_TICKS

func target_defeated(player: Node3D) -> bool:
	return is_instance_valid(player) and bool(player.get("_is_defeated"))

func check_target(boss) -> void:
	if not is_instance_valid(boss.target): boss.target = boss._find_player()
	if not is_instance_valid(boss.target) or target_defeated(boss.target):
		if boss.state_field != "loaf":
			boss._clear_deliveries()
			boss._states.clear()
			boss._sequence.clear()
			boss._shots_left = 0
			boss._shot_wait = -1
			boss.sequence_id = -1
			boss.state_field = "loaf"
			boss.velocity = Vector3.ZERO
			boss.play_action(4, {0:-1})
	elif boss.state_field == "loaf":
		# A revived/replaced player gets the same breathing room as arena entry.
		boss._enter_next_state()
