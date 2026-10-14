extends Node3D
## Purple bubbles rise around the afflicted character until cured or expired.
const SOUND := "res://assets/sfx/player/poison.wav"
const SOUND_PAUSE := 0.6
var _sound: AudioStreamPlayer3D
var _sound_pause: Timer

func _ready() -> void:
	name = "PoisonEffect"
	_start_sound()
	var bubbles := CPUParticles3D.new()
	bubbles.amount = 16
	bubbles.lifetime = 1.5
	bubbles.preprocess = 0.5
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 0.4
	bubbles.position.y = 0.5
	bubbles.direction = Vector3.UP
	bubbles.spread = 12.0
	bubbles.gravity = Vector3.ZERO
	bubbles.initial_velocity_min = 0.5
	bubbles.initial_velocity_max = 1.0
	bubbles.scale_amount_min = 0.5
	bubbles.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 0.12, 0.85, 0.65)
	mesh.material = material
	bubbles.mesh = mesh
	add_child(bubbles)


func _start_sound() -> void:
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = SfxManager._load(SOUND)
	_sound.bus = "SFX"
	_sound.max_distance = 30.0
	add_child(_sound)
	_sound_pause = Timer.new()
	_sound_pause.one_shot = true
	_sound_pause.wait_time = SOUND_PAUSE
	add_child(_sound_pause)
	_sound.finished.connect(_sound_pause.start)
	_sound_pause.timeout.connect(_sound.play)
	if _sound.stream: _sound.play()

func stop_sound() -> void:
	if _sound_pause: _sound_pause.stop()
	if _sound: _sound.stop()
