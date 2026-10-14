extends "res://scripts/tools/probe_checks.gd"
const Traps := preload("res://scripts/2d/shops/coliseum_traps.gd")

func _run() -> void:
	probe_label = "coliseum-traps"
	var rows: Array = Traps.ROWS.duplicate(true)
	rows.append(rows[0]) # Revisit must be a fresh armed trap.
	for row in rows:
		var picker = load("res://scenes/2d/shops/coliseum_pick.tscn").instantiate()
		get_tree().root.add_child(picker)
		picker._load_tab(3)
		_check(picker._rows.size() == 11, "Traps page lists eleven tests")
		_check(not picker._enemy_level_button.visible, "trap page hides enemy level")
		picker._start_battle(row)
		picker.queue_free()
		if not await _wait_scene("res://scenes/3d/field/valley_field.tscn"):
			get_tree().quit(1)
			return
		var field := get_tree().current_scene
		for frame in 180:
			if is_instance_valid(field._room_minimap): break
			await get_tree().physics_frame
		var traps: Array = field._map_root.get_children().filter(func(n): return n is BearTrap or n is NeedleTrap or n is FieldHazard or n is TrapBall)
		var exits: Array = field._map_root.get_children().filter(func(n): return n is Telepipe)
		_check(traps.size() == 1, str(row.name) + " spawns exactly one trap")
		_check(field._room_enemies.is_empty(), "trap arena has no enemies")
		_check(exits.size() == 1, "exit is available before interacting with trap")
		if traps.size() == 1:
			_check(not traps[0]._spent if traps[0] is TrapBall else traps[0].element_state != "spent" if traps[0] is BearTrap else traps[0].element_state != "off", "new visit starts with a fresh trap")
			if row.has("model"): _check(traps[0].model_path.ends_with(str(row.model) + ".glb"), "gun variant matches selection")
		if exits.size() != 1:
			get_tree().quit(1)
			return
		var player: Node3D = get_tree().get_first_node_in_group("player")
		_check(player.global_position.distance_to(exits[0].global_position) < 7.0, "exit is beside the entrance")
		exits[0].interact(player)
		if not await _wait_scene("res://scenes/3d/city/city_counter.tscn"):
			get_tree().quit(1)
			return
		_check(not SessionManager.has_suspended_session() and not SessionManager.has_completed_quest(), "immediate exit leaves no quest report or suspended run")
	print("[coliseum-traps] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _wait_scene(path: String) -> bool:
	for frame in 600:
		await get_tree().physics_frame
		if not SceneManager._transitioning and get_tree().current_scene and get_tree().current_scene.scene_file_path == path: return true
	_check(false, "timed out loading " + path)
	return false
