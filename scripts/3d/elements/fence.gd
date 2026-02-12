extends GameElement
class_name Fence
## Blocks access to items or keys within a stage. Disabled by interact switches.
## States: active, disabled

## Fence variant type
enum FenceVariant { DEFAULT, FENCE4, SHORT, DIAGONAL }

@export var variant: FenceVariant = FenceVariant.DEFAULT

## Texture name that identifies laser meshes (to be hidden when disabled)
const LASER_TEXTURE_NAME := "o0c_1_fence2"

## Laser scroll speed (offset.x, units/sec)
const LASER_SCROLL_SPEED := 0.70

## Collision body for blocking when active
var collision_body: StaticBody3D

## Laser materials for scroll animation and state toggle
var _laser_materials: Array[StandardMaterial3D] = []


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
	_setup_laser_materials()


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


func _setup_laser_materials() -> void:
	if not model:
		return
	_laser_materials.clear()
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and LASER_TEXTURE_NAME in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_laser_materials.append(dup)
	)


func _update_animation(delta: float) -> void:
	for mat in _laser_materials:
		mat.uv1_offset.x -= LASER_SCROLL_SPEED * delta


func _apply_state() -> void:
	for mat in _laser_materials:
		match element_state:
			"active":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mat.albedo_color.a = 1.0
			"disabled":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.0

	if collision_body:
		match element_state:
			"active":
				collision_body.collision_layer = 1
			"disabled":
				collision_body.collision_layer = 0


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
