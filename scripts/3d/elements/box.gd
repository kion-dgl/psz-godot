extends GameElement
class_name Box
## Destructible container that can drop items when destroyed.
## States: intact, destroyed

signal destroyed_box

## Whether this box is a rare variant (uses the shared o0c_recont instead of
## the active area's oNN_cont)
@export var is_rare: bool = false

## Drop type when destroyed (meseta, weapon, armor, item, none)
@export var drop_type: String = "none"

## Drop amount for meseta or item ID for items
@export var drop_value: String = ""

## Collision body for physical presence
var collision_body: StaticBody3D

## Hurtbox for receiving hits from player attack hitbox
var hurtbox: Hurtbox


var _reticle: Sprite3D
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
	_setup_hurtbox()
	_setup_mirror_textures(Vector2(0, 1) if is_rare else Vector2.ZERO)
	_setup_reticle()


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


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "BoxHurtbox"
	hurtbox.owner_node = self
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Extend hurtbox height so ranged projectiles can hit the box
	var hurtbox_size := Vector3(collision_size.x, maxf(collision_size.y, 2.0), collision_size.z)
	box.size = hurtbox_size
	shape.shape = box
	shape.position.y = hurtbox_size.y / 2
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


func _setup_reticle() -> void:
	_reticle = TargetReticle.build(collision_size.y + 0.5)
	add_child(_reticle)


func show_reticle() -> void:
	if _reticle:
		_reticle.visible = true


func hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false


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
