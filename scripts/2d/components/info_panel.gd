extends PanelContainer
## Bordered panel with title bar and body text for item details, enemy info, etc.

@onready var title_label: Label = $VBox/TitleLabel
@onready var separator: Label = $VBox/Separator
@onready var body_label: RichTextLabel = $VBox/BodyLabel


func set_info(title: String, body: String) -> void:
	if not is_inside_tree():
		await ready
	title_label.text = "── %s ──" % title
	body_label.text = body
	separator.text = "─".repeat(maxi(title.length() + 6, 20))


func clear_info() -> void:
	if not is_inside_tree():
		await ready
	title_label.text = ""
	separator.text = ""
	body_label.text = ""
