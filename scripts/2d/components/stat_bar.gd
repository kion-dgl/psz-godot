extends HBoxContainer
## Graphical stat bar with label, colored fill, and value display.

@export var stat_name: String = "HP"
@export var bar_width: int = 10
@export var current_value: int = 100
@export var max_value: int = 100
@export var fill_color: Color = ThemeColors.HP_BAR
@export var bg_color: Color = ThemeColors.HP_BAR_BG
@export var danger_threshold: float = 0.25
@export var show_danger_color: bool = true

@onready var name_label: Label = $NameLabel
@onready var bar_label: Label = $BarLabel
@onready var value_label: Label = $ValueLabel

var _flash_timer: float = 0.0
var _flash_on: bool = false


func _ready() -> void:
	update_bar()


func _process(delta: float) -> void:
	if not show_danger_color or max_value == 0:
		return
	var ratio := clampf(float(current_value) / float(max_value), 0.0, 1.0)
	if ratio > 0.0 and ratio <= danger_threshold:
		_flash_timer += delta
		if _flash_timer >= 0.4:
			_flash_timer = 0.0
			_flash_on = not _flash_on
			_apply_bar_color()
	elif _flash_on:
		_flash_on = false
		_flash_timer = 0.0
		_apply_bar_color()


func set_values(current: int, maximum: int) -> void:
	current_value = current
	max_value = maximum
	update_bar()


func update_bar() -> void:
	if not is_inside_tree():
		return
	name_label.text = stat_name
	var ratio := 0.0
	if max_value > 0:
		ratio = clampf(float(current_value) / float(max_value), 0.0, 1.0)
	var filled := int(ratio * bar_width)
	var empty := bar_width - filled
	bar_label.text = "█".repeat(filled) + "░".repeat(empty)
	value_label.text = "%d/%d" % [current_value, max_value]
	_apply_bar_color()


func _apply_bar_color() -> void:
	if not is_inside_tree():
		return
	var ratio := 0.0
	if max_value > 0:
		ratio = clampf(float(current_value) / float(max_value), 0.0, 1.0)
	var color: Color
	if show_danger_color and ratio > 0.0 and ratio <= danger_threshold:
		color = ThemeColors.DANGER if _flash_on else fill_color
	else:
		color = fill_color

	var settings := LabelSettings.new()
	settings.font_color = color
	bar_label.label_settings = settings

	var name_settings := LabelSettings.new()
	name_settings.font_color = ThemeColors.HEADER_TEXT
	name_settings.font_size = 14
	name_label.label_settings = name_settings

	var val_settings := LabelSettings.new()
	val_settings.font_color = ThemeColors.HINT_TEXT
	val_settings.font_size = 14
	value_label.label_settings = val_settings
