extends Control
## Direct-fire reticle, distinct from enemy cone eligibility markers.
func _draw() -> void:
	var center := size * 0.5
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 5, center + axis * 12, Color(0, 0, 0, 0.8), 4)
		draw_line(center + axis * 5, center + axis * 12, Color.WHITE, 2)
	draw_circle(center, 1.5, Color.WHITE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()
