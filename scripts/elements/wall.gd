extends GameElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed

signal destroyed_wall

## Collision body for physical presence
var collision_body: StaticBody3D


func _init() -> void:
	element_state = "intact"
	model_path = "valley/o01_wall.glb"
	collision_size = Vector3(2, 2, 0.5)


func _ready() -> void:
	super._ready()
	_setup_wall_collision()


func _setup_wall_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "WallCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	collision_body.add_child(shape)

	add_child(collision_body)


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
