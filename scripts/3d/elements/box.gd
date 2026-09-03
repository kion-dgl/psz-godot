extends DestructibleElement
class_name Box
## Destructible container that can drop items when destroyed.
## States: intact, destroyed
## Hurtbox + intact/destroyed state live in DestructibleElement.

signal destroyed_box

## Whether this box is a rare variant (uses the shared o0c_recont instead of
## the active area's oNN_cont)
@export var is_rare: bool = false

## Drop type when destroyed (meseta, weapon, armor, item, none)
@export var drop_type: String = "none"

## Drop amount for meseta or item ID for items
@export var drop_value: String = ""


var is_alive: bool = true


func _init() -> void:
	interactable = false  # Destroyed by attacking, not interacting
	element_state = "intact"
	collision_size = Vector3(1, 1, 1)


func _ready() -> void:
	add_to_group("enemies")

	if is_rare:
		# o0c_recont is a shared object — byte-identical in every field, so it
		# keeps one path. Only the plain container is re-skinned per area.
		model_path = "valley/o0c_recont.glb"
	else:
		model_path = AreaObjects.current_model_path("cont")

	super._ready()
	_fit_collision_to_model()
	collision_body = _build_static_collision("BoxCollision")
	_setup_hurtbox("BoxHurtbox")
	_setup_mirror_textures(Vector2(0, 1) if is_rare else Vector2.ZERO)
	_setup_reticle(collision_size.y + 0.5)


## Size the collision box from the container the area actually loaded.
##
## The per-field containers are not all the same size — most are 1x1x1 but
## Paru's o05_cont is 1 x 1.588 x 1, half again as tall — so the fixed 1x1x1
## box left the top third of that container without collision or hurtbox.
## Every container's mesh sits on y=0, so the shape's half-height offset still
## lands correctly. Falls back to the default when the model is missing or has
## no mesh to measure.
func _fit_collision_to_model() -> void:
	if not model:
		return
	var extents := AreaObjects.model_extents(model)
	if extents.size.x <= 0.0 or extents.size.y <= 0.0 or extents.size.z <= 0.0:
		return
	collision_size = extents.size


## Called when the box takes damage (from player attacks via Hurtbox)
func take_damage(_amount: int = 1, _knockback: Vector3 = Vector3.ZERO, _accuracy: int = 100) -> void:
	if element_state == "destroyed":
		return

	destroy()


## Destroy the box and spawn drops
func destroy() -> void:
	if element_state == "destroyed":
		return

	is_alive = false
	remove_from_group("enemies")
	set_state("destroyed")
	SfxManager.play_at("res://assets/sfx/common/common_160.wav", global_position)
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
