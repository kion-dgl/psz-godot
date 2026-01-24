extends WarpBase
class_name StartWarp
## Small warp gate at stage start/end points.
## Uses o0s_warps (small warp) model.


func _init() -> void:
	super._init()
	model_path = "special/o0s_warps.glb"
