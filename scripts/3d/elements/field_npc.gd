extends GameElement
class_name FieldNpc
## NPC character that appears in the field with a GLB model and dialog.
## Player can press E to talk. Dialog pages cycle on repeated interact.

signal dialog_started
signal dialog_finished

@export var npc_id: String = ""
@export var npc_name: String = ""
@export var dialog: Array = []  # Array of {speaker: String, text: String}

## Known NPC models — maps npc_id to { glb, texture } paths
const NPC_MODELS: Dictionary = {
	"sarisa": {
		"glb": "res://assets/npcs/sarisa/pc_a00_000.glb",
		"texture": "res://assets/npcs/sarisa/pc_a00_000.png",
	},
	"kai": {
		"glb": "res://assets/npcs/kai/pc_a01_000.glb",
		"texture": "res://assets/npcs/kai/pc_a01_000.png",
	},
}


func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 2.0, 2.0)
	element_state = "idle"


func _ready() -> void:
	_load_npc_model()
	_setup_collision()
	_apply_state()


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
	var entry: Variant = NPC_MODELS.get(npc_id, null)
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
			_apply_texture(model, tex)


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


func _apply_texture(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				new_mat.albedo_texture = tex
				mi.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_apply_texture(child, tex)


func _apply_state() -> void:
	match element_state:
		"idle":
			set_element_visible(true)
		"hidden":
			set_element_visible(false)
