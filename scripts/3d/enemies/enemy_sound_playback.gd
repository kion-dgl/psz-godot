class_name EnemySoundPlayback extends Node3D
## ROM sound cues on private animation copies: speed changes, looping and
## interruption follow AnimationPlayer rather than independent wall timers.
## Action-dependent clips are excluded by gen_enemy_sounds.py, not guessed.

const DATA_PATH := "res://data/enemy_sounds.json"
const SOURCE_FPS := 60.0
static var _data: Dictionary = {}
static var _streams: Dictionary = {}

var _enemy: Node3D
var _player: AnimationPlayer
var _loops: Dictionary = {}
var _loop_clip := ""


static func catalogue() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


func bind(enemy: Node3D, player: AnimationPlayer, model_id: String) -> void:
	_enemy = enemy
	_player = player
	var clips: Dictionary = catalogue().get("models", {}).get(model_id, {})
	if clips.is_empty() or not is_instance_valid(player):
		set_process(false)
		return
	var animation_root := player.get_node(player.root_node)
	var callback_path := animation_root.get_path_to(self)
	# Imported libraries are shared between enemies. Never add instance-specific
	# callback paths or modify loop flags on the cached source resource.
	for library_name in player.get_animation_library_list():
		var source := player.get_animation_library(library_name)
		var library := AnimationLibrary.new()
		for clip_name in source.get_animation_list():
			var anim := source.get_animation(clip_name).duplicate() as Animation
			var full_name := str(clip_name) if library_name == &"" else str(library_name) + "/" + str(clip_name)
			var events: Array = clips.get(str(clip_name), [])
			if not events.is_empty():
				var track := anim.add_track(Animation.TYPE_METHOD)
				anim.track_set_path(track, callback_path)
				for event in events:
					var time := float(event["frame"]) / SOURCE_FPS
					if time <= anim.length:
						anim.track_insert_key(track, time, {"method": &"play_cue",
							"args": [str(event["sound"]), full_name]})
			library.add_animation(clip_name, anim)
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, library)
	player.animation_started.connect(_on_animation_started)


func _on_animation_started(clip: StringName) -> void:
	if _loop_clip != str(clip):
		stop_loops()


func _audible() -> bool:
	return is_instance_valid(_enemy) and _enemy.is_visible_in_tree() and not bool(_enemy.get("dormant")) and not bool(_enemy.get("_is_immobilized"))


func play_cue(symbol: String, clip: String) -> void:
	# Method tracks are deferred by default. Reject callbacks from an animation
	# that was interrupted before its queued call ran.
	if not _audible() or not is_instance_valid(_player) or _player.assigned_animation != clip or not _player.is_playing():
		return
	var info: Dictionary = catalogue().get("sounds", {}).get(symbol, {})
	if info.is_empty():
		return
	if int(info["loop_begin"]) < 0:
		SfxManager.play_at(str(info["path"]), global_position)
		return
	if _loop_clip != clip:
		stop_loops()
	_loop_clip = clip
	if _loops.has(symbol):
		return
	var stream := _loop_stream(info)
	if stream == null:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.bus = "SFX"
	voice.max_distance = 30.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	voice.stream = stream
	add_child(voice)
	_loops[symbol] = voice
	voice.play()


static func _loop_stream(info: Dictionary) -> AudioStreamWAV:
	var path := str(info["path"])
	if _streams.has(path):
		return _streams[path] as AudioStreamWAV
	var source := load(path) as AudioStreamWAV
	if source == null:
		return null
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = roundi(float(info["loop_begin"]) * stream.mix_rate / float(info["mix_rate"]))
	stream.loop_end = roundi(float(info["loop_end"]) * stream.mix_rate / float(info["mix_rate"]))
	_streams[path] = stream
	return stream


func _process(_delta: float) -> void:
	if not _loops.is_empty() and (not _audible() or not _player.is_playing() or _player.get_playing_speed() == 0.0 or _player.assigned_animation != _loop_clip):
		stop_loops()


func stop_loops() -> void:
	for voice in _loops.values():
		voice.stop()
		voice.queue_free()
	_loops.clear()
	_loop_clip = ""
