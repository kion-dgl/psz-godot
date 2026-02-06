extends GameElement
class_name Gate
## Blocks passage between stages. Opens when all enemies are defeated.
## States: closed, open

## The laser/beam mesh that gets hidden when open
const LASER_MESH_NAME := "o0c_gate_3"

## Collision body for blocking when closed
var collision_body: StaticBody3D


func _init() -> void:
	model_path = "valley/o0c_gate.glb"
	element_state = "closed"
	collision_size = Vector3(2, 3, 0.5)


func _ready() -> void:
	super._ready()
	_setup_gate_collision()


func _setup_gate_collision() -> void:
	# Create static body for physical blocking
	collision_body = StaticBody3D.new()
	collision_body.name = "GateCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.3)
	shape.shape = box
	shape.position.y = 1.5
	collision_body.add_child(shape)

	add_child(collision_body)


func _apply_state() -> void:
	match element_state:
		"closed":
			set_mesh_visible(LASER_MESH_NAME, true)
			if collision_body:
				collision_body.collision_layer = 1  # Block player
		"open":
			set_mesh_visible(LASER_MESH_NAME, false)
			if collision_body:
				collision_body.collision_layer = 0  # Allow passage


## Open the gate
func open() -> void:
	set_state("open")


## Close the gate
func close() -> void:
	set_state("closed")


## Toggle gate state
func toggle() -> void:
	if element_state == "closed":
		open()
	else:
		close()
