extends GameElement
class_name FieldNpc
## NPC character that appears in the field with a GLB model and dialog.
## Player can press E to talk. Dialog pages cycle on repeated interact.

signal dialog_started
signal dialog_finished

@export var npc_id: String = ""
@export var npc_name: String = ""
@export var dialog: Array = []  # Array of {speaker: String, text: String}

## Known NPC models — maps npc_id to GLB path
const NPC_MODELS: Dictionary = {
	"sarisa": "res://assets/npcs/sarisa/pc_a00_000.glb",
	"kai": "res://assets/npcs/kai/pc_a01_000.glb",
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


func _load_npc_model() -> void:
	var glb_path: String = NPC_MODELS.get(npc_id, "")
	if glb_path.is_empty():
		push_warning("FieldNpc: No model for npc_id '%s'" % npc_id)
		return

	var packed := load(glb_path) as PackedScene
	if not packed:
		push_warning("FieldNpc: Failed to load model: " + glb_path)
		return

	model = packed.instantiate()
	add_child(model)


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
		var hud := node.get_node_or_null("HUD")
		if hud and hud is CanvasLayer:
			return hud as CanvasLayer
		for child in node.get_children():
			if child is CanvasLayer and child.name == "HUD":
				return child as CanvasLayer
		node = node.get_parent()
	return null


func _apply_state() -> void:
	match element_state:
		"idle":
			set_element_visible(true)
		"hidden":
			set_element_visible(false)
