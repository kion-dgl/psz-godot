extends CanvasLayer
## Isolated fixture authoring panel. Overrides are per animation, not campaign data.
var _player: Node3D
var _blade: Node3D
var _selector: OptionButton
var _preview: CheckButton
var _playing: CheckButton
var _scrub: HSlider
var _angles: Label
var _status: Label
var _path: String
var _clip := ""
var _grips: Dictionary = {}
var _defaults: Dictionary = {}
var _clips := ["pmsp_wait", "pmsa_walk", "pso_pa_walk_ready", "pso_pa_wait", "pso_pa_run", "pmsp_atk1", "pmsp_atk2", "pmsp_atk3", "pso_pa_block", "pso_pa_walk"]

func setup(player: Node3D) -> void:
	_player = player
	_blade = player.weapon_node
	_path = OS.get_environment("PSZ_SPEAR_GRIP_PATH")
	if FileAccess.file_exists(_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary:
			for clip in data:
				var a = data[clip]
				if a is Array and a.size() == 9:
					var b := Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
					if b.is_finite() and absf(b.determinant()) > 0.001: _grips[clip] = b
	_player.set_meta("fixture_grips", _grips)
	layer = 210
	var panel := PanelContainer.new()
	panel.position = Vector2(245, 12)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Spear grip — separate rotation for each animation"
	box.add_child(title)
	_selector = OptionButton.new()
	var labels := ["Relaxed idle — PSZ pmsp_wait", "Normal walk — pmsa_walk", "Caution walk — PSO 145", "Weapon ready — PSO 143", "Run — PSO 151", "Attack 1 — PSZ", "Attack 2 — PSZ", "Attack 3 — PSZ", "Block — PSO 144", "Source walk — PSO 145 (comparison)"]
	for label in labels: _selector.add_item(label)
	_selector.focus_mode = Control.FOCUS_NONE
	_selector.item_selected.connect(_select)
	box.add_child(_selector)
	_preview = CheckButton.new()
	_preview.text = "Preview selected animation (uncheck to test gameplay)"
	_preview.focus_mode = Control.FOCUS_NONE
	_preview.toggled.connect(_toggle_preview)
	box.add_child(_preview)
	_playing = CheckButton.new()
	_playing.text = "Play animation (off = scrub / hold pose)"
	_playing.focus_mode = Control.FOCUS_NONE
	_playing.toggled.connect(_toggle_play)
	box.add_child(_playing)
	_scrub = HSlider.new()
	_scrub.min_value = 0
	_scrub.max_value = 1
	_scrub.step = 0.01
	_scrub.value = 0.3
	_scrub.custom_minimum_size = Vector2(450, 24)
	_scrub.value_changed.connect(_seek)
	box.add_child(_scrub)
	_angles = Label.new()
	box.add_child(_angles)
	for axis in range(3):
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = ["Local X", "Local Y", "Local Z"][axis]
		label.custom_minimum_size.x = 80
		row.add_child(label)
		for degrees in [-90, -5, 5, 90, 180]:
			var button := Button.new()
			button.text = ("+" if degrees > 0 else "") + str(degrees) + "°"
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_rotate.bind(axis, degrees))
			row.add_child(button)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for caption in ["Reset selected", "Save all", "Copy selected"]:
		var button := Button.new()
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_action.bind(caption))
		actions.add_child(button)
	_status = Label.new()
	_status.text = "Enemies freeze during preview. Changes persist when switching poses."
	box.add_child(_status)
	_preview.button_pressed = true

func _select(index: int) -> void:
	_clip = _clips[index]
	if not _preview.button_pressed:
		_preview.button_pressed = true
		return
	# Measure the branch default separately from saved/user adjustments.
	_player.set_meta("fixture_grips", {})
	_player._sword_grip_clip = ""
	_player.play_animation(_clip, true)
	if _player._weapon_grip_tween: _player._weapon_grip_tween.custom_step(1.0)
	_defaults[_clip] = _blade.basis
	_player.set_meta("fixture_grips", _grips)
	if _grips.has(_clip): _blade.basis = _grips[_clip]
	_seek(_scrub.value)
	_toggle_play(_playing.button_pressed)
	_update_angles()

func _toggle_preview(enabled: bool) -> void:
	_player.set_physics_process(not enabled)
	_player.velocity = Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.set_physics_process(not enabled)
	if enabled:
		_select(_selector.selected)
	else:
		_player._sword_grip_clip = ""
		_player.transition_to(_player.PlayerState.IDLE)

func _toggle_play(playing: bool) -> void:
	if not _preview.button_pressed: return
	if playing: _player.animation_player.play(_clip)
	else: _player.animation_player.pause()

func _seek(fraction: float) -> void:
	if not _preview.button_pressed or _clip.is_empty(): return
	_player.animation_player.seek(_player.animation_player.get_animation(_clip).length * fraction, true)
	if not _playing.button_pressed: _player.animation_player.pause()

func _rotate(axis: int, degrees: int) -> void:
	if not _preview.button_pressed:
		_status.text = "Enable preview to adjust the selected animation."
		return
	if _player._weapon_grip_tween: _player._weapon_grip_tween.kill()
	_blade.rotate_object_local([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis], deg_to_rad(float(degrees)))
	_grips[_clip] = _blade.basis
	_update_angles()
	_status.text = "Unsaved change for " + _clip + " — Save all when ready."

func _update_angles() -> void:
	var r := _blade.rotation_degrees
	_angles.text = "%s: X %.1f°  Y %.1f°  Z %.1f°" % [_clip, r.x, r.y, r.z]

func _action(action: String) -> void:
	if action == "Save all":
		var data := {}
		for clip in _grips:
			var b: Basis = _grips[clip]
			data[clip] = [b.x.x,b.x.y,b.x.z,b.y.x,b.y.y,b.y.z,b.z.x,b.z.y,b.z.z]
		var file := FileAccess.open(_path, FileAccess.WRITE)
		if file == null:
			_status.text = "Could not save grips."
			return
		file.store_string(JSON.stringify(data, "  "))
		file.close()
		_status.text = "Saved all adjusted poses — tell me when ready."
	elif action == "Copy selected":
		DisplayServer.clipboard_set(_angles.text + "\nBasis: " + str(_blade.basis))
	elif action == "Reset selected" and _preview.button_pressed:
		_blade.basis = _defaults[_clip]
		_grips.erase(_clip)
		_update_angles()
		_status.text = "Selected pose reset to branch default. Save all to keep reset."
