extends GameElement
class_name FieldNpc
## NPC character that appears in the field with a GLB model and dialog.
## Player can press E to talk. Dialog pages cycle on repeated interact.

signal dialog_started
signal dialog_finished

@export var npc_id: String = ""
@export var npc_name: String = ""
@export var dialog: Array = []  # Array of {speaker: String, text: String}
@export var npc_animation: String = ""  # e.g. "~dam_d_lp" — tilde prefix resolved to gender

func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 2.0, 2.0)
	element_state = "idle"


func _ready() -> void:
	_load_npc_model()
	_setup_collision()
	_apply_state()
	if not npc_animation.is_empty():
		_load_and_play_animation(npc_animation)


## Capsule colors for NPCs without GLB models
const CAPSULE_COLORS: Dictionary = {
	"kai": Color(1.0, 0.9, 0.1),
	"dorn": Color(1.0, 0.6, 0.0),
	"ren": Color(0.0, 0.9, 0.9),
	"elio": Color(0.2, 0.9, 0.2),
	"mira": Color(0.7, 0.3, 0.9),
	"sarisa": Color(1.0, 0.5, 0.7),
	"fern": Color(0.6, 0.8, 0.3),
	"dr_carlo": Color(0.4, 0.6, 0.9),
	"vash": Color(0.6, 0.2, 0.2),
}


func _load_npc_model() -> void:
	var entry: Variant = NpcAssets.MODELS.get(npc_id, null)
	if entry == null:
		_spawn_capsule_placeholder()
		return

	var glb_path: String = entry["glb"]
	var packed := load(glb_path) as PackedScene
	if not packed:
		push_warning("FieldNpc: Failed to load model: " + glb_path)
		_spawn_capsule_placeholder()
		return

	model = packed.instantiate()
	add_child(model)

	# Apply separate texture if specified
	var tex_path: String = entry.get("texture", "")
	if not tex_path.is_empty():
		var tex := load(tex_path) as Texture2D
		if tex:
			MeshUtils.apply_texture(model, tex, false)


func _spawn_capsule_placeholder() -> void:
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = CAPSULE_COLORS.get(npc_id, Color(0.7, 0.7, 0.7))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# Name label above capsule
	if not npc_name.is_empty():
		var label := Label3D.new()
		label.text = npc_name
		label.position.y = 1.8
		label.font_size = 32
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)


func _on_interact(_player: Node3D) -> void:
	if dialog.is_empty():
		return

	dialog_started.emit()
	_show_dialog()


func _show_dialog() -> void:
	var hud := _find_hud()
	if not hud:
		push_warning("FieldNpc: No HUD found for dialog display")
		dialog_finished.emit()
		return

	var dialog_box := hud.get_node_or_null("DialogBox")
	if not dialog_box:
		var DialogBoxScript := preload("res://scripts/3d/ui/dialog_box.gd")
		dialog_box = DialogBoxScript.new()
		dialog_box.name = "DialogBox"
		hud.add_child(dialog_box)

	dialog_box.show_dialog(dialog)
	dialog_box.dialog_complete.connect(func() -> void:
		dialog_finished.emit()
	, CONNECT_ONE_SHOT)


func _find_hud() -> CanvasLayer:
	var node := get_parent()
	while node:
		for hud_name in ["FieldHud", "HUD"]:
			var hud := node.get_node_or_null(hud_name)
			if hud and hud is CanvasLayer:
				return hud as CanvasLayer
		node = node.get_parent()
	return null


func _apply_state() -> void:
	match element_state:
		"idle":
			set_element_visible(true)
		"hidden":
			set_element_visible(false)


func _load_and_play_animation(anim_field: String) -> void:
	if not model:
		return
	var skel: Skeleton3D = NodeUtils.first_of_type(model, "Skeleton3D") as Skeleton3D
	if not skel:
		return

	# Resolve animation name: "~dam_d_lp" → "pwsa_dam_d_lp" (female) or "pmsa_dam_d_lp" (male)
	var anim_name := anim_field
	if anim_name.begins_with("~"):
		var class_id: String = NpcAssets.CLASSES.get(npc_id, "humar")
		var is_female: bool = class_id in NpcAssets.FEMALE_CLASSES
		var prefix: String = "pwsa_" if is_female else "pmsa_"
		anim_name = prefix + anim_name.substr(1)

	# Pick animation source GLB based on gender
	var class_id: String = NpcAssets.CLASSES.get(npc_id, "humar")
	var is_female: bool = class_id in NpcAssets.FEMALE_CLASSES
	var anim_glb: String = "res://assets/player/animations/saver_w.glb" if is_female else "res://assets/player/animations/saber_m.glb"
	if not ResourceLoader.exists(anim_glb):
		return

	var anim_packed := load(anim_glb) as PackedScene
	if not anim_packed:
		return
	var anim_scene := anim_packed.instantiate()
	var source_player: AnimationPlayer = NodeUtils.first_of_type(anim_scene, "AnimationPlayer") as AnimationPlayer
	if not source_player or not source_player.has_animation(anim_name):
		push_warning("[FieldNpc] Animation '%s' not found in %s" % [anim_name, anim_glb])
		anim_scene.queue_free()
		return

	var anim := source_player.get_animation(anim_name).duplicate() as Animation
	anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(anim.get_track_count()):
		var track_path := String(anim.track_get_path(i))
		if "Skeleton3D" in track_path:
			var skel_idx := track_path.find("Skeleton3D")
			var prop_part := track_path.substr(skel_idx + 10)
			anim.track_set_path(i, NodePath(skel.name + prop_part))

	var player := AnimationPlayer.new()
	player.name = "NpcAnimPlayer"
	skel.get_parent().add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	player.add_animation_library("", lib)
	player.play(anim_name)
	anim_scene.queue_free()
	print("[FieldNpc] Playing '%s' on %s" % [anim_name, npc_id])
