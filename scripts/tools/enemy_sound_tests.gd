extends RefCounted

class SoundEnemy extends Node3D:
	var dormant := false
	var _is_immobilized := false


static func run(r: Node) -> void:
	print("── Enemy animation sound events ──")
	var data := EnemySoundPlayback.catalogue()
	var lion: Dictionary = data["models"]["lion"]
	r.assert_eq(lion["b_004_atk"][0]["frame"], 5, "Helion attack uses authored frame 5")
	r.assert_eq(lion["b_004_atk"][1]["frame"], 45, "Helion landing uses authored frame 45")
	r.assert_true(not data["models"]["snake"].has("m_003_wat1"), "ambiguous snake idle/appearance cues excluded")
	r.assert_true(not data["models"].has("pso_booma"), "PSO model never inherits PSZ Booma sounds")
	r.assert_eq(data["models"]["gorilla"]["b_014_dmg"][0]["sound"], "SE_ENEMY_GORILLA_DAMAGE", "Gorilla uses event archive 11, not config word 10")
	_test_timeline(r, data)
	_test_imported(r)


static func _test_timeline(r: Node, data: Dictionary) -> void:
	# CI deliberately has no downloaded assets. Exercise the real audio path
	# with a tiny local WAV resource; imported-model checks run when available.
	var original_sounds: Dictionary = data["sounds"].duplicate(true)
	var fixture := AudioStreamWAV.new()
	fixture.format = AudioStreamWAV.FORMAT_16_BITS
	fixture.mix_rate = 44100
	var pcm := PackedByteArray()
	pcm.resize(88200)
	fixture.data = pcm
	var fixture_path := "user://enemy_sound_test_fixture.tres"
	ResourceSaver.save(fixture, fixture_path)
	for info in data["sounds"].values():
		info["path"] = fixture_path
	var enemy := SoundEnemy.new()
	r.add_child(enemy)
	var player := AnimationPlayer.new()
	enemy.add_child(player)
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var library := AnimationLibrary.new()
	var attack := Animation.new()
	attack.length = 1.5
	library.add_animation("b_004_atk", attack)
	var walk := Animation.new()
	walk.length = 1.5
	walk.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("b_004_wlk", walk)
	player.add_animation_library("", library)
	var sounds := EnemySoundPlayback.new()
	enemy.add_child(sounds)
	sounds.bind(enemy, player, "lion")
	r.assert_eq(attack.get_track_count(), 0, "source animation stays untouched")
	r.assert_true(player.get_animation("b_004_atk") != attack, "enemy owns private animation copy")
	var before: int = SfxManager._next_3d_idx
	player.play("b_004_atk")
	player.advance(0.05)
	r.assert_eq(SfxManager._next_3d_idx, before, "no cue before frame crossing")
	player.advance(0.05)
	r.assert_eq(SfxManager._next_3d_idx, (before + 1) % SfxManager.POOL_SIZE, "method track plays attack at crossed frame")
	player.advance(0.7)
	r.assert_eq(SfxManager._next_3d_idx, (before + 2) % SfxManager.POOL_SIZE, "large step still catches landing cue")
	player.play("b_004_wlk")
	player.advance(0.1)
	before = SfxManager._next_3d_idx
	sounds.play_cue("SE_ENEMY_LION_ATTACK", "b_004_atk")
	r.assert_eq(SfxManager._next_3d_idx, before, "interrupted deferred cue is rejected")
	player.advance(0.7)
	player.advance(0.8)
	r.assert_eq(SfxManager._next_3d_idx, (before + 2) % SfxManager.POOL_SIZE, "walking cues cross loop boundary once")
	enemy.dormant = true
	before = SfxManager._next_3d_idx
	player.play("b_004_atk")
	player.advance(0.1)
	r.assert_eq(SfxManager._next_3d_idx, before, "dormant enemy is silent")
	enemy.dormant = false
	_test_loop_lifetime(r, sounds, player, data)
	enemy.free()
	data["sounds"] = original_sounds
	SfxManager._cache.erase(fixture_path)
	EnemySoundPlayback._streams.erase(fixture_path)
	DirAccess.remove_absolute(fixture_path)


static func _test_loop_lifetime(r: Node, sounds: EnemySoundPlayback, player: AnimationPlayer, data: Dictionary) -> void:
	# Exercise continuous sound lifetime and sample-exact loop boundaries.
	sounds.play_cue("SE_ENEMY_SNAKE_WALK", "b_004_atk")
	r.assert_eq(sounds._loops.size(), 1, "loop voice starts once")
	sounds.play_cue("SE_ENEMY_SNAKE_WALK", "b_004_atk")
	r.assert_eq(sounds._loops.size(), 1, "repeated cue does not stack loop voices")
	var voice: AudioStreamPlayer3D = sounds._loops["SE_ENEMY_SNAKE_WALK"]
	var stream := voice.stream as AudioStreamWAV
	r.assert_eq(stream.loop_begin, int(data["sounds"]["SE_ENEMY_SNAKE_WALK"]["loop_begin"]), "loop uses exact exported sample start")
	player.play("b_004_wlk")
	r.assert_eq(sounds._loops.size(), 0, "clip interruption releases sustained voice")
	sounds.play_cue("SE_ENEMY_SNAKE_WALK", "b_004_wlk")
	player.pause()
	sounds._process(0.0)
	r.assert_eq(sounds._loops.size(), 0, "pausing animation stops sustained voice")


static func _test_imported(r: Node) -> void:
	for id in ["helion", "hildegigas", "reyburn"]:
		var actual := EnemyBase.new()
		actual.enemy_data = EnemyRegistry.get_enemy(id)
		if not ResourceLoader.exists(actual.enemy_data.get_model_path()):
			actual.free()
			continue
		r.add_child(actual)
		actual.set_physics_process(false)
		r.assert_true(actual._sound_playback != null, id + " attaches sound controller")
		var death := actual._play_animation("ded", true)
		r.assert_true(not death.is_empty(), id + " resolves imported death clip")
		var has_sound_track := false
		if not death.is_empty():
			var animation := actual.animation_player.get_animation(death)
			for track in animation.get_track_count():
				if animation.track_get_type(track) == Animation.TYPE_METHOD:
					has_sound_track = true
		r.assert_true(has_sound_track, id + " imported death clip carries sound cues")
		actual.free()
