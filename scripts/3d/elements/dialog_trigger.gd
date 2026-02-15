extends GameElement
class_name DialogTrigger
## Invisible Area3D zone that shows a dialog box when the player enters.
## One-shot: once triggered, won't fire again in the same session.

signal dialog_finished

@export var trigger_id: String = ""
@export var dialog: Array = []  # Array of {speaker: String, text: String}

var _triggered: bool = false


func _init() -> void:
	interactable = false
	auto_collect = false
	collision_size = Vector3(4.0, 3.0, 4.0)
	element_state = "ready"


func _ready() -> void:
	# Skip model loading — this is invisible
	_setup_trigger_area()
	_apply_state()


func _setup_trigger_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "TriggerArea"
	interaction_area.collision_layer = 4  # Triggers layer
	interaction_area.collision_mask = 2   # Player layer

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	interaction_area.add_child(shape)

	interaction_area.body_entered.connect(_on_player_entered)
	add_child(interaction_area)


func _on_player_entered(body: Node3D) -> void:
	if _triggered:
		return
	if not (body.is_in_group("player") or body.name == "Player"):
		return
	if dialog.is_empty():
		return

	_triggered = true
	set_state("triggered")
	_show_dialog()


func _show_dialog() -> void:
	# Find or create dialog box on the HUD
	var hud := _find_hud()
	if not hud:
		push_warning("DialogTrigger: No HUD found for dialog display")
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
	# Walk up tree looking for CanvasLayer named HUD
	var node := get_parent()
	while node:
		var hud := node.get_node_or_null("HUD")
		if hud and hud is CanvasLayer:
			return hud as CanvasLayer
		# Also check for HUD as direct sibling of root
		for child in node.get_children():
			if child is CanvasLayer and child.name == "HUD":
				return child as CanvasLayer
		node = node.get_parent()
	return null


func _apply_state() -> void:
	# Invisible element — nothing to show/hide
	pass
