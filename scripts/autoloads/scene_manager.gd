extends Node
## SceneManager — handles scene transitions with stack-based navigation.
## Use goto_scene() for full transitions, push_scene()/pop_scene() for overlays.

signal scene_changed(scene_path: String)

var _scene_stack: Array[String] = []
var _transition_data: Dictionary = {}
var _transitioning: bool = false

## Overlay for fade transitions
var _fade_rect: ColorRect

## Overlay system — overlays render on a CanvasLayer above the base scene
var _overlay_canvas: CanvasLayer
var _overlay_stack: Array = []  # [{scene: Node, dim: ColorRect, path: String}]


func _ready() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.anchors_preset = Control.PRESET_FULL_RECT
	_fade_rect.z_index = 100
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(_fade_rect)
	add_child(canvas)

	_overlay_canvas = CanvasLayer.new()
	_overlay_canvas.layer = 50
	add_child(_overlay_canvas)


## Get data passed from the previous scene
func get_transition_data() -> Dictionary:
	return _transition_data


## Full scene change — clears all overlays and stack, then fades to new scene
func goto_scene(scene_path: String, data: Dictionary = {}) -> void:
	if _transitioning:
		return
	_transition_data = data

	# Instantly clear all overlays (no animation)
	for entry in _overlay_stack:
		if is_instance_valid(entry.dim):
			entry.dim.queue_free()
		if is_instance_valid(entry.scene):
			entry.scene.queue_free()
	_overlay_stack.clear()
	_scene_stack.clear()

	# Re-enable base scene if it was disabled
	var base: Node = get_tree().current_scene
	if base:
		base.process_mode = Node.PROCESS_MODE_INHERIT

	await _fade_to_scene(scene_path)


## Push an overlay scene on top of the current scene (no scene replacement)
func push_scene(scene_path: String, data: Dictionary = {}) -> void:
	if _transitioning:
		return
	_transitioning = true
	_transition_data = data

	# Disable input on current top (base scene or previous overlay)
	var current_top: Node = _get_current_top()
	if current_top:
		current_top.process_mode = Node.PROCESS_MODE_DISABLED

	# Load and instantiate the overlay scene
	var packed: PackedScene = load(scene_path)
	var scene_instance: Node = packed.instantiate()

	# Create dim ColorRect (full screen, blocks input behind)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.anchors_preset = Control.PRESET_FULL_RECT
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Start overlay invisible
	scene_instance.modulate.a = 0.0

	# Add to overlay canvas
	_overlay_canvas.add_child(dim)
	_overlay_canvas.add_child(scene_instance)

	# Track in stacks
	var entry := {scene = scene_instance, dim = dim, path = scene_path}
	_overlay_stack.append(entry)
	_scene_stack.append(scene_path)

	# Animate in: dim fades to 0.5, scene fades to 1.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(dim, "color:a", 0.5, 0.15)
	tween.tween_property(scene_instance, "modulate:a", 1.0, 0.15)
	await tween.finished

	scene_changed.emit(scene_path)
	_transitioning = false


## Pop the top overlay scene
func pop_scene(data: Dictionary = {}) -> void:
	if _transitioning:
		return
	if _overlay_stack.is_empty():
		return
	_transitioning = true
	_transition_data = data

	var entry: Dictionary = _overlay_stack.pop_back()
	_scene_stack.pop_back()

	# Animate out
	if is_instance_valid(entry.scene) and is_instance_valid(entry.dim):
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(entry.dim, "color:a", 0.0, 0.15)
		tween.tween_property(entry.scene, "modulate:a", 0.0, 0.15)
		await tween.finished
		entry.dim.queue_free()
		entry.scene.queue_free()

	# Re-enable previous top (overlay or base scene)
	var new_top: Node = _get_current_top()
	if new_top:
		new_top.process_mode = Node.PROCESS_MODE_INHERIT

	_transitioning = false


## Check if we can pop (have overlays open)
func can_pop() -> bool:
	return not _overlay_stack.is_empty()


func _fade_to_scene(scene_path: String) -> void:
	_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fade out
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 0.15)
	await tween.finished

	# Change scene
	get_tree().change_scene_to_file(scene_path)
	scene_changed.emit(scene_path)

	# Fade in
	await get_tree().process_frame
	var tween2 := create_tween()
	tween2.tween_property(_fade_rect, "color:a", 0.0, 0.15)
	await tween2.finished

	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


## Get the current top-most node (latest overlay, or base scene if no overlays)
func _get_current_top() -> Node:
	if not _overlay_stack.is_empty():
		return _overlay_stack.back().scene
	return get_tree().current_scene
