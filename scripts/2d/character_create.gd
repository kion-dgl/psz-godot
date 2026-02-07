extends Control
## Character creation screen — class selection, name entry, confirmation.

enum Step { CLASS_SELECT, NAME_ENTRY, CONFIRM }

var _step: int = Step.CLASS_SELECT
var _slot: int = 0
var _class_list: Array = []
var _selected_class_index: int = 0
var _selected_class_id: String = ""
var _char_name: String = ""

@onready var title_label: Label = $VBox/TitleLabel
@onready var content_panel: PanelContainer = $VBox/HBox/ContentPanel
@onready var info_panel: PanelContainer = $VBox/HBox/InfoPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	_slot = SceneManager.get_transition_data().get("slot", 0)
	title_label.text = "── CREATE CHARACTER (Slot %d) ──" % (_slot + 1)
	_load_classes()
	_show_class_select()


func _load_classes() -> void:
	_class_list = ClassRegistry.get_all_classes()
	# Sort by type (Hunter, Ranger, Force), then gender (Male, Female), then race
	var type_order := {"Hunter": 0, "Ranger": 1, "Force": 2}
	var gender_order := {"Male": 0, "Female": 1}
	var race_order := {"Human": 0, "Newman": 1, "Cast": 2}
	_class_list.sort_custom(func(a, b):
		var ta: int = type_order.get(a.type, 9)
		var tb: int = type_order.get(b.type, 9)
		if ta != tb: return ta < tb
		var ga: int = gender_order.get(a.gender, 9)
		var gb: int = gender_order.get(b.gender, 9)
		if ga != gb: return ga < gb
		var ra: int = race_order.get(a.race, 9)
		var rb: int = race_order.get(b.race, 9)
		return ra < rb
	)


func _unhandled_input(event: InputEvent) -> void:
	match _step:
		Step.CLASS_SELECT:
			_handle_class_select_input(event)
		Step.NAME_ENTRY:
			pass  # LineEdit handles its own input
		Step.CONFIRM:
			_handle_confirm_input(event)


func _handle_class_select_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_class_index = wrapi(_selected_class_index - 1, 0, _class_list.size())
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_class_index = wrapi(_selected_class_index + 1, 0, _class_list.size())
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_selected_class_id = _class_list[_selected_class_index].id
		_show_name_entry()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")
		get_viewport().set_input_as_handled()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_create_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_show_name_entry()
		get_viewport().set_input_as_handled()


func _show_class_select() -> void:
	_step = Step.CLASS_SELECT
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Back"
	_update_class_select()


func _update_class_select() -> void:
	# Content panel: class list
	for child in content_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var last_type := ""
	for i in range(_class_list.size()):
		var cls = _class_list[i]
		# Add type header when group changes
		if cls.type != last_type:
			if not last_type.is_empty():
				var spacer := Label.new()
				spacer.text = ""
				vbox.add_child(spacer)
			var type_header := Label.new()
			type_header.text = "── %s ──" % cls.type
			type_header.modulate = Color(0, 0.733, 0.8)
			vbox.add_child(type_header)
			last_type = cls.type
		var label := Label.new()
		if i == _selected_class_index:
			label.text = "> %-12s %s %s" % [cls.name, cls.race, cls.gender]
			label.modulate = Color(1, 0.8, 0)
		else:
			label.text = "  %-12s %s %s" % [cls.name, cls.race, cls.gender]
		vbox.add_child(label)

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	# Info panel: selected class details
	_update_class_info()


func _update_class_info() -> void:
	for child in info_panel.get_children():
		child.queue_free()

	if _class_list.is_empty():
		return

	var cls = _class_list[_selected_class_index]
	var stats: Dictionary = cls.get_stats_at_level(1)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % cls.name
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = "%s %s %s" % [cls.race, cls.gender, cls.type]
	desc_label.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(desc_label)

	var sep := Label.new()
	sep.text = "────────────────────"
	sep.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(sep)

	# Stats at level 1
	for stat_name in ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]:
		var stat_label := Label.new()
		var display_name: String = stat_name.to_upper().substr(0, 3) if stat_name.length() > 3 else stat_name.to_upper()
		if stat_name == "technique":
			display_name = "TEC"
		elif stat_name == "accuracy":
			display_name = "ACC"
		elif stat_name == "evasion":
			display_name = "EVA"
		elif stat_name == "defense":
			display_name = "DEF"
		elif stat_name == "attack":
			display_name = "ATK"
		stat_label.text = "  %-4s %d" % [display_name, stats.get(stat_name, 0)]
		vbox.add_child(stat_label)

	# Bonuses
	if not cls.bonuses.is_empty():
		var bonus_sep := Label.new()
		bonus_sep.text = ""
		vbox.add_child(bonus_sep)
		var bonus_header := Label.new()
		bonus_header.text = "Bonuses:"
		bonus_header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(bonus_header)
		for bonus in cls.bonuses:
			var b_label := Label.new()
			b_label.text = "  • " + bonus
			b_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b_label.custom_minimum_size = Vector2(300, 0)
			vbox.add_child(b_label)

	info_panel.add_child(vbox)


func _show_name_entry() -> void:
	_step = Step.NAME_ENTRY
	hint_label.text = "Type a name (max 16 characters) and press ENTER"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var prompt := Label.new()
	prompt.text = "\nEnter character name:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)

	var line_edit := LineEdit.new()
	line_edit.max_length = 16
	line_edit.text = _char_name
	line_edit.placeholder_text = "Name..."
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_edit.custom_minimum_size = Vector2(300, 40)
	line_edit.text_submitted.connect(_on_name_submitted)
	vbox.add_child(line_edit)

	content_panel.add_child(vbox)

	# Focus the line edit
	await get_tree().process_frame
	line_edit.grab_focus()


func _on_name_submitted(text: String) -> void:
	_char_name = text.strip_edges()
	if _char_name.is_empty():
		return
	_show_confirm()


func _show_confirm() -> void:
	_step = Step.CONFIRM
	var cls = _class_list[_selected_class_index]
	hint_label.text = "[ENTER] Create Character  [ESC] Back to Name"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var header := Label.new()
	header.text = "\n── Confirm Character ──"
	header.modulate = Color(0, 0.733, 0.8)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "\n  Name:  %s" % _char_name
	name_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(name_label)

	var class_label := Label.new()
	class_label.text = "  Class: %s" % cls.name
	vbox.add_child(class_label)

	var type_label := Label.new()
	type_label.text = "  Type:  %s %s %s" % [cls.race, cls.gender, cls.type]
	type_label.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(type_label)

	content_panel.add_child(vbox)


func _create_character() -> void:
	var character: Dictionary = CharacterManager.create_character(_slot, _selected_class_id, _char_name)
	if character.is_empty():
		push_warning("[CharCreate] Failed to create character")
		return
	CharacterManager.set_active_slot(_slot)
	SaveManager.save_game()
	SceneManager.goto_scene("res://scenes/2d/city.tscn")
