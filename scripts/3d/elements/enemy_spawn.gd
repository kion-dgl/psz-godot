extends GameElement
class_name EnemySpawn
## Static enemy spawn that can be damaged and defeated.
## States: alive, dead

signal defeated

## Enemy type ID (EnemyRegistry key like "ghowl", or model_id like "lizard")
@export var enemy_id: String = "ghowl"

## Hit points (defaults to 1 for one-hit-kill static spawns)
@export var hp: int = 1
@export var max_hp: int = 1

## Whether to load HP from EnemyRegistry (false for quest static spawns)
@export var use_registry_hp: bool = false

## Collision body for physical presence
var collision_body: StaticBody3D

## Hurtbox for receiving hits from player attack hitbox
var hurtbox: Hurtbox

## Resolved model folder name (set in _ready)
var _model_id: String = ""

## Animation
var _anim_player: AnimationPlayer

## Texture manifest — maps model_id → [texture filenames].
## Loaded once from JSON so we don't need DirAccess (fails on Android PCK).
static var _tex_manifest: Dictionary = {}
static var _tex_manifest_loaded: bool = false


func _init() -> void:
	interactable = false
	element_state = "alive"
	collision_size = Vector3(1.5, 2.0, 1.5)


func _ready() -> void:
	# Resolve enemy data — enemy_id can be a registry key or a model_id
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	if enemy_data:
		_model_id = str(enemy_data.model_id) if not str(enemy_data.model_id).is_empty() else enemy_id
	else:
		# Try treating enemy_id as a model_id (e.g. "lizard" instead of "ghowl")
		_model_id = enemy_id

	if use_registry_hp and enemy_data:
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
	# Construct path directly — DirAccess enumeration fails in Android PCK exports.
	var glb_path := "res://assets/enemies/%s/%s.glb" % [_model_id, _model_id]
	if not ResourceLoader.exists(glb_path):
		push_warning("[EnemySpawn] Model not found: %s" % glb_path)
		return

	var packed := load(glb_path) as PackedScene
	if not packed:
		push_warning("[EnemySpawn] Failed to load model: %s" % glb_path)
		return

	model = packed.instantiate()
	add_child(model)

	# Find and play idle animation
	_anim_player = _find_anim_player(model)
	if _anim_player:
		var idle_name := _find_animation("wat")
		if idle_name.is_empty():
			idle_name = _find_animation("stt")
		if not idle_name.is_empty():
			var anim := _anim_player.get_animation(idle_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			_anim_player.play(idle_name)


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


static func _load_tex_manifest() -> void:
	if _tex_manifest_loaded:
		return
	_tex_manifest_loaded = true
	var fa := FileAccess.open("res://data/enemy_textures.json", FileAccess.READ)
	if fa:
		var json := JSON.new()
		if json.parse(fa.get_as_text()) == OK and json.data is Dictionary:
			_tex_manifest = json.data
		fa.close()


func _apply_enemy_texture() -> void:
	if not model:
		return
	_load_tex_manifest()
	var tex_dir := "res://assets/enemies/" + _model_id + "/"
	if _tex_manifest.has(_model_id):
		var tex_files: Array = _tex_manifest[_model_id]
		if tex_files.size() > 0:
			var tex_path := tex_dir + str(tex_files[0])
			var tex := load(tex_path) as Texture2D
			if tex:
				_apply_texture(tex)
				return
	# Fallback: try DirAccess enumeration (works in editor for new models not yet in manifest)
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
				hurtbox.set_deferred("monitorable", true)
		"dead":
			set_element_visible(false)
			if collision_body:
				collision_body.collision_layer = 0
			if hurtbox:
				hurtbox.set_deferred("monitorable", false)


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
	# Play death animation before hiding
	var death_name := _find_animation("ded")
	if _anim_player and not death_name.is_empty():
		_anim_player.play(death_name)
		# Disable hurtbox immediately so enemy can't be hit again
		if hurtbox:
			hurtbox.set_deferred("monitorable", false)
		if collision_body:
			collision_body.collision_layer = 0
		await _anim_player.animation_finished

	set_state("dead")
	defeated.emit()
	print("[EnemySpawn] %s defeated!" % enemy_id)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null


func _find_animation(short_name: String) -> String:
	if not _anim_player:
		return ""
	# Direct match
	if _anim_player.has_animation(short_name):
		return short_name
	# Search for name ending with _<short_name>
	var anim_list: PackedStringArray = _anim_player.get_animation_list()
	for i in range(anim_list.size()):
		var anim_name: String = anim_list[i]
		if anim_name.ends_with("_" + short_name):
			return anim_name
	# Search in libraries
	var lib_list: Array[StringName] = _anim_player.get_animation_library_list()
	for j in range(lib_list.size()):
		var lib_name: StringName = lib_list[j]
		var lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		var lib_anim_list: PackedStringArray = lib.get_animation_list()
		for k in range(lib_anim_list.size()):
			var anim_name: String = lib_anim_list[k]
			if anim_name.ends_with("_" + short_name):
				var full: String = str(lib_name) + "/" + anim_name if lib_name else anim_name
				return full
	return ""
