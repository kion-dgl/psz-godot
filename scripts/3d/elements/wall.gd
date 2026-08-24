extends GameElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed

signal destroyed_wall

## Whether this wall can be destroyed by player attacks
@export var is_destructible: bool = true

## Hits required to break the wall. The original's breakable walls take a few
## strikes rather than shattering on the first touch.
const HITS_TO_DESTROY := 3

## Collision body for physical presence
var collision_body: StaticBody3D

## Hurtbox for receiving hits from the player's attack hitbox. Without it an
## attack never registers on the wall and the wall can never be broken.
var hurtbox: Hurtbox

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
	_setup_hurtbox()
	_setup_mirror_textures()


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "WallHurtbox"
	hurtbox.owner_node = self
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Match the wall's footprint, with enough height for ranged shots to land.
	var hb_size := Vector3(collision_size.x, maxf(collision_size.y, 2.0), collision_size.z)
	box.size = hb_size
	shape.shape = box
	shape.position.y = hb_size.y / 2
	hurtbox.add_child(shape)
	add_child(hurtbox)


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
				hurtbox.set_deferred("monitorable", false)


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
