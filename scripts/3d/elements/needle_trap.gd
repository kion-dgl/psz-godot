extends GameElement
class_name NeedleTrap
## Floor spike trap that damages players on contact.
## States: off (spikes hidden, safe), on (spikes visible, deals damage)
## Light damage with invulnerability window so player can recover and leave.

const SPIKE_TEX_NAME := "o0c_1_needle2"
const INVULN_TIME := 2.0

## Contact damage. The authored set table (psz-re Q6) gives the real per-type
## amounts — needler 25, burn 50, gun ~40, elemental ~30 — so the spawner sets
## this from the object data. Defaults to the original light value.
@export var damage_amount: int = 8
## Which psz-re trap this instance represents (needler/burn/gun/elemental).
## The four contact traps share this actor until dedicated models exist.
@export var trap_kind: String = "needler"
## Elemental subtype (heal/heat/light/ice) for trap_kind == "elemental".
@export var element: String = ""

var _spike_material: StandardMaterial3D = null
var _base_material: StandardMaterial3D = null
var _damage_area: Area3D
var _invuln_timer: float = 0.0
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
	var mats := _setup_split_materials(SPIKE_TEX_NAME)
	_spike_material = mats["feature"]
	_base_material = mats["base"]


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
	if element_state != "on":
		return
	var body_id: int = body.get_instance_id()
	if _hit_bodies.has(body_id):
		return
	_hit_bodies[body_id] = INVULN_TIME
	if body.has_method("take_damage"):
		body.take_damage(damage_amount)


func _update_animation(delta: float) -> void:
	var expired: Array = []
	for body_id in _hit_bodies:
		_hit_bodies[body_id] -= delta
		if _hit_bodies[body_id] <= 0:
			expired.append(body_id)
	for body_id in expired:
		_hit_bodies.erase(body_id)


func _apply_state() -> void:
	if _spike_material:
		match element_state:
			"on":
				_spike_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_spike_material.albedo_color.a = 1.0
				_spike_material.alpha_scissor_threshold = 0.5
			"off":
				_spike_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_spike_material.albedo_color.a = 0.0
				_spike_material.alpha_scissor_threshold = 1.0

	if _damage_area:
		_damage_area.set_deferred("monitoring", element_state == "on")
		_damage_area.set_deferred("monitorable", element_state == "on")

	_hit_bodies.clear()
