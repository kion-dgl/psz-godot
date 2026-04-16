extends GameElement
class_name NeedleTrap
## Floor spike trap that damages players on contact.
## States: off (spikes hidden, safe), on (spikes visible, deals damage)
## Light damage with invulnerability window so player can recover and leave.

const SPIKE_TEX_NAME := "o0c_1_needle2"
const DAMAGE_AMOUNT := 8
const INVULN_TIME := 2.0

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
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int) -> void:
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			var dup := std_mat.duplicate() as StandardMaterial3D
			dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			if std_mat.albedo_texture:
				std_mat.albedo_texture.flags_mirrored_repeat = true
			mesh.set_surface_override_material(surface, dup)
			if std_mat.albedo_texture and SPIKE_TEX_NAME in std_mat.albedo_texture.resource_path:
				_spike_material = dup
			else:
				_base_material = dup
	)


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
		body.take_damage(DAMAGE_AMOUNT)


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
