extends RefCounted
## Post-build audio matrix. Run coliseum_probe.tscn with PSZ_SOUND_PROBE=1
## and PSZ_SOUND_PACK=/absolute/path/assets.pck. No character saves are written.

static func run(host: Node) -> bool:
	var pack := OS.get_environment("PSZ_SOUND_PACK")
	if pack.is_empty() or not ProjectSettings.load_resource_pack(pack):
		push_error("[enemy-sounds] asset pack required")
		return false
	var data := EnemySoundPlayback.catalogue()
	for info in data["sounds"].values():
		var stream := load(str(info["path"])) as AudioStreamWAV
		if stream == null or stream.get_length() <= 0.0:
			push_error("[enemy-sounds] missing packed sound: " + str(info["path"]))
			return false
	for id in ["helion", "hildegigas", "batt", "reyhound", "reyburn"]:
		if not await _check_enemy(host, str(id)):
			return false
	print("[enemy-sounds] DONE ok — 230 packed sounds; five live animation rigs")
	return true


static func _check_enemy(host: Node, id: String) -> bool:
	var enemy := EnemyBase.new()
	enemy.enemy_data = EnemyRegistry.get_enemy(id)
	host.add_child(enemy)
	enemy.set_physics_process(false)
	if enemy.animation_player == null or enemy._sound_playback == null:
		enemy.free()
		return false
	var before: int = SfxManager._next_3d_idx
	var clip := enemy._play_animation("tht" if id == "reyburn" else "dmg", true)
	await host.get_tree().create_timer(1.2 if id == "reyburn" else 0.35).timeout
	var played: bool = SfxManager._next_3d_idx != before
	print("[enemy-sounds] %s %s sound cue: %s" % [id, clip, "PASS" if played else "FAIL"])
	enemy.queue_free()
	await host.get_tree().process_frame
	return played
