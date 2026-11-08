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
var _positions: Dictionary = {}
var _default_positions: Dictionary = {}
var _clips := ["pmsp_wait", "pmsa_walk", "pso_pa_walk_ready", "pso_pa_wait", "pso_pa_run", "pmsp_atk1", "pmsp_atk2", "pmsp_atk3", "pso_pa_block", "pso_pa_walk"]

func setup(player: Node3D) -> void:
	_player = player
	var bazooka: bool = player._get_equipped_weapon_type() in [WeaponData.WeaponType.BAZOOKA, WeaponData.WeaponType.LASER_CANNON]
	var wand: bool = player._get_equipped_weapon_type() == WeaponData.WeaponType.WAND
	var rod: bool = player._get_equipped_weapon_type() == WeaponData.WeaponType.ROD
	var rifle: bool = player._get_equipped_weapon_type() == WeaponData.WeaponType.RIFLE
	var gunblade: bool = player._get_equipped_weapon_type() == WeaponData.WeaponType.GUN_BLADE
	var slicer: bool = player._get_equipped_weapon_type() == WeaponData.WeaponType.SLICER
	if slicer: _clips = ["pmsl_wait", "pmsa_walk", "pso_sl_walk_ready", "pso_sl_wait", "pso_sl_run", "pmsl_atk1", "pmsl_atk2", "pmsl_atk3", "pso_sl_block"]
	if gunblade: _clips = ["pmgb_wait", "pmsa_walk", "pso_gb_walk_ready", "pso_gb_wait", "pso_gb_run", "pmgb_atk1", "pmgb_atk2", "pmgb_atk3", "pso_gb_block", "pmgb_wait_sht", "pso_gb_gun_walk_ready", "pso_gb_gun_wait", "pso_gb_gun_run", "pmgb_shot_atk1", "pmgb_shot_atk2", "pmgb_shot_atk3"]
	if rifle: _clips = ["pmar_wait", "pso_ri_walk", "pso_ri_walk_ready", "pso_ri_wait", "pso_ri_run", "pmar_atk1", "pmar_atk2", "pmar_atk3", "pso_ri_block", "pso_ri_dam_n", "pso_ri_dam_h", "pso_ri_dam_d", "pso_ri_dam_d_wa"]
	if bazooka: _clips = ["pmar_wait", "pso_la_walk", "pso_la_walk_ready", "pso_la_wait", "pso_la_run", "pso_la_atk1", "pmar_atk1", "pso_la_block", "pso_la_dam_n", "pso_la_dam_h", "pso_la_dam_d", "pso_la_dam_d_wa"]
	if rod: _clips = ["pmro_wait", "pso_ro_walk", "pso_ro_walk_ready", "pso_ro_wait", "pso_ro_run", "pmro_atk1", "pmro_atk2", "pmro_atk3", "pso_ro_block"]
	if wand: _clips = ["pmwa_wait", "pmsa_walk", "pso_wn_walk_ready", "pso_wn_wait", "pso_wn_run", "pmwa_atk1", "pmwa_atk2", "pmwa_atk3", "pso_wn_block", "pso_wn_dam_n", "pso_wn_dam_h", "pso_wn_dam_d", "pso_wn_dam_d_wa"]
	if player._is_female:
		for i in _clips.size(): _clips[i] = _clips[i].replace("pmsp", "pwsp").replace("pmsa", "pwsa").replace("pso_pa", "pso_f_pa").replace("pmsl", "pwsls").replace("pso_sl", "pso_f_sl").replace("pmgb", "pwgbs").replace("pso_gb", "pso_f_gb").replace("pmar", "pwars").replace("pso_ri", "pso_f_ri").replace("pso_la", "pso_f_la").replace("pmro", "pwro").replace("pso_ro", "pso_f_ro")
	_blade = player.weapon_node
	_path = OS.get_environment("PSZ_GUNBLADE_GRIP_PATH" if gunblade else ("PSZ_SLICER_GRIP_PATH" if slicer else "PSZ_SPEAR_GRIP_PATH"))
	if wand: _path = OS.get_environment("PSZ_WAND_GRIP_PATH")
	if rod: _path = OS.get_environment("PSZ_ROD_GRIP_PATH")
	if rifle: _path = OS.get_environment("PSZ_RIFLE_GRIP_PATH")
	if bazooka: _path = OS.get_environment("PSZ_BAZOOKA_GRIP_PATH")
	if FileAccess.file_exists(_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary:
			var saved_positions = data.get("_positions", {})
			if saved_positions is Dictionary:
				for clip in saved_positions:
					var values = saved_positions[clip]
					if values is Array and values.size() == 3:
						var position := Vector3(values[0], values[1], values[2])
						if position.is_finite(): _positions[clip] = position
			for clip in data:
				var a = data[clip]
				if a is Array and a.size() == 9:
					var b := Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
					if b.is_finite() and absf(b.determinant()) > 0.001: _grips[clip] = b
	_player.set_meta("fixture_grips", _grips)
	_player.set_meta("fixture_grip_positions", _positions)
	layer = 210
	var panel := PanelContainer.new()
	panel.position = Vector2(245, 12)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = ("Gunblade" if gunblade else ("Slicer" if slicer else "Spear")) + " grip — separate rotation for each animation"
	if rifle: title.text = "Rifle grip — separate rotation for each animation"
	if bazooka: title.text = "Bazooka grip — rotation and position per pose"
	if rod: title.text = "Rod grip — rotation and position per pose"
	if wand: title.text = "Wand grip — rotation and position per pose"
	box.add_child(title)
	_selector = OptionButton.new()
	var labels := ["Relaxed idle — PSZ pmsp_wait", "Normal walk — pmsa_walk", "Caution walk — PSO 145", "Weapon ready — PSO 143", "Run — PSO 151", "Attack 1 — PSZ", "Attack 2 — PSZ", "Attack 3 — PSZ", "Block — PSO 144", "Source walk — PSO 145 (comparison)"]
	if slicer: labels = ["Relaxed idle — PSZ", "Normal walk", "Caution walk — PSO 152", "Weapon ready — PSO 156", "Run — PSO 111", "Attack 1 — PSZ", "Attack 2 — PSZ", "Attack 3 — PSZ", "Block — PSO 103"]
	if gunblade: labels = ["Blade relaxed idle", "Normal walk", "Blade caution walk", "Blade ready", "Blade run", "Blade attack 1", "Blade attack 2", "Blade attack 3", "Block", "Gun idle", "Gun caution walk", "Gun ready", "Gun run", "Gun attack 1", "Gun attack 2", "Gun attack 3"]
	if rifle: labels = ["Relaxed idle", "Normal walk — PSO 15", "Caution walk — PSO 10", "Weapon ready — PSO 13", "Run — PSO 22", "Attack 1 — PSZ", "Attack 2 — PSZ", "Attack 3 — PSZ", "Block — PSO 14", "Damage", "Big damage", "Fall down", "Get up"]
	if rifle and player._is_female: labels = ["Relaxed idle", "Normal walk — PSO 255", "Caution walk — PSO 250", "Weapon ready — PSO 253", "Run — PSO 262", "Attack 1 — PSZ", "Attack 2 — PSZ", "Attack 3 — PSZ", "Block — PSO 254", "Damage", "Big damage", "Fall down", "Get up"]
	if bazooka: labels = ["Current relaxed idle", "Normal walk — PSO shot 41", "Caution walk — PSO 49", "Carry / ready — PSO shot 39", "Run — PSO shot 48", "Launcher firing — PSO 51 (preview)", "Current rifle-donor firing", "Block — PSO 53", "Damage", "Big damage", "Fall down", "Get up"]
	if bazooka and player._is_female: labels = ["Current relaxed idle", "Normal walk — PSO shot 278", "Caution walk — PSO 286", "Carry / ready — PSO shot 276", "Run — PSO shot 285", "Launcher firing — PSO 288 (preview)", "Current rifle-donor firing", "Block — PSO 290", "Damage", "Big damage", "Fall down", "Get up"]
	if rod: labels = ["Relaxed idle — PSZ", "Normal walk — PSO 69", "Caution walk — PSO 62", "Weapon ready — PSO 67", "Run — PSO 111", "Attack 1", "Attack 2", "Attack 3", "Block — PSO 68"]
	if rod and player._is_female: labels = ["Relaxed idle — PSZ", "Normal walk — PSO 306", "Caution walk — PSO 299", "Weapon ready — PSO 304", "Run — PSO 342", "Attack 1", "Attack 2", "Attack 3", "Block — PSO 305"]
	if wand: labels = ["Relaxed idle — PSZ", "Normal walk — PSZ", "Caution walk — PSO 76", "Weapon ready — PSO 81", "Run — PSO 111", "Attack 1", "Attack 2", "Attack 3", "Block — PSO 82", "Damage", "Big damage", "Fall down", "Get up"]
	for label in labels: _selector.add_item(label.replace("pmsp", "pwsp").replace("pmsa", "pwsa") if player._is_female else label)
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
	if rifle or bazooka or rod or wand:
		for axis in range(3):
			var row := HBoxContainer.new()
			box.add_child(row)
			var label := Label.new()
			label.text = ["Position X", "Position Y", "Position Z"][axis]
			row.add_child(label)
			for amount in [-0.05, -0.01, 0.01, 0.05]:
				var button := Button.new()
				button.text = "%+.2f" % amount
				button.focus_mode = Control.FOCUS_NONE
				button.pressed.connect(_move.bind(axis, amount))
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
	if rifle:
		_selector.select(1)
		_select(1)
	if rod or wand:
		_selector.select(0)
		_select(0)
	if bazooka:
		_selector.select(3)
		_select(3)

func _select(index: int) -> void:
	_clip = _clips[index]
	if not _preview.button_pressed:
		_preview.button_pressed = true
		return
	# Measure the branch default separately from saved/user adjustments.
	_player.set_meta("fixture_grips", {})
	_player.set_meta("fixture_grip_positions", {})
	_player._sword_grip_clip = ""
	_player.play_animation(_clip, true)
	if _player._weapon_grip_tween: _player._weapon_grip_tween.custom_step(1.0)
	_defaults[_clip] = _blade.basis
	_default_positions[_clip] = _blade.position
	_player.set_meta("fixture_grip_positions", _positions)
	_player.set_meta("fixture_grips", _grips)
	if _grips.has(_clip): _blade.basis = _grips[_clip]
	if _positions.has(_clip): _blade.position = _positions[_clip]
	_seek(_scrub.value)
	_toggle_play(_playing.button_pressed)
	_update_angles()

func _toggle_preview(enabled: bool) -> void:
	_player.set_meta("fixture_grip_preview", enabled)
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

func _move(axis: int, amount: float) -> void:
	if not _preview.button_pressed: return
	_blade.position += [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis] * amount
	_positions[_clip] = _blade.position
	_update_angles()
	_status.text = "Unsaved position for " + _clip + " — Save all when ready."

func _update_angles() -> void:
	var r := _blade.rotation_degrees
	_angles.text = "%s: X %.1f°  Y %.1f°  Z %.1f°" % [_clip, r.x, r.y, r.z]
	_angles.text += "\nPosition: %.2f, %.2f, %.2f" % [_blade.position.x, _blade.position.y, _blade.position.z]

func _action(action: String) -> void:
	if action == "Save all":
		var data := {}
		for clip in _grips:
			var b: Basis = _grips[clip]
			data[clip] = [b.x.x,b.x.y,b.x.z,b.y.x,b.y.y,b.y.z,b.z.x,b.z.y,b.z.z]
		if not _positions.is_empty():
			data["_positions"] = {}
			for clip in _positions:
				var pos: Vector3 = _positions[clip]
				data["_positions"][clip] = [pos.x, pos.y, pos.z]
		var file := FileAccess.open(_path, FileAccess.WRITE)
		if file == null:
			_status.text = "Could not save grips."
			return
		file.store_string(JSON.stringify(data, "  "))
		file.close()
		_preview.button_pressed = false
		hide()
	elif action == "Copy selected":
		DisplayServer.clipboard_set(_angles.text + "\nBasis: " + str(_blade.basis))
	elif action == "Reset selected" and _preview.button_pressed:
		_blade.basis = _defaults[_clip]
		_grips.erase(_clip)
		_blade.position = _default_positions[_clip]
		_positions.erase(_clip)
		_update_angles()
		_status.text = "Selected pose reset to branch default. Save all to keep reset."
