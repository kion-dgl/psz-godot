extends GameElement
class_name StepSwitch
## Floor-activated switch that triggers when stepped on.
## States: off, on

signal activated
signal deactivated


func _init() -> void:
	model_path = "valley/o0c_switchf.glb"
	auto_collect = true  # Triggers when player steps on it
	collision_size = Vector3(1.5, 0.5, 1.5)
	element_state = "off"


func _apply_state() -> void:
	if not model:
		return

	apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if element_state == "off":
				std_mat.uv1_offset.y = 0.5
				std_mat.emission_enabled = false
			else:  # on
				std_mat.uv1_offset.y = 0.0
				std_mat.emission_enabled = true
				std_mat.emission = Color(0, 1, 0)
				std_mat.emission_energy_multiplier = 0.3
	)


func _on_collected(_player: Node3D) -> void:
	# Step switch activates when stepped on
	if element_state == "off":
		turn_on()


## Turn switch on
func turn_on() -> void:
	if element_state == "on":
		return
	set_state("on")
	activated.emit()
	print("[StepSwitch] Activated")


## Turn switch off
func turn_off() -> void:
	if element_state == "off":
		return
	set_state("off")
	deactivated.emit()
	print("[StepSwitch] Deactivated")
