extends GameElement
class_name NeedleTrap
## Floor spike trap that damages players and enemies on contact.
## States: off (retracted, safe), on (extended, deals damage)
## Texture swap between o0c_1_needle (off/gray) and o0c_1_needle2 (on/orange).

const NEEDLE_TEX_OFF := "o0c_1_needle"
const NEEDLE_TEX_ON := "o0c_1_needle2"
const DAMAGE_AMOUNT := 15
const DAMAGE_INTERVAL := 0.8

var _tex_on: Texture2D
var _tex_off: Texture2D
var _materials: Array[StandardMaterial3D] = []
var _damage_area: Area3D
var _damage_timer: float = 0.0
var _bodies_in_area: Array[Node3D] = []


func _init() -> void:
	model_path = "valley/o0c_needle.glb"
	element_state = "off"
	collision_size = Vector3(3.0, 1.0, 3.0)
	auto_collect = false
	interactable = false


func _ready() -> void:
	super._ready()
	_tex_off = load("res://assets/objects/valley/o0c_1_needle.png") as Texture2D
	_tex_on = load("res://assets/objects/valley/o0c_1_needle2.png") as Texture2D
	_cache_materials()
	_setup_damage_area()
	_apply_state()


func _cache_materials() -> void:
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int) -> void:
		if mat is StandardMaterial3D:
			var dup := mat.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, dup)
			_materials.append(dup)
	)


func _setup_damage_area() -> void:
	_damage_area = Area3D.new()
	_damage_area.name = "DamageArea"
	_damage_area.collision_layer = 4
	_damage_area.collision_mask = 2 | 8

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	_damage_area.add_child(shape)

	_damage_area.body_entered.connect(_on_damage_body_entered)
	_damage_area.body_exited.connect(_on_damage_body_exited)
	add_child(_damage_area)


func _on_damage_body_entered(body: Node3D) -> void:
	if element_state != "on":
		return
	_bodies_in_area.append(body)
	_deal_damage(body)


func _on_damage_body_exited(body: Node3D) -> void:
	_bodies_in_area.erase(body)


func _update_animation(delta: float) -> void:
	if element_state != "on" or _bodies_in_area.is_empty():
		return
	_damage_timer += delta
	if _damage_timer >= DAMAGE_INTERVAL:
		_damage_timer = 0.0
		for body in _bodies_in_area:
			if is_instance_valid(body):
				_deal_damage(body)


func _deal_damage(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(DAMAGE_AMOUNT)
	elif body.has_method("_on_hit_received"):
		body._on_hit_received(DAMAGE_AMOUNT, global_position)


func _apply_state() -> void:
	var tex: Texture2D = _tex_on if element_state == "on" else _tex_off
	if tex:
		for mat in _materials:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	if _damage_area:
		_damage_area.set_deferred("monitoring", element_state == "on")
		_damage_area.set_deferred("monitorable", element_state == "on")

	_bodies_in_area.clear()
	_damage_timer = 0.0
