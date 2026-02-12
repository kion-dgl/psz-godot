extends GameElement
class_name Box
## Destructible container that can drop items when destroyed.
## States: intact, destroyed

signal destroyed_box

## Whether this box is a rare variant (uses o0c_recont instead of o01_cont)
@export var is_rare: bool = false

## Drop type when destroyed (meseta, weapon, armor, item, none)
@export var drop_type: String = "none"

## Drop amount for meseta or item ID for items
@export var drop_value: String = ""

## Collision body for physical presence
var collision_body: StaticBody3D


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


func _setup_textures() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			std_mat.texture_repeat = true
			std_mat.uv1_scale = Vector3(2, 2, 1)
			if is_rare:
				std_mat.uv1_offset = Vector3(0, 1, 0)
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


## Called when the box takes damage (from player attacks)
func take_damage(_amount: int = 1) -> void:
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
		# Add other drop types as needed
		_:
			return

	if drop:
		drop.position = global_position
		drop.position.y += 0.5  # Spawn slightly above ground
		parent.call_deferred("add_child", drop)
