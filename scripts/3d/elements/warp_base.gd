extends GameElement
class_name WarpBase
## Base class for warp gates (start warp, area warp, boss warp).
## States: active, inactive

signal warp_activated(target_map: String, spawn_index: int)

## Target map to warp to
@export var target_map: String = ""

## Spawn index in target map
@export var spawn_index: int = 0


func _init() -> void:
	auto_collect = true  # Warp when player enters
	collision_size = Vector3(2, 3, 2)
	element_state = "active"


func _apply_state() -> void:
	if not model:
		return

	apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if element_state == "inactive":
				std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				std_mat.albedo_color.a = 0.5
			else:
				std_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				std_mat.albedo_color.a = 1.0
	)


func _on_collected(player: Node3D) -> void:
	if element_state != "active":
		return

	if target_map.is_empty():
		print("[Warp] No target map configured")
		return

	print("[Warp] Activating warp to: ", target_map, " spawn: ", spawn_index)
	warp_activated.emit(target_map, spawn_index)

	# Trigger map transition via game controller
	get_tree().call_group("map_controller", "on_trigger_activated", target_map, spawn_index)


## Activate the warp gate
func activate() -> void:
	set_state("active")


## Deactivate the warp gate
func deactivate() -> void:
	set_state("inactive")
