extends Node
## SceneManager — handles scene transitions with stack-based navigation.
## Use goto_scene() for full transitions, push_scene()/pop_scene() for overlays.

signal scene_changed(scene_path: String)

var _scene_stack: Array[String] = []
var _transition_data: Dictionary = {}
var _transitioning: bool = false

## Overlay for fade transitions
var _fade_rect: ColorRect


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


## Get data passed from the previous scene
func get_transition_data() -> Dictionary:
	return _transition_data


## Full scene change — clears stack
func goto_scene(scene_path: String, data: Dictionary = {}) -> void:
	if _transitioning:
		return
	_transition_data = data
	_scene_stack.clear()
	await _fade_to_scene(scene_path)


## Push a scene onto the stack (for overlays like inventory, shops)
func push_scene(scene_path: String, data: Dictionary = {}) -> void:
	if _transitioning:
		return
	_transition_data = data
	var current := get_tree().current_scene.scene_file_path
	if not current.is_empty():
		_scene_stack.append(current)
	await _fade_to_scene(scene_path)


## Pop back to the previous scene
func pop_scene(data: Dictionary = {}) -> void:
	if _transitioning:
		return
	if _scene_stack.is_empty():
		return
	_transition_data = data
	var prev_scene := _scene_stack.pop_back()
	await _fade_to_scene(prev_scene)


## Check if we can pop
func can_pop() -> bool:
	return not _scene_stack.is_empty()


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
