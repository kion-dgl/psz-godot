extends GameElement
class_name Fence
## Blocks access to items or keys within a stage. Disabled by interact switches.
## States: active, disabled

## Fence variant type
enum FenceVariant { DEFAULT, FENCE4, SHORT, DIAGONAL }

@export var variant: FenceVariant = FenceVariant.DEFAULT

## Texture name that identifies laser meshes (to be hidden when disabled)
const LASER_TEXTURE_NAME := "o0c_1_fence2"

## Collision body for blocking when active
var collision_body: StaticBody3D

## Cached list of laser meshes
var _laser_meshes: Array[MeshInstance3D] = []


func _init() -> void:
	element_state = "active"
	collision_size = Vector3(3, 2, 0.5)


func _ready() -> void:
	# Set model path based on variant
	match variant:
		FenceVariant.DEFAULT:
			model_path = "valley/o0c_fence.glb"
		FenceVariant.FENCE4:
			model_path = "valley/o0c_fence4.glb"
		FenceVariant.SHORT:
			model_path = "valley/o0c_shfence.glb"
		FenceVariant.DIAGONAL:
			model_path = "valley/o0c_dgfance.glb"

	super._ready()
	_setup_fence_collision()
	_find_laser_meshes()


func _setup_fence_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "FenceCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	collision_body.add_child(shape)

	add_child(collision_body)


func _find_laser_meshes() -> void:
	if not model:
		return

	_laser_meshes.clear()
	_find_laser_meshes_recursive(model)


func _find_laser_meshes_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if _has_laser_texture(mesh_inst):
			_laser_meshes.append(mesh_inst)

	for child in node.get_children():
		_find_laser_meshes_recursive(child)


func _has_laser_texture(mesh_inst: MeshInstance3D) -> bool:
	for i in range(mesh_inst.get_surface_override_material_count()):
		var mat := mesh_inst.get_active_material(i)
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture:
				var tex_path := std_mat.albedo_texture.resource_path
				if LASER_TEXTURE_NAME in tex_path:
					return true
	return false


func _apply_state() -> void:
	match element_state:
		"active":
			_set_lasers_visible(true)
			if collision_body:
				collision_body.collision_layer = 1
		"disabled":
			_set_lasers_visible(false)
			if collision_body:
				collision_body.collision_layer = 0


func _set_lasers_visible(is_visible: bool) -> void:
	for mesh in _laser_meshes:
		mesh.visible = is_visible


## Activate the fence (block passage)
func activate() -> void:
	set_state("active")


## Disable the fence (allow passage, hide lasers)
func disable() -> void:
	set_state("disabled")


## Toggle fence state
func toggle() -> void:
	if element_state == "active":
		disable()
	else:
		activate()
