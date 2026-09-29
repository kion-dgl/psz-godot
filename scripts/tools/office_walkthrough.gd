extends Node
## Physical smoke test for the raised office. Uses the real player and input.
## godot --headless --path . res://scenes/tools/office_walkthrough.tscn

var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "OfficeProbe")
	CharacterManager.set_active_slot(0)
	CharacterManager._sync_to_game_state()
	CityState.clear()
	SessionManager.reset_all_state()
	var office: Node3D = load("res://scenes/3d/city/city_office.tscn").instantiate()
	get_tree().root.add_child(office)
	await get_tree().create_timer(0.25).timeout
	var player: CharacterBody3D = office.player
	var camera := Camera3D.new()
	office.add_child(camera)
	camera.position = Vector3(0, 3, 8)
	camera.look_at(Vector3(0, 3, -5))
	camera.make_current()
	# Lower-floor start, then actual movement up the central stair.
	player.global_position = Vector3(0, 0.1, 1.4)
	player.player_rotation = PI
	for i in range(45):
		await get_tree().physics_frame
	# Player root is above its feet; compare against its settled lower-floor height.
	var grounded_y := player.global_position.y
	print("[office-walk] lower-floor root=%s" % grounded_y)
	_check(absf(_floor_height(office, Vector2(4, -5)) - 1.05) < 0.01, "side landing has a supporting floor")
	_check(absf(_floor_height(office, Vector2(0, -1.34)) - 0.525) < 0.01, "stairs have a continuous sloped floor")
	await _walk_to(player, "move_forward", -3.9, true)
	_check(player.global_position.z < -3.8, "player reaches desk landing")
	_check(absf(player.global_position.y - grounded_y - 1.05) < 0.12, "player stands on raised floor")
	_check(absf(office._principal_npc.global_position.y - 1.05) < 0.01, "Principal stands at landing height")
	_check(player.nearest_interactable == office._principal_npc, "Principal is reachable from the landing")
	# Confirm the real interaction still opens dialog, then dismiss it.
	player._try_interact()
	await get_tree().process_frame
	_check(player.current_state == player.PlayerState.CUTSCENE, "Principal interaction opens dialog")
	for i in range(5):
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = true
		Input.parse_input_event(event)
		await get_tree().create_timer(0.15).timeout
		event = InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = false
		Input.parse_input_event(event)
	_check(player.current_state != player.PlayerState.CUTSCENE, "dialog returns control to the player")
	player.player_rotation = 0.0
	await _walk_to(player, "move_backward", 1.4, false)
	_check(player.global_position.z > 1.3, "player descends stairs to entrance floor")
	_check(absf(player.global_position.y - grounded_y) < 0.12, "player returns to lower floor height")
	print("[office-walk] %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	office.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _walk_to(player: CharacterBody3D, action: String, target_z: float, forward: bool) -> void:
	Input.action_press(action)
	for i in range(360):
		await get_tree().physics_frame
		if (forward and player.global_position.z <= target_z) or (not forward and player.global_position.z >= target_z):
			break
	Input.action_release(action)
	for i in range(15):
		await get_tree().physics_frame
	print("[office-walk] position=%s" % player.global_position)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
	print("[office-walk] %s: %s" % ["PASS" if condition else "FAIL", label])


func _floor_height(office: Node3D, point: Vector2) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 4, point.y), Vector3(point.x, -1, point.y), 1)
	var hit := office.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else -100.0
