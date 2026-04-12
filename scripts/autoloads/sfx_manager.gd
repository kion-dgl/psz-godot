extends Node
## SfxManager — Sound effect playback with pooled AudioStreamPlayers.
## Autoload that provides fire-and-forget SFX with volume control via the SFX bus.

const POOL_SIZE := 8
var sfx_volume: float = 0.5

var _pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_idx: int = 0
var _next_3d_idx: int = 0
var _cache: Dictionary = {}


func _ready() -> void:
	var bus_idx: int = AudioServer.get_bus_index("SFX")
	if bus_idx == -1:
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "SFX")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(sfx_volume))

	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.name = "SFX2D_%d" % i
		add_child(player)
		_pool.append(player)

	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.name = "SFX3D_%d" % i
		player.max_distance = 30.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_pool_3d.append(player)


## Play a 2D sound effect (UI, menu, global sounds).
func play(path: String, volume_db: float = 0.0) -> void:
	var stream := _load(path)
	if not stream:
		return
	var player := _pool[_next_idx]
	_next_idx = (_next_idx + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Play a 3D positional sound effect at a world position.
func play_at(path: String, position: Vector3, volume_db: float = 0.0) -> void:
	var stream := _load(path)
	if not stream:
		return
	var player := _pool_3d[_next_3d_idx]
	_next_3d_idx = (_next_3d_idx + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.global_position = position
	player.play()


## Play a random file matching a glob pattern, e.g. "res://assets/sfx/weapons/saber_swing_*.wav"
func play_random(base_path: String, volume_db: float = 0.0) -> void:
	var files := _glob_cache(base_path)
	if files.is_empty():
		return
	play(files[randi() % files.size()], volume_db)


## Play a random file at a 3D position.
func play_random_at(base_path: String, position: Vector3, volume_db: float = 0.0) -> void:
	var files := _glob_cache(base_path)
	if files.is_empty():
		return
	play_at(files[randi() % files.size()], position, volume_db)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream:
		_cache[path] = stream
	return stream


var _glob_results: Dictionary = {}

func _glob_cache(pattern: String) -> Array:
	if _glob_results.has(pattern):
		return _glob_results[pattern]

	var last_slash: int = pattern.rfind("/")
	if last_slash == -1 or not pattern.contains("*"):
		_glob_results[pattern] = []
		return []

	var dir_path: String = pattern.substr(0, last_slash)
	var file_pattern: String = pattern.substr(last_slash + 1)
	var star_pos: int = file_pattern.find("*")
	var prefix: String = file_pattern.substr(0, star_pos)
	var suffix: String = file_pattern.substr(star_pos + 1)

	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.begins_with(prefix) and fname.ends_with(suffix):
				files.append("%s/%s" % [dir_path, fname])
			fname = dir.get_next()
		dir.list_dir_end()
	files.sort()
	_glob_results[pattern] = files
	return files
