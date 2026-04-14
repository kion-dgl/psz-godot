extends GameElement
class_name BearTrap
## Floor bear trap that snaps shut when a player or enemy steps on it.
## States: open (lasers visible, armed), closed (lasers hidden, triggered)
## GLB has two sub-meshes: container (always visible) and lasers (toggled).

const LASER_TEX_NAME := "o0c_1_tora2"
const DAMAGE_AMOUNT := 25

var _laser_material: StandardMaterial3D = null


func _init() -> void:
	model_path = "valley/o0c_torabasami.glb"
	element_state = "open"
	collision_size = Vector3(2.0, 1.0, 2.0)
	auto_collect = false
	interactable = false


func _ready() -> void:
	super._ready()
	_find_laser_material()
	_setup_trigger_area()
	_apply_state()


func _find_laser_material() -> void:
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int) -> void:
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and LASER_TEX_NAME in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_laser_material = dup
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
	if _laser_material:
		match element_state:
			"open":
				_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_laser_material.albedo_color.a = 1.0
				_laser_material.alpha_scissor_threshold = 0.5
			"closed":
				_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_laser_material.albedo_color.a = 0.0
				_laser_material.alpha_scissor_threshold = 1.0

	if interaction_area:
		var armed: bool = element_state == "open"
		interaction_area.set_deferred("monitoring", armed)
		interaction_area.set_deferred("monitorable", armed)
