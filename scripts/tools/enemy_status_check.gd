extends RefCounted
## Rendered live regression: PSZ_TRAP_CHECK=1 PSZ_STATUS_CHECK=1 ... coliseum_probe.tscn
const Check := preload("res://scripts/tools/gameplay_recovery_check.gd")
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var tree := player.get_tree()
	await tree.create_timer(2.0).timeout
	player.set_physics_process(false)
	enemy.reveal()
	enemy.set_physics_process(true)
	enemy._spawn_lock = 0.0
	enemy.enemy_data = enemy.enemy_data.duplicate()
	enemy.enemy_data.hp_base = 1000
	enemy.current_hp = 1000
	var origin := player.global_position + Vector3(0, 0, -4)
	enemy.global_position = origin
	var camera := Camera3D.new()
	player.get_parent().add_child(camera)
	camera.global_position = origin + Vector3(5, 3, 7)
	camera.look_at(origin + Vector3.UP)
	camera.make_current()
	var ok := true
	for kind in ["burn", "freeze", "stun"]:
		enemy.global_position = origin
		enemy.apply_status_effect(kind)
		var hp := enemy.current_hp
		var at := enemy.global_position
		await tree.create_timer(0.5).timeout
		await _capture(tree, kind)
		await tree.create_timer(0.6).timeout
		if kind == "burn":
			ok = Check._check(enemy.current_hp <= hp - 50, "live burn removes maximum-HP damage") and ok
		else:
			ok = Check._check(enemy.global_position.distance_to(at) < 0.01, "live " + kind + " stops movement") and ok
			ok = Check._check(enemy.animation_player.speed_scale == 0.0, "live " + kind + " stops animation") and ok
			enemy._on_hit_received(1, Vector3.ZERO, 10000)
			await tree.create_timer(3.3).timeout
			ok = Check._check(enemy._is_immobilized and enemy.global_position.distance_to(at) < 0.01, "live " + kind + " survives attacks for healing window") and ok
		await tree.create_timer(5.0 if kind == "burn" else 0.8).timeout
		ok = Check._check(enemy._status_effects.is_empty() and not enemy._is_immobilized, "live " + kind + " expires") and ok
	CharacterManager.get_active_character().class_id = "hucast"
	PsoStartMenu.open()
	PsoStartMenu._mode = PsoStartMenu.Mode.PALETTE_PICK
	PsoStartMenu._canvas.queue_redraw()
	await _capture(tree, "palette")
	PsoStartMenu.close()
	return ok

static func _capture(tree: SceneTree, name: String) -> void:
	var folder := OS.get_environment("PSZ_GAMEPLAY_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join("status-" + name + ".png"))
