extends WarpBase
class_name AreaWarp
## Medium warp gate for area transitions.
## Uses o0s_warpm (medium warp) model.


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpm.glb"
	collision_size = Vector3(3, 4, 3)
