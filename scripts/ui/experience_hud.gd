extends Control
## Progress within the current level; PB retains its separate yellow rim.
var _flash := 0.0
var _progress: Dictionary = {}

func _ready() -> void:
	position = Vector2(76, 112)
	size = Vector2(160, 21)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	CharacterManager.level_up.connect(_level_changed)
	CharacterManager.active_character_changed.connect(_character_changed)

func _level_changed(_level: int) -> void:
	_flash = 1.5

func _character_changed(_slot: int) -> void:
	_flash = 0.0

func _process(delta: float) -> void:
	var next := CharacterManager.get_exp_progress()
	var redraw := _flash > 0.0 or next != _progress
	_flash = maxf(0.0, _flash - delta)
	_progress = next
	if redraw: queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var maxed := bool(_progress.get("maxed", false))
	var caption := "EXP MAX" if maxed else "EXP %d / %d" % [int(_progress.get("current", 0)), int(_progress.get("needed", 0))]
	if _flash > 0.0: caption = "LEVEL UP!"
	draw_rect(Rect2(0, 0, 160, 4), Color(0.08, 0.12, 0.18, 0.95))
	draw_rect(Rect2(0, 0, 160 * float(_progress.get("percent", 0.0)), 4), Color(0.35, 0.9, 0.8))
	draw_string(font, Vector2(0, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color.WHITE if _flash == 0.0 else Color(1, 0.95, 0.35))
