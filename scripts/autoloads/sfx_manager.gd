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


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream:
		_cache[path] = stream
	return stream
