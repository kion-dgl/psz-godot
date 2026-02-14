extends GameElement
class_name EnemySpawn
## Static enemy spawn that can be damaged and defeated.
## States: alive, dead

signal defeated

## Enemy type ID (matches EnemyRegistry keys, e.g. "lizard", "booma")
@export var enemy_id: String = "lizard"

## Hit points
@export var hp: int = 30
@export var max_hp: int = 30

## Collision body for physical presence
var collision_body: StaticBody3D

## Hurtbox for receiving hits from player attack hitbox
var hurtbox: Hurtbox


func _init() -> void:
	interactable = false
	element_state = "alive"
	collision_size = Vector3(1.5, 2.0, 1.5)


func _ready() -> void:
	# Look up enemy data for HP stats
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	if enemy_data:
		hp = int(enemy_data.hp_base)
		max_hp = hp

	# Skip GameElement._load_model() — we load from assets/enemies/ directly
	_load_enemy_model()
	_setup_collision()
	_apply_state()

	_setup_enemy_collision()
	_setup_hurtbox()
	_apply_enemy_texture()


func _load_enemy_model() -> void:
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	var model_id: String = enemy_id
	if enemy_data and not str(enemy_data.model_id).is_empty():
		model_id = str(enemy_data.model_id)

	var full_path := "res://assets/enemies/%s/%s.glb" % [model_id, model_id]
	if not ResourceLoader.exists(full_path):
		push_warning("[EnemySpawn] Model not found: %s" % full_path)
		return

	var packed := load(full_path) as PackedScene
	if not packed:
		push_warning("[EnemySpawn] Failed to load model: %s" % full_path)
		return

	model = packed.instantiate()
	add_child(model)


func _setup_enemy_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "EnemyCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	collision_body.add_child(shape)

	add_child(collision_body)


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "EnemyHurtbox"
	hurtbox.owner_node = self

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	hurtbox.add_child(shape)

	add_child(hurtbox)


func _apply_enemy_texture() -> void:
	if not model:
		return
	# Enemy GLBs have their texture alongside; load and apply it
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	var model_id: String = enemy_id
	if enemy_data:
		model_id = str(enemy_data.model_id) if not str(enemy_data.model_id).is_empty() else enemy_id
	var tex_dir := "res://assets/enemies/" + model_id + "/"
	# Find first PNG that isn't the GLB
	if DirAccess.dir_exists_absolute(tex_dir):
		var dir := DirAccess.open(tex_dir)
		if dir:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname.ends_with(".png") and not fname.ends_with(".import"):
					var tex := load(tex_dir + fname) as Texture2D
					if tex:
						_apply_texture(tex)
						break
				fname = dir.get_next()
			dir.list_dir_end()


func _apply_texture(texture: Texture2D) -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_texture = texture
			dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh.set_surface_override_material(surface, dup)
	)


func _apply_state() -> void:
	match element_state:
		"alive":
			set_element_visible(true)
			if collision_body:
				collision_body.collision_layer = 1
			if hurtbox:
				hurtbox.monitorable = true
		"dead":
			set_element_visible(false)
			if collision_body:
				collision_body.collision_layer = 0
			if hurtbox:
				hurtbox.monitorable = false


## Called when hit by player attack via Hurtbox
func take_damage(amount: int = 1, _knockback: Vector3 = Vector3.ZERO) -> void:
	if element_state == "dead":
		return

	hp -= amount
	print("[EnemySpawn] %s took %d damage, hp=%d/%d" % [enemy_id, amount, hp, max_hp])

	if hp <= 0:
		hp = 0
		_die()


func _die() -> void:
	set_state("dead")
	defeated.emit()
	print("[EnemySpawn] %s defeated!" % enemy_id)
