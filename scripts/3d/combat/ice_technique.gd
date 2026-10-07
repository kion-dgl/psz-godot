class_name IceTechnique
extends Node3D
## Shared player/enemy ice delivery profiles. Enemy casts keep their authored
## damage/range and one resolution per target across the whole fan.

static func profile(technique: String) -> Dictionary:
	match technique:
		"barta": return {"speed": 20.0, "range": 15.0, "waves": 1, "angles": [0.0], "interval": 0.15, "color": Color(0.3, 0.7, 1.0)}
		"gibarta": return {"speed": 18.0, "range": 10.0, "waves": 3, "angles": [-0.12, 0.0, 0.12], "interval": 0.15, "color": Color(0.3, 0.7, 1.0)}
	return {}

var technique_id := "barta"
var direction := Vector3.FORWARD
var target: Node3D
var damage := 1
var max_range := 10.0
var _elapsed := 0.0
var _waves := 0
var _budget := {}

func _physics_process(delta: float) -> void:
	var p := profile(technique_id)
	if p.is_empty():
		queue_free()
		return
	_elapsed += delta
	while _waves < int(p.waves) and _elapsed >= _waves * float(p.interval):
		_emit_wave(p)
		_waves += 1
	if _waves >= int(p.waves):
		queue_free()

func _emit_wave(p: Dictionary) -> void:
	for angle in p.angles:
		var bolt := EnemyProjectile.new()
		bolt.dir = direction.rotated(Vector3.UP, float(angle))
		bolt.speed = float(p.speed)
		bolt.max_range = max_range
		bolt.damage = damage
		bolt.target = target
		bolt.color = p.color
		bolt.technique_id = technique_id
		bolt.hit_budget = _budget
		get_parent().add_child(bolt)
		bolt.global_position = global_position
