extends GameElement
class_name InteractSwitch
## Player-activated switch that disables fences. Requires interaction to toggle.
## States: off, on

signal activated
signal deactivated

## Emissive color when switch is on
const ON_EMISSION_COLOR := Color(0, 1, 0)  # Green
const ON_EMISSION_ENERGY: float = 0.3


func _init() -> void:
	model_path = "valley/o0c_switchs.glb"
	interactable = true
	collision_size = Vector3(1.5, 2, 1.5)
	element_state = "off"


func _apply_state() -> void:
	if not model:
		return

	apply_to_all_materials(_update_material)


func _update_material(mat: Material, _mesh: MeshInstance3D, _surface: int) -> void:
	if mat is StandardMaterial3D:
		var std_mat := mat as StandardMaterial3D

		# Apply UV offset for state indication
		if element_state == "off":
			std_mat.uv1_offset.y = 0.5
			std_mat.emission_enabled = false
		else:  # on
			std_mat.uv1_offset.y = 0.0
			std_mat.emission_enabled = true
			std_mat.emission = ON_EMISSION_COLOR
			std_mat.emission_energy_multiplier = ON_EMISSION_ENERGY


func _on_interact(_player: Node3D) -> void:
	toggle()


## Turn switch on
func turn_on() -> void:
	if element_state == "on":
		return
	set_state("on")
	activated.emit()
	print("[InteractSwitch] Activated")


## Turn switch off
func turn_off() -> void:
	if element_state == "off":
		return
	set_state("off")
	deactivated.emit()
	print("[InteractSwitch] Deactivated")


## Toggle switch state
func toggle() -> void:
	if element_state == "off":
		turn_on()
	else:
		turn_off()
