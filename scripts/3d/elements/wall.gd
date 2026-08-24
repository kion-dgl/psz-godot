extends DestructibleElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed
## Hurtbox + intact/destroyed state live in DestructibleElement.

signal destroyed_wall

## Whether this wall can be destroyed by player attacks
@export var is_destructible: bool = true

## Hits required to break the wall. The original's breakable walls take a few
## strikes rather than shattering on the first touch.
const HITS_TO_DESTROY := 3

var _hits_taken: int = 0


func _init() -> void:
	element_state = "intact"
	collision_size = Vector3(6, 1.85, 0.52)


func _ready() -> void:
	# Per-area wall art. The Eternal Tower ships no oNN_wall, so AreaObjects
	# falls back to the Valley model there rather than loading nothing.
	model_path = AreaObjects.current_model_path("wall")
	super._ready()
	collision_body = _build_static_collision("WallCollision")
	_setup_hurtbox("WallHurtbox")
	_setup_mirror_textures()


## Called when the wall takes damage (from player attacks via the Hurtbox).
## Signature matches Box.take_damage so the shared hitbox→hurtbox path drives it.
func take_damage(_amount: int = 1, _knockback: Vector3 = Vector3.ZERO, _accuracy: int = 100) -> void:
	if not is_destructible:
		return
	if element_state == "destroyed":
		return

	_hits_taken += 1
	if _hits_taken >= HITS_TO_DESTROY:
		destroy()


## Destroy the wall
func destroy() -> void:
	if element_state == "destroyed":
		return

	set_state("destroyed")
	destroyed_wall.emit()
	print("[Wall] Destroyed")
