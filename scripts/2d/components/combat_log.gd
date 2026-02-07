extends PanelContainer
## Scrolling combat text log with color-coded messages.

const COLOR_NORMAL := Color(0, 1, 0.533)
const COLOR_DAMAGE := Color(1, 0.267, 0.267)
const COLOR_HEAL := Color(0.267, 1, 0.267)
const COLOR_INFO := Color(0, 0.733, 0.8)
const COLOR_LOOT := Color(1, 0.8, 0)

@onready var scroll: ScrollContainer = $Scroll
@onready var log_label: RichTextLabel = $Scroll/LogLabel

var _max_lines: int = 100


func _ready() -> void:
	log_label.text = ""


func add_message(text: String, color: Color = COLOR_NORMAL) -> void:
	var hex := color.to_html(false)
	log_label.append_text("[color=#%s]%s[/color]\n" % [hex, text])
	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


func add_damage(text: String) -> void:
	add_message(text, COLOR_DAMAGE)


func add_heal(text: String) -> void:
	add_message(text, COLOR_HEAL)


func add_info(text: String) -> void:
	add_message(text, COLOR_INFO)


func add_loot(text: String) -> void:
	add_message(text, COLOR_LOOT)


func clear_log() -> void:
	log_label.clear()
