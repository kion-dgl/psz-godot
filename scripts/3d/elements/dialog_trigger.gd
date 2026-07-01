extends GameElement
class_name DialogTrigger
## Invisible Area3D zone that shows a dialog box when the player enters.
## One-shot: once triggered, won't fire again in the same session.
##
## trigger_condition controls WHEN this fires:
##   "enter" (default) — Area3D body_entered (walk into zone)
##   "room_clear"      — no Area3D; activate() must be called externally
##   "item_pickup"     — fires when a quest item is collected in the same room
##
## actions[] runs after dialog finishes:
##   "play_credits"        — complete quest + transition to credits roll
##   "complete_quest"      — SessionManager.complete_quest()
##   "telepipe"            — return to city
##   "dismiss_companion"   — companion stops following and idles in place

signal dialog_finished

@export var trigger_id: String = ""
@export var dialog: Array = []  # Array of {speaker: String, text: String}
@export var trigger_condition: String = "enter"  # "enter", "room_clear", or "item_pickup"
@export var actions: Array = []  # ["complete_quest", "telepipe"]

var _triggered: bool = false
var _player_ref: Node3D = null
var companion_node: Node3D = null  # If set, route dialog to companion speech bubble


func _init() -> void:
	interactable = false
	auto_collect = false
	collision_size = Vector3(4.0, 3.0, 4.0)
	element_state = "ready"


func _ready() -> void:
	# Skip model loading — this is invisible
	if trigger_condition == "enter":
		_setup_trigger_area()
	elif trigger_condition == "item_pickup":
		SessionManager.quest_item_collected.connect(_on_quest_item_collected)
	_apply_state()


func _on_quest_item_collected(_item_id: String, _new_count: int, _target: int) -> void:
	activate()


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

	# Debug visualization — cyan transparent box (toggled with F5 via trigger_ prefix)
	var debug_mesh := MeshInstance3D.new()
	debug_mesh.name = "trigger_dialog_debug"
	var box_mesh := BoxMesh.new()
	box_mesh.size = collision_size
	debug_mesh.mesh = box_mesh
	debug_mesh.position.y = collision_size.y / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.9, 0.9, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	debug_mesh.material_override = mat
	add_child(debug_mesh)


func _on_player_entered(body: Node3D) -> void:
	if _triggered:
		return
	if not (body.is_in_group("player") or body.name == "Player"):
		return
	if dialog.is_empty():
		return

	_triggered = true
	_player_ref = body
	_freeze_player()
	set_state("triggered")
	_show_dialog()


## Externally called for room_clear triggers (after all enemies defeated).
func activate() -> void:
	if _triggered:
		return
	if dialog.is_empty():
		return

	_triggered = true
	# Find player in the scene tree
	_player_ref = get_tree().get_first_node_in_group("player")
	_freeze_player()
	set_state("triggered")
	_show_dialog()


func _freeze_player() -> void:
	if _player_ref and _player_ref.has_method("transition_to"):
		_player_ref.transition_to(_player_ref.PlayerState.CUTSCENE)


func _unfreeze_player() -> void:
	if _player_ref and _player_ref.has_method("transition_to"):
		if _player_ref.current_state == _player_ref.PlayerState.CUTSCENE:
			# Resume running if player is holding movement input
			var has_input := Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
			if has_input:
				_player_ref.transition_to(_player_ref.PlayerState.RUNNING)
			else:
				_player_ref.transition_to(_player_ref.PlayerState.IDLE)
	_player_ref = null


func _show_dialog() -> void:
	var pages: Array = dialog.duplicate(true)
	# If this trigger has completion actions and objectives are now met, append completion text
	var _objectives_met := _has_completion_actions() and SessionManager.are_objectives_complete()
	if _objectives_met:
		pages.append({"speaker": "", "text": "Quest complete! Please report to the Guild."})

	# Route to companion speech bubble — no camera change, no player freeze, auto-advance
	if companion_node and is_instance_valid(companion_node) and companion_node.has_method("show_speech"):
		print("[DialogTrigger] '%s' → companion speech bubble (%d pages)" % [trigger_id, pages.size()])
		_unfreeze_player()
		_show_companion_dialog(pages)
		return
	else:
		print("[DialogTrigger] '%s' → HUD dialog box (companion_node=%s)" % [trigger_id, companion_node])

	# Find or create dialog box on the HUD
	var hud := _find_hud()
	if not hud:
		push_warning("DialogTrigger: No HUD found for dialog display")
		_unfreeze_player()
		_execute_actions()
		dialog_finished.emit()
		return

	var dialog_box := hud.get_node_or_null("DialogBox")
	if not dialog_box:
		var DialogBoxScript := preload("res://scripts/3d/ui/dialog_box.gd")
		dialog_box = DialogBoxScript.new()
		dialog_box.name = "DialogBox"
		hud.add_child(dialog_box)

	dialog_box.show_dialog(pages)
	dialog_box.dialog_complete.connect(func() -> void:
		_unfreeze_player()
		_execute_actions()
		dialog_finished.emit()
	, CONNECT_ONE_SHOT)


func _show_companion_dialog(pages: Array) -> void:
	_show_companion_page(pages, 0)


func _show_companion_page(pages: Array, index: int) -> void:
	if index >= pages.size() or not is_instance_valid(companion_node):
		_execute_actions()
		dialog_finished.emit()
		return
	var page: Dictionary = pages[index]
	var text: String = str(page.get("text", ""))
	var speaker: String = str(page.get("speaker", ""))
	# Auto-advance: ~1 second per 12 characters, minimum 3 seconds
	var duration: float = maxf(3.0, text.length() / 20.0)
	companion_node.show_speech(text, speaker, duration)

	var next_idx := index + 1
	companion_node.speech_finished.connect(func() -> void:
		_show_companion_page(pages, next_idx)
	, CONNECT_ONE_SHOT)


func _has_completion_actions() -> bool:
	for action in actions:
		if str(action) in ["complete_quest", "telepipe"]:
			return true
	return false


func _execute_actions() -> void:
	var objectives_met := SessionManager.are_objectives_complete()
	for action in actions:
		match str(action):
			"play_credits":
				print("[DialogTrigger] Action: play_credits → credits scene")
				# Complete quest first so save state is correct
				if objectives_met:
					SessionManager.complete_quest()
				SceneManager.goto_scene("res://scenes/2d/credits.tscn")
				return  # Don't process further actions
			"complete_quest":
				if not objectives_met:
					continue
				print("[DialogTrigger] Action: complete_quest")
				SfxManager.play("res://assets/sfx/ui/quest_complete.wav")
				SessionManager.complete_quest()
			"telepipe":
				if not objectives_met:
					continue
				print("[DialogTrigger] Action: spawning telepipe at trigger position")
				_spawn_telepipe_at_position()
			"dismiss_companion":
				if companion_node and is_instance_valid(companion_node) and companion_node.has_method("dismiss"):
					print("[DialogTrigger] Action: dismiss_companion")
					companion_node.dismiss()


func _spawn_telepipe_at_position() -> void:
	var TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")
	var telepipe := TelepipeScript.new()
	telepipe.name = "Telepipe"
	get_parent().add_child(telepipe)
	telepipe.position = position
	# Connect to field controller's end logic via tree
	var field_controller := _find_field_controller()
	if field_controller and field_controller.has_method("_on_end_reached"):
		telepipe.activated.connect(func() -> void:
			field_controller._on_end_reached()
		)
	else:
		# Fallback: go to city directly
		telepipe.activated.connect(func() -> void:
			SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
		)


func _find_field_controller() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("_on_end_reached"):
			return node
		node = node.get_parent()
	return null


func _find_hud() -> CanvasLayer:
	# Walk up tree looking for a CanvasLayer named HUD or FieldHud
	var node := get_parent()
	while node:
		for child in node.get_children():
			if child is CanvasLayer and (child.name == "HUD" or child.name == "FieldHud"):
				return child as CanvasLayer
		node = node.get_parent()
	return null


func _apply_state() -> void:
	# Invisible element — nothing to show/hide
	pass
