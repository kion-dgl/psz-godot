extends DestructibleElement
class_name Wall
## Destructible wall that can be attacked to destroy.
## States: intact, destroyed
## Hurtbox + intact/destroyed state live in DestructibleElement.

signal destroyed_wall

## Whether this wall can be destroyed by player attacks
@export var is_destructible: bool = true

## Alive flag for the "enemies" group ride-along — the same contract Box uses:
## the cone targeting, reticles, and melee hit resolution all scan that group
## and skip anything not "alive", so a destructible element has to speak both.
var is_alive: bool = true

## Cone bounds override. A wall is 6 units wide, but ConeTargeting defaults a
## no-enemy_data target to a 0.5 radius sphere at its centre — from beside a
## wall that centre is 3 units off-axis and outside every weapon's cone, so a
## wall the player is standing against could never be targeted or hit. These
## widen the cone test to the wall's real face.
var target_radius := 3.0
var target_height := 1.85

## Hits required to break the wall. The original's breakable walls take a few
## strikes rather than shattering on the first touch.
const HITS_TO_DESTROY := 3

var _hits_taken: int = 0


func _init() -> void:
	element_state = "intact"
	collision_size = Vector3(6, 1.85, 0.52)


func _ready() -> void:
	if is_destructible:
		add_to_group("enemies")
	# Per-area wall art. The Eternal Tower ships no oNN_wall, so AreaObjects
	# falls back to the Valley model there rather than loading nothing.
	model_path = AreaObjects.current_model_path("wall")
	super._ready()
	collision_body = _build_static_collision("WallCollision")
	_setup_hurtbox("WallHurtbox")
	_setup_mirror_textures()
	# Centre of the wall's face, not above it — a wall is targeted like an
	# enemy standing in the doorway, not like loot on the ground.
	if is_destructible:
		_setup_reticle(collision_size.y * 0.5)


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

	is_alive = false
	remove_from_group("enemies")
	hide_reticle()
	set_state("destroyed")
	destroyed_wall.emit()
	print("[Wall] Destroyed")
