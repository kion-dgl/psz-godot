extends GameElement
class_name NeedleTrap
## Floor spike trap that damages players on contact.
## States: off (safe), on (cycles extended needles and a safe retracted interval).
## Light damage with invulnerability window so player can recover and leave.

const SPIKE_TEX_NAME := "o0c_1_needle2"
## Preserve the source plate mapping; extended needles use the Storybook spike strip.
const MATERIAL_PROFILES := {
	"o0c_1_needle": {"uv_scale": Vector2(2.0, -1.0), "uv_offset": Vector2(0.0, 1.5), "mirror_x": true, "mirror_y": false},
	"o0c_1_needle2": {"uv_scale": Vector2(2.0, 1.0), "uv_offset": Vector2(-0.17, -0.18), "mirror_x": true, "mirror_y": true},
}
const DAMAGE_AMOUNT := 8
const INVULN_TIME := 2.0
const EXTENDED_TIME := 1.0
const RETRACTED_TIME := 3.0

## Ordinary floor-plate damage; environmental hazards have distinct delivery.
@export var damage: int = DAMAGE_AMOUNT
@export var trap_kind: String = "needle_trap"

var _spike_materials: Array[ShaderMaterial] = []
var _damage_area: Area3D
var _hit_bodies: Dictionary = {}
var cycles_spikes := true
var spikes_extended := false
var _phase_left := EXTENDED_TIME


func _init() -> void:
	model_path = "valley/o0c_needle.glb"
	element_state = "off"
	collision_size = Vector3(3.0, 1.0, 3.0)
	auto_collect = false
	interactable = false


func _ready() -> void:
	super._ready()
	_setup_materials()
	_setup_damage_area()
	_apply_state()


func _setup_materials() -> void:
	_spike_materials = _setup_split_materials(SPIKE_TEX_NAME, MATERIAL_PROFILES)
	_configure_needle_surfaces()

func _configure_needle_surfaces() -> void:
	for material in _spike_materials:
		material.set_shader_parameter("preserve_horizontal_faces", true)
		material.set_shader_parameter("align_needle_slots", true)

func _setup_damage_area() -> void:
	_damage_area = Area3D.new()
	_damage_area.name = "DamageArea"
	_damage_area.collision_layer = 4
	_damage_area.collision_mask = 2

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	_damage_area.add_child(shape)

	_damage_area.body_entered.connect(_on_damage_body_entered)
	add_child(_damage_area)


func _on_damage_body_entered(body: Node3D) -> void:
	if not spikes_extended or element_state != "on" or not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	if body.has_method("can_take_hit") and not body.can_take_hit():
		return
	var body_id: int = body.get_instance_id()
	if _hit_bodies.has(body_id):
		return
	_hit_bodies[body_id] = INF if cycles_spikes else INVULN_TIME
	_deliver_hit(body)

func _deliver_hit(body: Node3D) -> void:
	body.take_damage(damage)


func _update_animation(delta: float) -> void:
	if cycles_spikes and element_state == "on":
		_phase_left -= delta
		while _phase_left <= 0.0:
			spikes_extended = not spikes_extended
			_phase_left += EXTENDED_TIME if spikes_extended else RETRACTED_TIME
			_hit_bodies.clear()
			_update_spike_visibility()
	var expired: Array = []
	for body_id in _hit_bodies:
		_hit_bodies[body_id] -= delta
		if _hit_bodies[body_id] <= 0:
			expired.append(body_id)
	for body_id in expired:
		_hit_bodies.erase(body_id)
	# Entry alone misses players who remain inside after a hit or dodge.
	if element_state == "on" and _damage_area:
		for body in _damage_area.get_overlapping_bodies():
			_on_damage_body_entered(body)


func _apply_state() -> void:
	spikes_extended = element_state == "on"
	_phase_left = EXTENDED_TIME
	_update_spike_visibility()

	if _damage_area:
		_damage_area.set_deferred("monitoring", element_state == "on")
		_damage_area.set_deferred("monitorable", element_state == "on")

	_hit_bodies.clear()


func _update_spike_visibility() -> void:
	for material in _spike_materials:
		material.set_shader_parameter("visibility_alpha", 1.0 if spikes_extended else 0.0)
