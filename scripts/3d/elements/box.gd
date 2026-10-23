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

## Cone-targeting bounds, fitted from the loaded container in _ready (walls
## carry the same pair). The cone reads these for no-enemy_data targets.
var target_radius := 0.5
var target_height := 0.5


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
	# Cone bounds ON the container, aimed at its vertical centre — the same
	# fix walls got. The cone's default for a no-enemy_data target is a 0.5
	# sphere at the ORIGIN (the feet), which put the lock-on point on the
	# floor beside the box and left close-range swings missing it entirely.
	target_radius = maxf(collision_size.x, collision_size.z) * 0.5
	# FULL height: the cone places its aim sphere at position + height/2,
	# matching enemies' collision_height semantics — so this lands the aim
	# point at the container's true centre, not on the floor beside it.
	target_height = collision_size.y
	collision_body = _build_static_collision("BoxCollision")
	_setup_hurtbox("BoxHurtbox")
	_setup_mirror_textures(Vector2(0, 1) if is_rare else Vector2.ZERO)
	# Reticle at the centre too, not floating above the lid.
	_setup_reticle(target_height)


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
	# Break visual. The original's container-break effect id is not yet
	# decoded (no per-container entry in the effect factory tables), so this
	# is an engine-native fragment burst sized from the container; swap for
	# the decoded effect when psz-re pins it.
	var parent := get_parent()
	if parent:
		parent.call_deferred("add_child", _make_burst())

	# Spawn drop if configured
	if drop_type != "none":
		_spawn_drop()

	print("[Box] Destroyed")


## Shrapnel: the container blows apart into tumbling shards thrown radially
## with an upward bias, falling under gravity. The original's container-break
## effect id is still undecoded (no per-container entry in the effect factory
## tables), so these are engine-native shards sized from the container — the
## motion profile is the part playtesting asked for: outward, violent, brief.
func _make_burst() -> Node3D:
	var host := Node3D.new()
	host.position = position + Vector3.UP * (collision_size.y * 0.5)
	host.rotation = rotation
	var shard_scale: float = clampf(collision_size.length() * 0.35, 0.7, 1.6)

	var shards := CPUParticles3D.new()
	shards.one_shot = true
	shards.amount = 36
	shards.lifetime = 0.8
	shards.explosiveness = 1.0
	shards.direction = Vector3.UP
	shards.spread = 85.0
	shards.initial_velocity_min = 3.0
	shards.initial_velocity_max = 7.0
	shards.gravity = Vector3(0, -14, 0)
	shards.scale_amount_min = 0.45
	shards.scale_amount_max = 1.35
	shards.angular_velocity_min = -12.0
	shards.angular_velocity_max = 12.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.18, 0.1) * shard_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.55, 0.34)
	mat.roughness = 0.9
	mesh.material = mat
	shards.draw_mesh = mesh
	host.add_child(shards)
	shards.finished.connect(host.queue_free)
	shards.restart()

	# A short hot flash under the shards sells the detonation beat.
	var flash := CPUParticles3D.new()
	flash.one_shot = true
	flash.amount = 6
	flash.lifetime = 0.18
	flash.explosiveness = 1.0
	flash.direction = Vector3.UP
	flash.spread = 180.0
	flash.initial_velocity_min = 0.4
	flash.initial_velocity_max = 1.2
	flash.scale_amount_min = 1.2
	flash.scale_amount_max = 2.0
	var fmesh := SphereMesh.new()
	fmesh.radius = 0.16 * shard_scale
	fmesh.height = 0.32 * shard_scale
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.78, 0.4, 0.85)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.6, 0.2)
	fmat.emission_energy_multiplier = 2.2
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmesh.material = fmat
	flash.draw_mesh = fmesh
	host.add_child(flash)
	return host


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
