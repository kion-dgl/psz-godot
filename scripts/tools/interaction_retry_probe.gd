extends "res://scripts/tools/probe_checks.gd"
## Entry: godot --headless --path . res://scripts/tools/interaction_retry_probe.tscn
## PSZ_INTERACT_MISS=1 deliberately misses and MUST exit 1 with a useful FAIL.
func _run() -> void:
	probe_label = "interaction-retry"
	get_tree().current_scene = null
	CharacterManager._characters.clear()
	CharacterManager._characters.resize(20)
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "RetryProbe")
	CharacterManager.set_active_slot(0)
	SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	var player: Node3D
	for frame in 600:
		await get_tree().physics_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	if not player:
		_check(false, "counter loads player")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.5).timeout
	var miss := OS.get_environment("PSZ_INTERACT_MISS") == "1"
	var recover := OS.get_environment("PSZ_INTERACT_RECOVER") == "1"
	Autopilot._teleport_player(Vector3(0, 100, 0) if miss or recover else Autopilot.COUNTER_NPC_POS)
	await get_tree().create_timer(0.8).timeout
	if recover:
		get_tree().create_timer(1.0).timeout.connect(func(): Autopilot._teleport_player(Autopilot.COUNTER_NPC_POS))
	await preload("res://scripts/tools/interaction_retry.gd").watch(Autopilot, Autopilot.GUILD_COUNTER)
	if miss:
		return # watch calls the real fail terminator, which has a quit grace period.
	_check(SceneManager._scene_stack.has(Autopilot.GUILD_COUNTER), "real guild interaction opens expected overlay")
	print("[interaction-retry] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
