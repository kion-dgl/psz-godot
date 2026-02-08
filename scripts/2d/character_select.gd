extends Control
## Character selection screen — 4 character slots displayed in bordered panels.

const SLOT_COUNT := 4

var _current_slot: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var slots_container: HBoxContainer = $VBox/SlotsContainer
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "SELECT CHARACTER"
	hint_label.text = "[←/→] Navigate  [ENTER] Select  [DELETE] Delete  [ESC] Back"
	_refresh_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_current_slot = wrapi(_current_slot - 1, 0, SLOT_COUNT)
		_refresh_slots()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_current_slot = wrapi(_current_slot + 1, 0, SLOT_COUNT)
		_refresh_slots()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_slot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		_delete_slot()
		get_viewport().set_input_as_handled()


func _refresh_slots() -> void:
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(280, 180)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var style := StyleBoxFlat.new()
		style.bg_color = ThemeColors.BG_DARK
		style.border_color = ThemeColors.TEXT_HIGHLIGHT if i == _current_slot else ThemeColors.BORDER
		style.set_border_width_all(2 if i == _current_slot else 1)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)

		var slot_header := Label.new()
		slot_header.text = "Slot %d" % (i + 1)
		slot_header.modulate = ThemeColors.HEADER
		slot_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(slot_header)

		var character = CharacterManager.get_character(i)
		if character != null:
			var name_label := Label.new()
			name_label.text = character.get("name", "???")
			name_label.modulate = ThemeColors.TEXT_HIGHLIGHT if i == _current_slot else ThemeColors.TEXT_PRIMARY
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(name_label)

			var class_label := Label.new()
			class_label.text = character.get("class_id", "Unknown")
			class_label.modulate = ThemeColors.HEADER
			class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(class_label)

			var level_label := Label.new()
			level_label.text = "Level %d" % character.get("level", 1)
			level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(level_label)
		else:
			var empty_label := Label.new()
			empty_label.text = "\n[ Empty Slot ]"
			empty_label.modulate = ThemeColors.TEXT_DISABLED
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(empty_label)

		if i == _current_slot:
			var cursor := Label.new()
			cursor.text = "▲"
			cursor.modulate = ThemeColors.TEXT_HIGHLIGHT
			cursor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(cursor)

		panel.add_child(vbox)
		slots_container.add_child(panel)


func _select_slot() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character != null:
		CharacterManager.set_active_slot(_current_slot)
		SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
	else:
		SceneManager.goto_scene("res://scenes/2d/character_create.tscn", {"slot": _current_slot})


func _delete_slot() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character == null:
		return
	# TODO: Add confirm dialog before deletion
	CharacterManager.delete_character(_current_slot)
	_refresh_slots()
