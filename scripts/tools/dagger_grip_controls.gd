extends CanvasLayer
## Local-only controls for the isolated dagger playtest; never loaded in campaign.
var _player: Node3D
var _blade: Node3D
var _original: Basis
var _angles: Label
var _status: Label
var _path: String

func setup(player: Node3D) -> void:
	_player = player
	_blade = player.weapon_node_left
	_original = _blade.basis
	_path = OS.get_environment("PSZ_DAGGER_GRIP_PATH")
	layer = 210
	var panel := PanelContainer.new()
	panel.position = Vector2(245, 12)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Left dagger orientation (right hand unchanged)"
	box.add_child(title)
	_angles = Label.new()
	box.add_child(_angles)
	for axis in range(3):
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_label := Label.new()
		name_label.text = ["Local X", "Local Y", "Local Z (blade length)"][axis]
		name_label.custom_minimum_size.x = 165
		row.add_child(name_label)
		for degrees in [-90, -5, 5, 90, 180]:
			var button := Button.new()
			button.text = ("+" if degrees > 0 else "") + str(degrees) + "°"
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_rotate.bind(axis, degrees))
			row.add_child(button)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for caption in ["Reset", "Save", "Copy angles", "Preview block"]:
		var button := Button.new()
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_action.bind(caption))
		actions.add_child(button)
	var pause := CheckButton.new()
	pause.text = "Freeze enemies while adjusting"
	pause.focus_mode = Control.FOCUS_NONE
	pause.toggled.connect(_freeze_enemies)
	box.add_child(pause)
	pause.button_pressed = true
	_status = Label.new()
	_status.text = "Changes are live. Save keeps them across fixture restarts."
	box.add_child(_status)
	if not _path.is_empty() and FileAccess.file_exists(_path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary and data.get("basis", []).size() == 9:
			var a: Array = data.basis
			var saved := Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
			if saved.is_finite() and absf(saved.determinant()) > 0.001:
				_blade.basis = saved
				_status.text = "Loaded your saved left-hand orientation."
	_update_angles()

func _rotate(axis: int, degrees: int) -> void:
	if not is_instance_valid(_blade): return
	_blade.rotate_object_local([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis], deg_to_rad(float(degrees)))
	_update_angles()
	_status.text = "Unsaved adjustment — test it, then Save."

func _update_angles() -> void:
	var r := _blade.rotation_degrees
	_angles.text = "Rotation: X %.1f°   Y %.1f°   Z %.1f°" % [r.x, r.y, r.z]

func _action(action: String) -> void:
	if action == "Preview block":
		var enemies := get_tree().get_nodes_in_group("enemies")
		if not enemies.is_empty():
			preload("res://scripts/3d/player/humar_saber_prototype.gd").block_feedback(_player, enemies[0])
			_status.text = "Block effect preview (no gameplay block triggered)."
	elif action == "Reset":
		_blade.basis = _original
		_update_angles()
		_status.text = "Reset to current branch defaults (Save to keep reset)."
	elif action == "Copy angles":
		DisplayServer.clipboard_set(_angles.text + "\nBasis: " + str(_blade.basis))
		_status.text = "Copied angles and exact basis."
	elif action == "Save":
		var file := FileAccess.open(_path, FileAccess.WRITE)
		if file == null:
			_status.text = "Could not save orientation."
			return
		var b := _blade.basis
		file.store_string(JSON.stringify({"basis": [b.x.x,b.x.y,b.x.z,b.y.x,b.y.y,b.y.z,b.z.x,b.z.y,b.z.z], "rotation_degrees": [_blade.rotation_degrees.x,_blade.rotation_degrees.y,_blade.rotation_degrees.z]}, "  "))
		file.close()
		_status.text = "Saved — tell me when ready and I can apply this grip."

func _freeze_enemies(frozen: bool) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(not frozen)
