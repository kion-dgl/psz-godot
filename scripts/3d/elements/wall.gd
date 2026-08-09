extends GameElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed

signal destroyed_wall

## Whether this wall can be destroyed by player attacks
@export var is_destructible: bool = true

## Collision body for physical presence
var collision_body: StaticBody3D


func _init() -> void:
	element_state = "intact"
	collision_size = Vector3(6, 1.85, 0.52)


func _ready() -> void:
	# Per-area wall art. The Eternal Tower ships no oNN_wall, so AreaObjects
	# falls back to the Valley model there rather than loading nothing.
	model_path = AreaObjects.current_model_path("wall")
	super._ready()
	collision_body = _build_static_collision("WallCollision")
	_setup_mirror_textures()


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
