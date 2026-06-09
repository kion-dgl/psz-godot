extends GameElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed

signal destroyed_wall

const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat.gdshader")

## Whether this wall can be destroyed by player attacks
@export var is_destructible: bool = true

## Collision body for physical presence
var collision_body: StaticBody3D


func _init() -> void:
	element_state = "intact"
	model_path = "valley/o01_wall.glb"
	collision_size = Vector3(6, 1.85, 0.52)


func _ready() -> void:
	super._ready()
	collision_body = _build_static_collision("WallCollision")
	_setup_textures()


func _setup_textures() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture:
				var smat := ShaderMaterial.new()
				smat.shader = MIRROR_SHADER
				smat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				smat.set_shader_parameter("uv_scale", Vector2(2, 2))
				smat.set_shader_parameter("mirror_x", true)
				smat.set_shader_parameter("mirror_y", true)
				mesh.set_surface_override_material(surface, smat)
	)


func _apply_state() -> void:
	match element_state:
		"intact":
			set_element_visible(true)
			if collision_body:
				collision_body.collision_layer = 1
		"destroyed":
			set_element_visible(false)
			if collision_body:
				collision_body.collision_layer = 0


## Called when the wall takes damage (from player attacks)
func take_damage(_amount: int = 1) -> void:
	if not is_destructible:
		return
	if element_state == "destroyed":
		return

	destroy()


## Destroy the wall
func destroy() -> void:
	if element_state == "destroyed":
		return

	set_state("destroyed")
	destroyed_wall.emit()
	print("[Wall] Destroyed")
