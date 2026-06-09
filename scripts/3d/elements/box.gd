extends GameElement
class_name Box
## Destructible container that can drop items when destroyed.
## States: intact, destroyed

signal destroyed_box

const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat.gdshader")

## Whether this box is a rare variant (uses o0c_recont instead of o01_cont)
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
		model_path = "valley/o0c_recont.glb"
	else:
		model_path = "valley/o01_cont.glb"

	super._ready()
	collision_body = _build_static_collision("BoxCollision")
	_setup_hurtbox()
	_setup_textures()
	_setup_reticle()


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


func _setup_textures() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture:
				var smat := ShaderMaterial.new()
				smat.shader = MIRROR_SHADER
				smat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				smat.set_shader_parameter("uv_scale", Vector2(2, 2))
				smat.set_shader_parameter("mirror_x", true)
				smat.set_shader_parameter("mirror_y", true)
				if is_rare:
					smat.set_shader_parameter("uv_offset", Vector2(0, 1))
				mesh.set_surface_override_material(surface, smat)
	)


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
	_reticle = Sprite3D.new()
	_reticle.name = "TargetReticle"
	_reticle.pixel_size = 0.008
	_reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reticle.no_depth_test = true
	_reticle.modulate = Color(1.0, 0.15, 0.15, 0.9)
	_reticle.visible = false

	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: int = size / 2
	for y in range(size):
		var progress: float = float(y) / float(size - 1)
		var half_width: int = int(float(half) * (1.0 - progress))
		for x in range(half - half_width, half + half_width + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, Color.WHITE)
	_reticle.texture = ImageTexture.create_from_image(img)
	_reticle.position = Vector3(0, collision_size.y + 0.5, 0)
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
