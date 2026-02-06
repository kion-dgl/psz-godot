extends HBoxContainer
## Terminal-style stat bar: "HP ██████░░░░ 82/100"

@export var stat_name: String = "HP"
@export var bar_width: int = 10
@export var current_value: int = 100
@export var max_value: int = 100
@export var fill_color: Color = Color(0, 1, 0.533)
@export var empty_color: Color = Color(0.333, 0.333, 0.333)

@onready var name_label: Label = $NameLabel
@onready var bar_label: Label = $BarLabel
@onready var value_label: Label = $ValueLabel


func _ready() -> void:
	update_bar()


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
