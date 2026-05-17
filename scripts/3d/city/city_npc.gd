extends GameElement
class_name CityNPC
## Interactive NPC for the 3D city hub. Loads a GLB model and opens
## a 2D shop/menu overlay on interaction.

## Animation sources to search for idle anims (tried in order).
## npc_idles_vrm.glb contains the same PSO anims as npc_idles.glb but
## with their tracks retargeted to the VRM J_Bip_* bone convention
## (built by web/scripts/bake-retarget-vrm.mjs). Clip names in that
## file are suffixed _vrm to avoid colliding with the PSZ versions —
## VRM NPCs request "pso_f_sh_stand_vrm" instead of "pso_f_sh_stand".
##
## Note the VRM library lives under assets/npcs/item_shop/, not
## assets/player/animations/, because the export preset's
## exclude_filter ships `assets/player/*` via the Arweave asset pack
## rather than bundling them into the APK. Our small VRM library
## ships in-tree with the item_shop NPC's other assets.
const NPC_ANIM_SOURCES := [
	"res://assets/player/animations/npc_idles.glb",
	"res://assets/npcs/item_shop/npc_idles_vrm.glb",
	"res://assets/player/animations/saver_m.glb",
	"res://assets/player/animations/saver_w.glb",
]

@export var npc_model_path: String = ""  # Full res:// path to GLB
@export var npc_display_name: String = "NPC"
@export var target_scene_path: String = ""
@export var npc_rotation_y: float = 0.0
@export var idle_anim: String = ""  # Animation name from npc_idles.glb
## Animation played once on player interaction (greeting / bow style),
## then the NPC returns to idle_anim. Looked up from NPC_ANIM_SOURCES
## the same way as idle_anim.
@export var interact_anim: String = ""
@export var hat_model_path: String = ""  # Optional GLB attached to head bone
@export var hat_bone_name: String = "090_Head"

var _prompt_label: Label3D
var _player_ref: Node3D  # Set by area controller after spawning
var _anim_player: AnimationPlayer


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
	if ResourceLoader.exists(tex_path):
		var texture := load(tex_path) as Texture2D
		if texture:
			_apply_npc_texture(model, texture)

	_setup_idle_anim()
	_attach_hat()


func _attach_hat() -> void:
	if hat_model_path.is_empty() or not model:
		return
	var skel: Skeleton3D = _find_typed(model, "Skeleton3D") as Skeleton3D
	if not skel or skel.find_bone(hat_bone_name) == -1:
		push_warning("[CityNPC] Hat bone '%s' not found on %s" % [hat_bone_name, npc_display_name])
		return
	var packed := load(hat_model_path) as PackedScene
	if not packed:
		push_warning("[CityNPC] Failed to load hat: " + hat_model_path)
		return
	var attach := BoneAttachment3D.new()
	attach.name = "HatAttach"
	attach.bone_name = hat_bone_name
	skel.add_child(attach)
	var hat := packed.instantiate()
	attach.add_child(hat)


func _setup_idle_anim() -> void:
	if idle_anim.is_empty() or not model:
		return

	# Find skeleton in the NPC model
	var skel: Skeleton3D = _find_typed(model, "Skeleton3D") as Skeleton3D
	if not skel:
		return

	# Search animation sources for the requested idle anim
	var source_anim: Animation = null
	for source_path in NPC_ANIM_SOURCES:
		if not ResourceLoader.exists(source_path):
			continue
		var anim_packed := load(source_path) as PackedScene
		if not anim_packed:
			continue
		var anim_scene := anim_packed.instantiate()
		var source_player: AnimationPlayer = _find_typed(anim_scene, "AnimationPlayer") as AnimationPlayer
		if source_player and source_player.has_animation(idle_anim):
			source_anim = source_player.get_animation(idle_anim).duplicate() as Animation
			anim_scene.queue_free()
			break
		anim_scene.queue_free()

	if not source_anim:
		return

	# Create AnimationPlayer on the skeleton's parent
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "NPCAnimPlayer"
	skel.get_parent().add_child(_anim_player)

	# Remap animation tracks to this NPC's skeleton name
	source_anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(source_anim.get_track_count()):
		var track_path := String(source_anim.track_get_path(i))
		if "Skeleton3D" in track_path:
			var skel_idx := track_path.find("Skeleton3D")
			var prop_part := track_path.substr(skel_idx + 10)
			source_anim.track_set_path(i, NodePath(skel.name + prop_part))

	var lib := AnimationLibrary.new()
	lib.add_animation(idle_anim, source_anim)
	_anim_player.add_animation_library("", lib)
	_anim_player.play(idle_anim)

	print("[CityNPC] Playing idle: %s on %s" % [idle_anim, npc_display_name])


## Play a one-shot animation, then return to the idle anim.
func play_oneshot(anim_name: String) -> void:
	if not model or not _anim_player:
		return
	# Load the animation if not already in the library
	if not _anim_player.has_animation(anim_name):
		var anim := _load_anim_from_sources(anim_name)
		if not anim:
			push_warning("[CityNPC] One-shot animation '%s' not found" % anim_name)
			return
		var lib: AnimationLibrary = _anim_player.get_animation_library("")
		lib.add_animation(anim_name, anim)
	_anim_player.play(anim_name)
	_anim_player.animation_finished.connect(func(_finished_name: StringName) -> void:
		if not idle_anim.is_empty() and _anim_player.has_animation(idle_anim):
			_anim_player.play(idle_anim)
	, CONNECT_ONE_SHOT)
	print("[CityNPC] One-shot: %s on %s" % [anim_name, npc_display_name])


func _load_anim_from_sources(anim_name: String) -> Animation:
	var skel: Skeleton3D = _find_typed(model, "Skeleton3D") as Skeleton3D
	if not skel:
		return null
	for source_path in NPC_ANIM_SOURCES:
		if not ResourceLoader.exists(source_path):
			continue
		var anim_packed := load(source_path) as PackedScene
		if not anim_packed:
			continue
		var anim_scene := anim_packed.instantiate()
		var source_player: AnimationPlayer = _find_typed(anim_scene, "AnimationPlayer") as AnimationPlayer
		if source_player and source_player.has_animation(anim_name):
			var anim := source_player.get_animation(anim_name).duplicate() as Animation
			anim.loop_mode = Animation.LOOP_NONE
			for i in range(anim.get_track_count()):
				var track_path := String(anim.track_get_path(i))
				if "Skeleton3D" in track_path:
					var skel_idx := track_path.find("Skeleton3D")
					var prop_part := track_path.substr(skel_idx + 10)
					anim.track_set_path(i, NodePath(skel.name + prop_part))
			anim_scene.queue_free()
			return anim
		anim_scene.queue_free()
	return null


func _find_typed(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed(child, type_name)
		if found:
			return found
	return null


func _ready() -> void:
	super._ready()
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = npc_display_name
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
	SfxManager.play("res://assets/sfx/ui/menu_open.wav")
	# Play the interaction-response animation if configured. Fires
	# concurrently with the scene push so the greet/bow plays in the
	# background as the shop UI transitions in — the player sees it on
	# the way out, and when they exit the shop the NPC has already
	# returned to idle.
	if not interact_anim.is_empty():
		play_oneshot(interact_anim)
	# Save position so we return to same spot
	var area_controller := get_parent()
	if area_controller and area_controller.has_method("_save_player_state"):
		area_controller._save_player_state()
	SceneManager.push_scene(target_scene_path, {
		"npc_model_path": npc_model_path,
		"npc_display_name": npc_display_name,
	})


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
