extends CanvasLayer
## Field HUD — shows player stats (HP/PP bars, level, name) top-left,
## meseta below, and hosts the room minimap (always visible).

const MARGIN := 12.0

var _stats_panel: Control
var _meseta_label: Control

# Cached character info (static for session)
var _char_name: String = ""
var _char_level: int = 1


func _ready() -> void:
	layer = 99
	name = "FieldHud"

	var ch = CharacterManager.get_active_character()
	if ch:
		_char_name = str(ch.get("name", ""))
		_char_level = int(ch.get("level", 1))

	_stats_panel = _StatsPanel.new()
	_stats_panel.char_name = _char_name
	_stats_panel.char_level = _char_level
	add_child(_stats_panel)

	_meseta_label = _MesetaLabel.new()
	add_child(_meseta_label)

	GameState.hp_changed.connect(_on_stats_changed)
	GameState.max_hp_changed.connect(_on_stats_changed)
	GameState.mp_changed.connect(_on_stats_changed)
	GameState.max_mp_changed.connect(_on_stats_changed)
	GameState.meseta_changed.connect(_on_meseta_changed)


func _on_stats_changed(_value: int) -> void:
	_stats_panel.queue_redraw()


func _on_meseta_changed(_value: int) -> void:
	_meseta_label.queue_redraw()


# ── Stats Panel (top-left) ───────────────────────────────────────────────────

class _StatsPanel extends Control:
	const PANEL_W := 220.0
	const PANEL_H := 72.0
	const BAR_W := 120.0
	const BAR_H := 8.0
	const FONT_SIZE_MAIN := 13
	const FONT_SIZE_SMALL := 11

	const BG_COLOR := Color(0.08, 0.08, 0.15, 0.8)
	const BORDER_COLOR := Color(0.4, 0.4, 0.5, 0.5)
	const HP_GREEN := Color(0.2, 0.9, 0.2)
	const HP_YELLOW := Color(0.9, 0.9, 0.2)
	const HP_RED := Color(0.9, 0.2, 0.2)
	const PP_COLOR := Color(0.3, 0.7, 1.0)
	const BAR_BG := Color(0.15, 0.15, 0.2)
	const LABEL_GREEN := Color(0.5, 1.0, 0.5)
	const LABEL_CYAN := Color(0.5, 0.9, 1.0)
	const STAR_YELLOW := Color(1.0, 0.9, 0.3)
	const NAME_WHITE := Color(1.0, 1.0, 1.0, 0.9)
	const VALUE_WHITE := Color(0.9, 0.9, 0.9)

	var char_name: String = ""
	var char_level: int = 1

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		position = Vector2(MARGIN, MARGIN)
		size = Vector2(PANEL_W, PANEL_H)
		custom_minimum_size = size

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var hp: int = GameState.hp
		var max_hp: int = GameState.max_hp
		var pp: int = GameState.mp
		var max_pp: int = GameState.max_mp

		# Background
		var rect := Rect2(Vector2.ZERO, Vector2(PANEL_W, PANEL_H))
		draw_rect(rect, BG_COLOR)
		# Border
		draw_rect(rect, BORDER_COLOR, false, 1.0)

		var pad := 8.0
		var y := pad + 12.0  # baseline for first line

		# Line 1: ★Lv N              Name
		var lv_text := "Lv %d" % char_level
		draw_string(font, Vector2(pad, y), "\u2605", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN, STAR_YELLOW)
		var star_w: float = font.get_string_size("\u2605", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN).x
		draw_string(font, Vector2(pad + star_w, y), lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN, STAR_YELLOW)
		var name_w: float = font.get_string_size(char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN).x
		draw_string(font, Vector2(PANEL_W - pad - name_w, y), char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN, NAME_WHITE)

		y += 18.0

		# Line 2: HP bar
		_draw_stat_bar(font, Vector2(pad, y), "HP", hp, max_hp, true)

		y += 16.0

		# Line 3: PP bar
		_draw_stat_bar(font, Vector2(pad, y), "PP", pp, max_pp, false)

	func _draw_stat_bar(font: Font, pos: Vector2, label: String, current: int, maximum: int, is_hp: bool) -> void:
		var label_color: Color = LABEL_GREEN if is_hp else LABEL_CYAN
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, label_color)

		var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL).x
		var bar_x: float = pos.x + label_w + 6.0
		var bar_y: float = pos.y - BAR_H  # bars draw downward from top

		# Bar background
		draw_rect(Rect2(bar_x, bar_y, BAR_W, BAR_H), BAR_BG)

		# Bar fill
		var pct: float = float(current) / float(maximum) if maximum > 0 else 0.0
		var fill_w: float = BAR_W * clampf(pct, 0.0, 1.0)
		var fill_color: Color
		if is_hp:
			if pct > 0.5:
				fill_color = HP_GREEN
			elif pct > 0.25:
				fill_color = HP_YELLOW
			else:
				fill_color = HP_RED
		else:
			fill_color = PP_COLOR
		if fill_w > 0:
			draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_H), fill_color)

		# Numeric value right-aligned
		var val_text := "%d/%d" % [current, maximum]
		var val_w: float = font.get_string_size(val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL).x
		draw_string(font, Vector2(PANEL_W - 8.0 - val_w, pos.y), val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, VALUE_WHITE)


# ── Meseta Label (below stats) ───────────────────────────────────────────────

class _MesetaLabel extends Control:
	const FONT_SIZE := 12
	const MESETA_COLOR := Color(1.0, 0.85, 0.3)

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		position = Vector2(MARGIN, MARGIN + 72.0 + 4.0)
		size = Vector2(220, 20)
		custom_minimum_size = size

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var meseta: int = GameState.meseta
		var text := "M %s" % _format_meseta(meseta)
		draw_string(font, Vector2(8.0, 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MESETA_COLOR)

	func _format_meseta(value: int) -> String:
		var s := str(value)
		if s.length() <= 3:
			return s
		var result := ""
		var count := 0
		for i in range(s.length() - 1, -1, -1):
			if count > 0 and count % 3 == 0:
				result = "," + result
			result = s[i] + result
			count += 1
		return result
