extends GameElement
class_name NeedleTrap
## Floor spike trap that damages players on contact.
## States: off (spikes hidden, safe), on (spikes visible, deals damage)
## Light damage with invulnerability window so player can recover and leave.

const SPIKE_TEX_NAME := "o0c_1_needle2"
## Original NSBMD Max-mode SRT and per-surface wrap bits; /states/trap-validation.
const MATERIAL_PROFILES := {
	"o0c_1_needle": {"uv_scale": Vector2(2.0, -1.0), "uv_offset": Vector2(0.0, 1.5), "mirror_x": true, "mirror_y": false},
	"o0c_1_needle2": {"uv_scale": Vector2(1.0, -2.0), "uv_offset": Vector2(0.0, 2.0), "mirror_x": false, "mirror_y": true},
}
const DAMAGE_AMOUNT := 8
const INVULN_TIME := 2.0

## Ordinary floor-plate damage; environmental hazards have distinct delivery.
@export var damage: int = DAMAGE_AMOUNT
@export var trap_kind: String = "needle_trap"

var _spike_materials: Array[ShaderMaterial] = []
var _damage_area: Area3D
var _hit_bodies: Dictionary = {}


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
	if element_state != "on" or not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	if body.has_method("can_take_hit") and not body.can_take_hit():
		return
	var body_id: int = body.get_instance_id()
	if _hit_bodies.has(body_id):
		return
	_hit_bodies[body_id] = INVULN_TIME
	_deliver_hit(body)

func _deliver_hit(body: Node3D) -> void:
	body.take_damage(damage)


func _update_animation(delta: float) -> void:
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
	for material in _spike_materials:
		material.set_shader_parameter("visibility_alpha", 1.0 if element_state == "on" else 0.0)

	if _damage_area:
		_damage_area.set_deferred("monitoring", element_state == "on")
		_damage_area.set_deferred("monitorable", element_state == "on")

	_hit_bodies.clear()
