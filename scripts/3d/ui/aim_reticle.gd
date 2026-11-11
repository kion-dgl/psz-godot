extends Control
## Aim marker only. Timing and recovery belong to the action palette.
var locked := false
var target_pixel := Vector2.ZERO
func _draw() -> void:
	var center := size * 0.5
	var tint := Color.WHITE
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 5, center + axis * 12, Color(0, 0, 0, 0.8), 4)
		draw_line(center + axis * 5, center + axis * 12, tint, 2)
	draw_circle(center, 1.5, tint)
	if locked:
		draw_arc(target_pixel, 20, 0, TAU, 32, Color(1.0, 0.8, 0.2), 2)
	var mode_text := "LOCKED  ·  Q release  ·  Tab switch" if locked else "SHOULDER AIM  ·  Z exit"
	draw_string(ThemeDB.fallback_font, center + Vector2(-110, -35), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()
