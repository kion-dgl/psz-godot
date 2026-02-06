extends Control
## Equipment screen — view and manage equipped items (weapon, frame, unit1-4).

const EQUIPMENT_SLOTS := ["weapon", "frame", "unit1", "unit2", "unit3", "unit4"]
const SLOT_NAMES := ["Weapon", "Frame", "Unit 1", "Unit 2", "Unit 3", "Unit 4"]

var _selected_slot: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var equip_panel: PanelContainer = $VBox/HBox/EquipPanel
@onready var stats_panel: PanelContainer = $VBox/HBox/StatsPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ EQUIPMENT ══════"
	hint_label.text = "[↑/↓] Select Slot  [ENTER] Equip/Unequip  [ESC] Back"
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_slot = wrapi(_selected_slot - 1, 0, EQUIPMENT_SLOTS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_slot = wrapi(_selected_slot + 1, 0, EQUIPMENT_SLOTS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_toggle_equip()
		get_viewport().set_input_as_handled()


func _toggle_equip() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var slot_key: String = EQUIPMENT_SLOTS[_selected_slot]
	var current: String = str(equipment.get(slot_key, ""))

	if not current.is_empty():
		# Unequip
		equipment[slot_key] = ""
		hint_label.text = "Unequipped %s" % current
	else:
		hint_label.text = "No items available to equip (collect items from field first)"

	_refresh_display()


func _refresh_display() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equipment: Dictionary = character.get("equipment", {})

	# Equipment slots panel
	for child in equip_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "── Equipment Slots ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	for i in range(EQUIPMENT_SLOTS.size()):
		var slot_key: String = EQUIPMENT_SLOTS[i]
		var equipped: String = str(equipment.get(slot_key, ""))
		var display_name: String = SLOT_NAMES[i]

		var label := Label.new()
		if equipped.is_empty():
			label.text = "%-8s [Empty]" % display_name
			if i == _selected_slot:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
				label.modulate = Color(0.333, 0.333, 0.333)
		else:
			label.text = "%-8s %s" % [display_name, equipped]
			if i == _selected_slot:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text

		vbox.add_child(label)

	equip_panel.add_child(vbox)

	# Stats panel
	_refresh_stats()


func _refresh_stats() -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data == null:
		return

	var level: int = int(character.get("level", 1))
	var base_stats: Dictionary = class_data.get_stats_at_level(level)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "── Stats ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "%s  %s Lv.%d" % [
		str(character.get("name", "???")),
		str(character.get("class_id", "???")),
		level
	]
	name_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(name_label)

	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)

	for stat_name in ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]:
		var display := stat_name.to_upper().substr(0, 3)
		match stat_name:
			"technique": display = "TEC"
			"accuracy": display = "ACC"
			"evasion": display = "EVA"
			"defense": display = "DEF"
			"attack": display = "ATK"
		var val: int = base_stats.get(stat_name, 0)
		var stat_label := Label.new()
		stat_label.text = "  %-4s %d" % [display, val]
		vbox.add_child(stat_label)

	stats_panel.add_child(vbox)
