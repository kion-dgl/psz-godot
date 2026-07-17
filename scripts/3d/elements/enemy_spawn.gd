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

## Animation source — rare variants that share animations with their base model.
## Maps model_id → source model_id whose GLB contains the animations.
const ANIM_SOURCE: Dictionary = {
	"armadillo_rare": "armadillo",
	"bat_blue": "bat",
	"circle_black": "circle",
	"frog_bomb": "frog",
	"frog_rare": "frog",
	"gorilla_female": "gorilla",
	"gorilla_rare": "gorilla",
	"lion_rare": "lion",
	"orangutan_rare": "orangutan",
	"quad_rare": "quad",
	"rabbit_rare": "rabbit",
	"rappy_blue": "rappy",
	"rappy_red": "rappy",
	"roc_rare": "roc",
	"seal_rare": "seal",
	"shrimp_rare": "shrimp",
	"snake_rare": "snake",
}

## Texture manifest — maps model_id → [texture filenames].
## Loaded once from JSON so we don't need DirAccess (fails on Android PCK).
static var _tex_manifest: Dictionary = {}
static var _tex_manifest_loaded: bool = false


func _init() -> void:
	interactable = false
	element_state = "alive"
	collision_size = Vector3(1.5, 2.0, 1.5)


var _reticle: Sprite3D
var is_alive: bool = true


func _ready() -> void:
	add_to_group("enemies")

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

	collision_body = _build_static_collision("EnemyCollision")
	_setup_hurtbox()
	_apply_enemy_texture()
	_setup_reticle()


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

	# Rare variants without embedded animations — load from base model
	if ANIM_SOURCE.has(_model_id):
		var has_anims := _anim_player != null and _anim_player.get_animation_list().size() > 0
		if not has_anims:
			_load_anims_from_source(ANIM_SOURCE[_model_id])

	if _anim_player:
		var idle_name := _find_animation("wat")
		if idle_name.is_empty():
			idle_name = _find_animation("stt")
		if not idle_name.is_empty():
			var anim := _anim_player.get_animation(idle_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			_anim_player.play(idle_name)


func _load_anims_from_source(source_id: String) -> void:
	var src_path := "res://assets/enemies/%s/%s.glb" % [source_id, source_id]
	if not ResourceLoader.exists(src_path):
		push_warning("[EnemySpawn] Animation source not found: %s" % src_path)
		return
	var src_packed := load(src_path) as PackedScene
	if not src_packed:
		return
	var src_scene := src_packed.instantiate()
	var src_anim: AnimationPlayer = _find_anim_player(src_scene)
	if not src_anim:
		src_scene.queue_free()
		return

	# Find skeleton in our model for track remapping
	var skel: Skeleton3D = _find_typed(model, "Skeleton3D") as Skeleton3D
	if not skel:
		src_scene.queue_free()
		return

	# Create AnimationPlayer on the model scene root (not inside the mesh node)
	# so track paths like "m_103/Skeleton3D:bone" resolve correctly
	if not _anim_player:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "SourceAnimPlayer"
		model.add_child(_anim_player)

	# Copy animations, remapping skeleton paths to our model
	var src_skel: Skeleton3D = _find_typed(src_scene, "Skeleton3D") as Skeleton3D
	var src_skel_parent_name: String = src_skel.get_parent().name if src_skel else ""
	var dst_skel_parent_name: String = skel.get_parent().name

	var lib := AnimationLibrary.new()
	for anim_name in src_anim.get_animation_list():
		var anim := src_anim.get_animation(anim_name).duplicate() as Animation
		for i in range(anim.get_track_count()):
			var track_path := String(anim.track_get_path(i))
			if not src_skel_parent_name.is_empty() and track_path.begins_with(src_skel_parent_name + "/"):
				track_path = dst_skel_parent_name + track_path.substr(src_skel_parent_name.length())
				anim.track_set_path(i, NodePath(track_path))
		lib.add_animation(anim_name, anim)

	_anim_player.add_animation_library("", lib)
	src_scene.queue_free()
	print("[EnemySpawn] Loaded %d animations from %s for %s" % [lib.get_animation_list().size(), source_id, _model_id])


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
	MeshUtils.apply_texture(model, texture)


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
func take_damage(amount: int = 1, _knockback: Vector3 = Vector3.ZERO, accuracy: int = 100) -> void:
	if element_state == "dead":
		return

	# Apply damage formula with defense/evasion
	var enemy_data_ref = EnemyRegistry.get_enemy(enemy_id)
	var defense: int = int(enemy_data_ref.defense_base) if enemy_data_ref else 5
	var evasion: int = int(enemy_data_ref.evasion_base) if enemy_data_ref else 30
	var result: Dictionary = CombatManager.apply_damage_to_enemy(amount, defense, evasion, accuracy)

	if not result.get("hit", true):
		_spawn_damage_number("MISS", Color(0.7, 0.7, 0.7))
		return

	var final_damage: int = int(result.get("damage", amount))
	var is_crit: bool = result.get("is_critical", false)
	hp -= final_damage
	var dmg_color := Color(1.0, 1.0, 0.2) if is_crit else Color.WHITE
	var dmg_text := str(final_damage) + ("!" if is_crit else "")
	_spawn_damage_number(dmg_text, dmg_color)

	if hp <= 0:
		hp = 0
		_die()


func _die() -> void:
	is_alive = false
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
	var hit := node.find_children("*", "AnimationPlayer", true, false)
	return hit[0] if not hit.is_empty() else null


func _find_typed(root: Node, type_name: String) -> Node:
	var hit := root.find_children("*", type_name, true, false)
	return hit[0] if not hit.is_empty() else null


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


func _setup_reticle() -> void:
	_reticle = TargetReticle.build(collision_size.y + 0.5)
	add_child(_reticle)


func show_reticle() -> void:
	if _reticle:
		_reticle.visible = true


func hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false


func _spawn_damage_number(text: String, color: Color = Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0)
	label.position = Vector3(randf_range(-0.3, 0.3), 2.0 + randf_range(0, 0.3), 0)
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
