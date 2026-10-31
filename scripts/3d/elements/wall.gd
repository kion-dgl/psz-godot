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
	_fit_collision_to_model()
	collision_body = _build_static_collision("WallCollision")
	_setup_hurtbox("WallHurtbox")
	_setup_mirror_textures()
	# Centre of the wall's face, not above it — a wall is targeted like an
	# enemy standing in the doorway, not like loot on the ground.
	if is_destructible:
		_setup_reticle(collision_size.y * 0.5)


## Size the collision (and with it the hurtbox and cone bounds) from the wall
## model the area actually loaded — the same fix boxes got: the per-field
## walls are not all 6 x 1.85 x 0.52, and a fixed box leaves taller or wider
## walls partly uncollidable, unhittable and untargeable. Falls back to the
## authored default when there is nothing to measure.
func _fit_collision_to_model() -> void:
	if not model:
		return
	var extents := AreaObjects.model_extents(model)
	if extents.size.x <= 0.0 or extents.size.y <= 0.0 or extents.size.z <= 0.0:
		return
	collision_size = extents.size
	target_radius = maxf(extents.size.x, extents.size.z) * 0.5
	target_height = extents.size.y


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
	_spawn_debris()
	print("[Wall] Destroyed")


## The original spawns the per-field break-apart debris (oNN_wallptcl — a
## different mesh and texture in every field; area_objects.gd). The model is
## the original's own; the scatter motion is ours.
func _spawn_debris() -> void:
	var parent := get_parent()
	if not parent:
		return
	var path := "res://assets/objects/" + AreaObjects.current_model_path("wallptcl")
	if not ResourceLoader.exists(path):
		return
	var debris := Node3D.new()
	var scene: PackedScene = load(path)
	if scene:
		debris.add_child(scene.instantiate())
	debris.position = position
	debris.rotation = rotation
	parent.call_deferred("add_child", debris)
	var tween := debris.create_tween()
	tween.tween_interval(0.9)
	tween.tween_callback(debris.queue_free)
