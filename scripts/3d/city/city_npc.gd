extends GameElement
class_name CityNPC
## Interactive NPC for the 3D city hub. Loads a GLB model and opens
## a 2D shop/menu overlay on interaction.

@export var npc_model_path: String = ""  # Full res:// path to GLB
@export var npc_display_name: String = "NPC"
@export var target_scene_path: String = ""
@export var npc_rotation_y: float = 0.0

var _prompt_label: Label3D
var _player_ref: Node3D  # Set by area controller after spawning


func _init() -> void:
	interactable = true
	collision_size = Vector3(2, 2, 2)


func _load_model() -> void:
	if npc_model_path.is_empty():
		return

	var packed := load(npc_model_path) as PackedScene
	if not packed:
		push_warning("[CityNPC] Failed to load model: " + npc_model_path)
		return

	model = packed.instantiate()
	add_child(model)
	model.rotation.y = npc_rotation_y

	# Apply texture if PNG exists alongside GLB
	var tex_path := npc_model_path.replace(".glb", ".png")
	var texture := load(tex_path) as Texture2D
	if texture:
		_apply_npc_texture(model, texture)


func _ready() -> void:
	super._ready()
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] %s" % npc_display_name
	_prompt_label.font_size = 32
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 2.5, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(1, 0.8, 0)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _process(delta: float) -> void:
	super._process(delta)
	# Show prompt when player's nearest interactable is this NPC
	if _player_ref and is_instance_valid(_player_ref):
		_prompt_label.visible = _player_ref.get_nearest_interactable() == self
	else:
		_prompt_label.visible = false


func set_player(player: Node3D) -> void:
	_player_ref = player


func _on_interact(_player: Node3D) -> void:
	if target_scene_path.is_empty():
		return
	# Save position so we return to same spot
	var area_controller := get_parent()
	if area_controller and area_controller.has_method("_save_player_state"):
		area_controller._save_player_state()
	SceneManager.push_scene(target_scene_path)


func _apply_npc_texture(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_texture = texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh_inst.set_surface_override_material(i, new_mat)
			elif mat == null:
				var new_mat := StandardMaterial3D.new()
				new_mat.albedo_texture = texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_apply_npc_texture(child, texture)
