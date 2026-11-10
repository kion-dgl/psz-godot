extends Control
## Direct-fire reticle and shared combo timing, visible without debug overlays.
var locked := false
var target_pixel := Vector2.ZERO
var combo: Dictionary = {"step": 0, "fraction": 0.0, "open": 0.0, "close": 0.0, "state": "FIRE"}

func set_combo(value: Dictionary) -> void:
	combo = value
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var state: String = combo.state
	var tint := Color(0.3, 1.0, 0.5) if state in ["CLICK", "QUEUED"] else Color(1.0, 0.45, 0.35) if state == "MISSED" else Color.WHITE
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 5, center + axis * 12, Color(0, 0, 0, 0.8), 4)
		draw_line(center + axis * 5, center + axis * 12, tint, 2)
	draw_circle(center, 1.5, tint)
	if locked:
		draw_arc(target_pixel, 20, 0, TAU, 32, Color(1.0, 0.8, 0.2), 2)
	var mode_text := "LOCKED  ·  Q release  ·  Tab switch" if locked else "SHOULDER AIM  ·  Z exit"
	draw_string(ThemeDB.fallback_font, center + Vector2(-110, -35), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)
	_draw_combo(center, tint)

func _draw_combo(center: Vector2, tint: Color) -> void:
	var step := int(combo.step)
	for index in range(3):
		var rect := Rect2(center + Vector2(-29 + index * 20, 23), Vector2(18, 5))
		draw_rect(rect.grow(1), Color(0, 0, 0, 0.85))
		draw_rect(rect, tint if index < step else Color(0.35, 0.35, 0.35))
	if step > 0:
		var bar := Rect2(center + Vector2(-45, 35), Vector2(90, 6))
		draw_rect(bar.grow(1), Color(0, 0, 0, 0.85))
		if step < 3:
			var start := float(combo.open)
			draw_rect(Rect2(bar.position + Vector2(90 * start, 0), Vector2(90 * maxf(0, float(combo.close) - start), 6)), Color(0.15, 0.55, 0.3))
		var marker := bar.position + Vector2(90 * clampf(float(combo.fraction), 0, 1), 0)
		draw_line(marker - Vector2(0, 2), marker + Vector2(0, 8), tint, 2)
	var text := "%d / 3  %s" % [step, combo.state] if step > 0 else "FIRE"
	var font := ThemeDB.fallback_font
	var point := center + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, 59)
	draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()
