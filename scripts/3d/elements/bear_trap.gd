extends GameElement
class_name BearTrap
## Floor bear trap that snaps shut when a player or enemy steps on it.
## States: open (armed, waiting), closed (triggered, deals damage)
## Texture swap between o0c_1_tora1 (open) and o0c_1_tora2 (closed).

const TORA_TEX_OPEN := "o0c_1_tora1"
const TORA_TEX_CLOSED := "o0c_1_tora2"
const DAMAGE_AMOUNT := 25

var _tex_open: Texture2D
var _tex_closed: Texture2D
var _materials: Array[StandardMaterial3D] = []


func _init() -> void:
	model_path = "valley/o0c_torabasami.glb"
	element_state = "open"
	collision_size = Vector3(2.0, 1.0, 2.0)
	auto_collect = false
	interactable = false


func _ready() -> void:
	super._ready()
	_tex_open = load("res://assets/objects/valley/o0c_1_tora1.png") as Texture2D
	_tex_closed = load("res://assets/objects/valley/o0c_1_tora2.png") as Texture2D
	_cache_materials()
	_setup_trigger_area()
	_apply_state()


func _cache_materials() -> void:
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int) -> void:
		if mat is StandardMaterial3D:
			var dup := mat.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, dup)
			_materials.append(dup)
	)


func _setup_trigger_area() -> void:
	var area := Area3D.new()
	area.name = "TriggerArea"
	area.collision_layer = 4
	area.collision_mask = 2 | 8

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	area.add_child(shape)

	area.body_entered.connect(_on_body_stepped)
	add_child(area)
	interaction_area = area


func _on_body_stepped(body: Node3D) -> void:
	if element_state != "open":
		return
	set_state("closed")
	if body.has_method("take_damage"):
		body.take_damage(DAMAGE_AMOUNT)
	elif body.has_method("_on_hit_received"):
		body._on_hit_received(DAMAGE_AMOUNT, global_position)


func _apply_state() -> void:
	var tex: Texture2D = _tex_closed if element_state == "closed" else _tex_open
	if tex:
		for mat in _materials:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	if interaction_area:
		var armed: bool = element_state == "open"
		interaction_area.set_deferred("monitoring", armed)
		interaction_area.set_deferred("monitorable", armed)
