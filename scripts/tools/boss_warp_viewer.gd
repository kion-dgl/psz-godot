extends Node3D
## Interactive viewer for the boss warp in the real Valley goal room (seed 782).
## Run: godot --path . res://scripts/tools/boss_warp_viewer.tscn
## Keys: 1-4 switch state, Space pauses/resumes the scroll, arrows orbit and
## zoom, C toggles auto-cycling, Esc quits.

const STATES := ["locked", "open", "inactive", "active"]
const AUTO_INTERVAL := 2.5

var _warp: BossWarp
var _camera: Camera3D
var _label: Label
var _state_index := 0
var _auto := true
var _auto_time := 0.0
var _scroll_paused := false
var _orbit_angle := 0.96
var _orbit_distance := 13.0
var _orbit_height := 5.5

func _ready() -> void:
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "WarpViewer")
	CharacterManager.set_active_slot(0)
	var generator := preload("res://scripts/3d/field/grid_generator.gd").new()
	generator.set_seed(782)
	var field: Dictionary = generator.generate_field("normal", "gurhacia")
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections(field.sections)
	SessionManager.set_current_section(2)
	SceneManager._transition_data = {"current_cell_pos": field.sections[2].end_pos}
	var room := (load("res://scenes/3d/field/valley_field.tscn") as PackedScene).instantiate()
	add_child(room)
	for frame in range(120):
		await get_tree().process_frame
		if room.player != null and room._gate_mgr != null:
			break
	await get_tree().create_timer(1.0).timeout
	for child in room.get_children():
		if child is BossWarp:
			_warp = child
	if _warp == null:
		push_error("[boss-warp-viewer] no BossWarp spawned in the goal room")
		get_tree().quit(1)
		return
	room.player.set_physics_process(false)
	_camera = Camera3D.new()
	room.add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	layer.layer = 300
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(_label)
	_apply_state()
	print("[boss-warp-viewer] ready — window stays open; press Esc to quit")

func _process(delta: float) -> void:
	if _warp == null:
		return
	if _auto:
		_auto_time += delta
		if _auto_time >= AUTO_INTERVAL:
			_auto_time = 0.0
			_state_index = (_state_index + 1) % STATES.size()
			_apply_state()
	var center: Vector3 = _warp.global_position + Vector3.UP * 2.0
	_camera.global_position = center + Vector3(
		cos(_orbit_angle) * _orbit_distance,
		_orbit_height,
		sin(_orbit_angle) * _orbit_distance)
	_camera.look_at(center)
	if _label != null and _scroll_paused:
		_label.modulate = Color(1, 0.8, 0.8)
	else:
		_label.modulate = Color.WHITE

func _input(event: InputEvent) -> void:
	if _warp == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_auto = false
			_state_index = key - KEY_1
			_apply_state()
		KEY_SPACE:
			_scroll_paused = not _scroll_paused
			_warp.set_process(not _scroll_paused)
		KEY_C:
			_auto = not _auto
			_auto_time = 0.0
			_apply_state()
		KEY_LEFT:
			_orbit_angle -= 0.08
		KEY_RIGHT:
			_orbit_angle += 0.08
		KEY_UP:
			_orbit_distance = maxf(4.0, _orbit_distance - 0.6)
		KEY_DOWN:
			_orbit_distance = minf(40.0, _orbit_distance + 0.6)
		KEY_ESCAPE:
			get_tree().quit(0)

func _apply_state() -> void:
	_warp.set_state(STATES[_state_index])
	if _label != null:
		_label.text = "BossWarp: %s%s\n[1]locked [2]open [3]inactive [4]active  [Space]pause scroll  [<-/->]orbit [^/v]zoom  [C]auto-cycle  [Esc]quit" % [
			STATES[_state_index].to_upper(),
			" (auto)" if _auto else ""]
