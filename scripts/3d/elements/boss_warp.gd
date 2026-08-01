extends AreaWarp
class_name BossWarp
## Boss-arena warp — the entrance to a boss fight. Uses the large o0s_warpb
## (big) warp model instead of the medium o0s_warpm area-transition warp, so the
## step into the boss room reads as a boss warp, not just another area gate.
## Inherits AreaWarp's beam material + locked/open state handling.


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpb.glb"
	collision_size = Vector3(4, 5, 4)
