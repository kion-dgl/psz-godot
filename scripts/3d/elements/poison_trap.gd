extends NeedleTrap
class_name PoisonTrap
## Shares floor overlap/cooldown machinery; delivers poison instead of spike damage.
const GAS_TEXTURE := "o0c_1_poisonm2"
const GAS_PROFILES := {
	"o0c_1_poisonm": {"uv_scale": Vector2(2, -1), "uv_offset": Vector2(0, 1.5), "mirror_x": true, "mirror_y": false},
	"o0c_1_poisonm2": {"uv_scale": Vector2(1, -2), "uv_offset": Vector2(0, 1), "mirror_x": false, "mirror_y": true},
}
func _init() -> void:
	trap_kind = "poison_trap"
	model_path = "valley/o0c_poisonm.glb"
	collision_size = Vector3(6.1, 1.0, 6.1)
	damage = 0

func _setup_materials() -> void:
	_spike_materials = _setup_split_materials(GAS_TEXTURE, GAS_PROFILES)

func _deliver_hit(body: Node3D) -> void:
	if body.has_method("apply_status_effect"): body.apply_status_effect("poison")
