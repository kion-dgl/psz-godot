extends GameElement
class_name Box
## Destructible container that can drop items when destroyed.
## States: intact, destroyed

signal destroyed_box

const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat.gdshader")

## Whether this box is a rare variant (uses o0c_recont instead of o01_cont)
@export var is_rare: bool = false

## Drop type when destroyed (meseta, weapon, armor, item, none)
@export var drop_type: String = "none"

## Drop amount for meseta or item ID for items
@export var drop_value: String = ""

## Collision body for physical presence
var collision_body: StaticBody3D

## Hurtbox for receiving hits from player attack hitbox
var hurtbox: Hurtbox


func _init() -> void:
	interactable = false  # Destroyed by attacking, not interacting
	element_state = "intact"
	collision_size = Vector3(1, 1, 1)


func _ready() -> void:
	if is_rare:
		model_path = "valley/o0c_recont.glb"
	else:
		model_path = "valley/o01_cont.glb"

	super._ready()
	_setup_box_collision()
	_setup_hurtbox()
	_setup_textures()


func _setup_box_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "BoxCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	collision_body.add_child(shape)

	add_child(collision_body)


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "BoxHurtbox"
	hurtbox.owner_node = self
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	hurtbox.add_child(shape)
	add_child(hurtbox)


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
				if is_rare:
					smat.set_shader_parameter("uv_offset", Vector2(0, 1))
				mesh.set_surface_override_material(surface, smat)
	)


func _apply_state() -> void:
	match element_state:
		"intact":
			set_element_visible(true)
			if collision_body:
				collision_body.collision_layer = 1
			if hurtbox:
				hurtbox.monitorable = true
		"destroyed":
			set_element_visible(false)
			if collision_body:
				collision_body.collision_layer = 0
			if hurtbox:
				hurtbox.monitorable = false


## Called when the box takes damage (from player attacks via Hurtbox)
func take_damage(_amount: int = 1, _knockback: Vector3 = Vector3.ZERO) -> void:
	if element_state == "destroyed":
		return

	destroy()


## Destroy the box and spawn drops
func destroy() -> void:
	if element_state == "destroyed":
		return

	set_state("destroyed")
	destroyed_box.emit()

	# Spawn drop if configured
	if drop_type != "none":
		_spawn_drop()

	print("[Box] Destroyed")


func _spawn_drop() -> void:
	# Get the parent to spawn the drop at the box's position
	var parent := get_parent()
	if not parent:
		return

	var drop: GameElement = null

	match drop_type:
		"meseta":
			drop = DropMeseta.new()
			drop.amount = int(drop_value) if not drop_value.is_empty() else 10
		"item", "weapon", "armor":
			if not drop_value.is_empty():
				drop = DropItem.new()
				drop.item_id = drop_value
				drop.amount = 1
		_:
			return

	if drop:
		var world_pos := global_position
		world_pos.y += 0.5  # Spawn slightly above ground
		drop.position = parent.to_local(world_pos)
		parent.call_deferred("add_child", drop)
