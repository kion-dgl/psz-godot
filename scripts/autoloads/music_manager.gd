extends Node
## MusicManager — Background music playback with crossfade transitions.
## Autoload that maps game areas to tracks and handles smooth transitions
## when the player moves between areas.

## Fade duration in seconds
const FADE_DURATION := 1.5
## Music volume (0.0 to 1.0)
var music_volume: float = 0.8

## Area variant → track key mapping.
## The area_id (e.g. "gurhacia") + variant (e.g. "a") combine to form the lookup key.
const AREA_TRACKS := {
	# City
	"city": "full_of_life",
	"office": "general",
	"teleporter": "flowing",
	"title": "phantasy_star_zero",
	"character_select": "precede",
	"character_create": "lets_go_together",

	# Gurhacia Valley
	"valley_a": "desolate_scape",
	"valley_b": "desolate_wilds",
	"valley_z": "growl_from_the_red_beat",

	# Ozette Wetlands
	"wetlands_a": "damp_swamp",
	"wetlands_b": "damp_clump",
	"wetlands_z": "chaotic_swells",

	# Rioh Snowfield
	"snowfield_a": "snowflake",
	"snowfield_b": "snowstorm",
	"snowfield_z": "rush_to_struggle",

	# Paru Forgotten City
	"paru_a": "secret_alter",
	"paru_b": "secret_ritual",
	"paru_z": "machinery_pressure",

	# Makara Ruins
	"makara_a": "trickle_maze",
	"makara_b": "trickle_labyrinth",
	"makara_z": "rush_to_struggle",

	# Arca Plant
	"arca_a": "overflow",
	"arca_b": "overdrive",
	"arca_z": "machinery_conqueror",

	# Dark Shrine
	"shrine_a": "crescent_serenade",
	"shrine_b": "crescent_crusade",
	"shrine_z": "idola_the_imitated_god",
}

## Track key → file path mapping
const TRACK_FILES := {
	"phantasy_star_zero": "res://assets/music/phantasy_star_zero.ogg",
	"precede": "res://assets/music/precede.ogg",
	"lets_go_together": "res://assets/music/lets_go_together.ogg",
	"full_of_life": "res://assets/music/full_of_life.ogg",
	"general": "res://assets/music/general.ogg",
	"flowing": "res://assets/music/flowing.ogg",
	"desolate_scape": "res://assets/music/desolate_scape.ogg",
	"desolate_wilds": "res://assets/music/desolate_wilds.ogg",
	"growl_from_the_red_beat": "res://assets/music/growl_from_the_red_beat.ogg",
	"damp_swamp": "res://assets/music/damp_swamp.ogg",
	"damp_clump": "res://assets/music/damp_clump.ogg",
	"chaotic_swells": "res://assets/music/chaotic_swells.ogg",
	"snowflake": "res://assets/music/snowflake.ogg",
	"snowstorm": "res://assets/music/snowstorm.ogg",
	"rush_to_struggle": "res://assets/music/rush_to_struggle.ogg",
	"secret_alter": "res://assets/music/secret_alter.ogg",
	"secret_ritual": "res://assets/music/secret_ritual.ogg",
	"machinery_pressure": "res://assets/music/machinery_pressure.ogg",
	"trickle_maze": "res://assets/music/trickle_maze.ogg",
	"trickle_labyrinth": "res://assets/music/trickle_labyrinth.ogg",
	"overflow": "res://assets/music/overflow.ogg",
	"overdrive": "res://assets/music/overdrive.ogg",
	"machinery_conqueror": "res://assets/music/machinery_conqueror.ogg",
	"crescent_serenade": "res://assets/music/crescent_serenade.ogg",
	"crescent_crusade": "res://assets/music/crescent_crusade.ogg",
	"idola_the_imitated_god": "res://assets/music/idola_the_imitated_god.ogg",
	"idola_the_devils_shadow": "res://assets/music/idola_the_devils_shadow.ogg",
}

## Map area_id to folder name for track lookup
const AREA_FOLDERS := {
	"gurhacia": "valley",
	"ozette": "wetlands",
	"rioh": "snowfield",
	"paru": "paru",
	"makara": "makara",
	"arca": "arca",
	"dark": "shrine",
	"tower": "tower",
}

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _current_track: String = ""
var _stream_cache: Dictionary = {}


func _ready() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.bus = "Music"
	_player_a.name = "MusicA"
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.bus = "Music"
	_player_b.name = "MusicB"
	add_child(_player_b)

	_active_player = _player_a

	# Create Music bus if it doesn't exist
	if AudioServer.get_bus_index("Music") == -1:
		var bus_idx: int = AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "Music")
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(music_volume))


## Play music for a field area. Called by valley_field_controller on cell load.
## area_id: e.g. "gurhacia", "ozette"
## variant: e.g. "a", "b", "e", "z" (from section.area)
func play_field_music(area_id: String, variant: String) -> void:
	var folder: String = AREA_FOLDERS.get(area_id, "")
	if folder.is_empty():
		return
	# Transition areas ("e") use the same track as "a"
	var lookup_variant: String = variant
	if variant == "e":
		lookup_variant = "a"
	var key: String = "%s_%s" % [folder, lookup_variant]
	var track: String = AREA_TRACKS.get(key, "")
	if not track.is_empty():
		_play_track(track)


## Play music for a named location (city, office, teleporter, title).
func play_location_music(location: String) -> void:
	var track: String = AREA_TRACKS.get(location, "")
	if not track.is_empty():
		_play_track(track)


## Stop music with a fade out.
func stop() -> void:
	if _active_player.playing:
		var tw := create_tween()
		tw.tween_property(_active_player, "volume_db", -40.0, FADE_DURATION)
		tw.tween_callback(func():
			_active_player.stop()
			_current_track = ""
		)


func _play_track(track_key: String) -> void:
	if track_key == _current_track:
		return  # Already playing

	var path: String = TRACK_FILES.get(track_key, "")
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		print("[MusicManager] Track not found: %s" % path)
		return

	# Load or fetch from cache
	var stream: AudioStream
	if _stream_cache.has(track_key):
		stream = _stream_cache[track_key]
	else:
		stream = load(path) as AudioStream
		if not stream:
			print("[MusicManager] Failed to load: %s" % path)
			return
		# Enable looping for music tracks
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_stream_cache[track_key] = stream

	# Crossfade: fade out active, fade in inactive
	var old_player := _active_player
	var new_player := _player_b if _active_player == _player_a else _player_a

	new_player.stream = stream
	new_player.volume_db = -40.0
	new_player.play()

	var tw := create_tween()
	tw.set_parallel(true)
	if old_player.playing:
		tw.tween_property(old_player, "volume_db", -40.0, FADE_DURATION)
	tw.tween_property(new_player, "volume_db", 0.0, FADE_DURATION)
	tw.set_parallel(false)
	tw.tween_callback(func():
		old_player.stop()
	)

	_active_player = new_player
	_current_track = track_key
	print("[MusicManager] Now playing: %s" % track_key)
