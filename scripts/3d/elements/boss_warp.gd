extends WarpBase
class_name BossWarp
## Boss-arena warp — the entrance to a boss fight. Uses the large o0s_warpb (big)
## warp model instead of the medium o0s_warpm area-transition warp, so the step
## into the boss room reads as a boss warp, not just another area gate. Extends
## WarpBase directly (not AreaWarp) to avoid AreaWarp's class-scope pack-only
## red-beam preload; the goal-pad's separate GateTrigger drives the actual warp,
## so this element is purely the boss-warp visual.


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpb.glb"
	collision_size = Vector3(4, 5, 4)
	auto_collect = false
