extends WarpBase
class_name AreaWarp
## Medium warp gate for area transitions.
## Uses o0s_warpm (medium warp) model.
## States: locked, open (shared with Gate/KeyGate)


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpm.glb"
	collision_size = Vector3(3, 4, 3)
	element_state = "locked"


func _apply_state() -> void:
	# Skip WarpBase transparency — area warp stays fully opaque in both states
	pass
