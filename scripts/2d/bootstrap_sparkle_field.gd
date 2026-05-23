extends Control
## Procedural sparkle field for the bootstrap loader — 32 white twinkles at
## random positions, each pulsing on its own time offset. Drawn procedurally
## (no texture file) so the bootstrap can render before the asset pack is
## mounted — see res://scripts/2d/bootstrap.gd for the same constraint.

const COUNT := 32

var _sparkles: Array = []
var _time: float = 0.0


func _ready() -> void:
	_generate()
	resized.connect(_generate)
	set_process(true)


func _generate() -> void:
	_sparkles.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in COUNT:
		_sparkles.append({
			"pos": Vector2(rng.randf() * size.x, rng.randf() * size.y),
			"base": 3.0 + rng.randf() * 6.0,
			"offset": rng.randf() * 3.0,
			"duration": 2.2 + rng.randf() * 1.8,
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for s in _sparkles:
		var t: float = fposmod(_time + float(s.offset), float(s.duration)) / float(s.duration)
		# Smooth pulse: peak at t=0.5, ease in/out
		var raw: float = 1.0 - abs(t * 2.0 - 1.0)
		var pulse: float = raw * raw * (3.0 - 2.0 * raw)
		var alpha: float = lerp(0.2, 1.0, pulse)
		var sc: float = lerp(0.7, 1.4, pulse)
		var radius: float = float(s.base) * sc * 0.5
		draw_circle(Vector2(s.pos), radius, Color(1.0, 1.0, 1.0, alpha))
