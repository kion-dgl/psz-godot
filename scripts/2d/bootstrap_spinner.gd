extends Control
## Bootstrap loader spinner — static white outer ring + two opposite 90° yellow
## arcs that rotate around the ring. Cloud icon lives as a sibling/child
## TextureRect in the scene and is toggled separately by bootstrap.gd based on
## phase (hidden during CONNECTING, shown once the link is "established").

@export var ring_diameter: float = 160.0
@export var border_width: float = 3.0
@export var spin_period_sec: float = 1.2

var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(ring_diameter, ring_diameter)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := Vector2(ring_diameter * 0.5, ring_diameter * 0.5)
	var radius := ring_diameter * 0.5 - border_width * 0.5
	# Static white outer ring (full circle)
	draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.4), border_width, true)
	# Two opposite 90° yellow arcs, rotating together
	var rot: float = _time * (TAU / spin_period_sec)
	var yellow := Color(0.992, 0.878, 0.278, 0.95)
	draw_arc(center, radius, rot, rot + PI * 0.5, 32, yellow, border_width, true)
	draw_arc(center, radius, rot + PI, rot + PI * 1.5, 32, yellow, border_width, true)
