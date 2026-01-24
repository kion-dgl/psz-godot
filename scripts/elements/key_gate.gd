extends GameElement
class_name KeyGate
## Gate that requires a specific key to open.
## States: locked, unlocked

## Key ID required to unlock this gate
@export var required_key_id: String = "default"

## The laser/beam mesh that gets hidden when unlocked
const LASER_MESH_NAME := "o0c_gatet_3"

## Collision body for blocking when locked
var collision_body: StaticBody3D


func _init() -> void:
	model_path = "valley/o0c_gatet.glb"
	interactable = true
	element_state = "locked"
	collision_size = Vector3(2, 3, 0.5)


func _ready() -> void:
	super._ready()
	_setup_gate_collision()


func _setup_gate_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "KeyGateCollision"
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
		"locked":
			set_mesh_visible(LASER_MESH_NAME, true)
			if collision_body:
				collision_body.collision_layer = 1
		"unlocked":
			set_mesh_visible(LASER_MESH_NAME, false)
			if collision_body:
				collision_body.collision_layer = 0


func _on_interact(player: Node3D) -> void:
	if element_state == "unlocked":
		return

	# Check if player has the required key
	# TODO: Check GameState for key
	# if GameState.has_key(required_key_id):
	#     unlock()
	# else:
	#     print("[KeyGate] Requires key: ", required_key_id)

	# For now, just unlock for testing
	unlock()


## Unlock the gate
func unlock() -> void:
	set_state("unlocked")
	print("[KeyGate] Unlocked with key: ", required_key_id)


## Lock the gate
func lock() -> void:
	set_state("locked")
