extends Control
## Tech shop — browse and buy randomized technique disks to inventory.

var _items: Array = []
var _selected_index: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var list_panel: PanelContainer = $VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ TECH SHOP ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Buy  [ESC] Leave"
	_generate_inventory()
	_refresh_display()


func _generate_inventory() -> void:
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	_items = TechniqueManager.generate_shop_inventory(char_level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_buy_selected()
		get_viewport().set_input_as_handled()


func _buy_selected() -> void:
	if _items.is_empty() or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	var cost: int = int(item.get("cost", 0))
	var technique_id: String = str(item.get("technique_id", ""))
	var level: int = int(item.get("level", 1))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return

	# Create disk item and add to inventory
	var disk_id: String = "disk_%s_%d" % [technique_id, level]
	if not Inventory.can_add_item(disk_id):
		hint_label.text = "Inventory full!"
		return

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# Add disk to inventory
	Inventory.add_item(disk_id, 1)
	var tech_name: String = str(TechniqueManager.TECHNIQUES.get(technique_id, {}).get("name", technique_id))
	hint_label.text = "Bought Disk: %s Lv.%d!" % [tech_name, level]
	_refresh_display()


func _refresh_display() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	var current_meseta: int = int(character.get("meseta", 0)) if character else 0

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %d  Slots: %d/40" % [current_meseta, Inventory.get_total_slots()]
	meseta_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(meseta_label)

	var selected_label: Label = null

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "  (No techniques available)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var technique_id: String = str(item.get("technique_id", ""))
			var level: int = int(item.get("level", 1))
			var cost: int = int(item.get("cost", 0))
			var disk_name: String = str(item.get("name", "???"))

			# Check player's current technique level
			var current_tech_level: int = 0
			if character:
				current_tech_level = TechniqueManager.get_technique_level(character, technique_id)

			# Check requirements
			var required_level: int = TechniqueManager.get_disk_required_level(level)
			var cant_afford: bool = current_meseta < cost
			var too_low_level: bool = char_level < required_level
			var already_higher: bool = current_tech_level >= level

			# Build status tags
			var status_tag := ""
			if already_higher:
				status_tag = " [Lv.%d]" % current_tech_level
			elif current_tech_level > 0:
				status_tag = " [Lv.%d]" % current_tech_level
			if too_low_level:
				status_tag += " [Req.%d]" % required_level

			var label := Label.new()
			label.text = "%-22s %5d M%s" % [disk_name, cost, status_tag]

			if i == _selected_index:
				label.text = "> " + label.text
				if already_higher:
					label.modulate = Color(0.5, 0.5, 0.5)
				elif too_low_level:
					label.modulate = Color(0.7, 0.5, 0.15)
				elif cant_afford:
					label.modulate = Color(0.8, 0.8, 0.267)
				else:
					label.modulate = Color(1, 0.8, 0)
				selected_label = label
			else:
				label.text = "  " + label.text
				if already_higher:
					label.modulate = Color(0.333, 0.333, 0.333)
				elif too_low_level:
					label.modulate = Color(0.5, 0.35, 0.1)
				elif cant_afford:
					label.modulate = Color(0.5, 0.5, 0.2)
			vbox.add_child(label)

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	if selected_label != null:
		scroll.ensure_control_visible.call_deferred(selected_label)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _items.is_empty() or _selected_index >= _items.size():
		return

	var item: Dictionary = _items[_selected_index]
	var technique_id: String = str(item.get("technique_id", ""))
	var level: int = int(item.get("level", 1))
	var tech: Dictionary = TechniqueManager.get_technique(technique_id)
	if tech.is_empty():
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(item.get("name", "???"))
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	_add_line(vbox, "Element: %s" % str(tech.get("element", "none")).capitalize())
	_add_line(vbox, "Target: %s" % str(tech.get("target", "single")).capitalize())

	var power: int = int(tech.get("power", 0))
	if power > 0:
		var scaled_power: int = int(float(power) * (1.0 + float(level) / 10.0))
		_add_line(vbox, "Power: %d (Lv.%d)" % [scaled_power, level])

	var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
	_add_line(vbox, "PP Cost: %d" % pp_cost)

	# Required level
	var required_level: int = TechniqueManager.get_disk_required_level(level)
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	var req_label := Label.new()
	req_label.text = "Req. Level: %d" % required_level
	if char_level < required_level:
		req_label.modulate = Color(0.7, 0.5, 0.15)
	vbox.add_child(req_label)

	# Current technique level
	if character:
		var current_level: int = TechniqueManager.get_technique_level(character, technique_id)
		if current_level > 0:
			var cur_label := Label.new()
			if current_level >= level:
				cur_label.text = "Known: Lv.%d (already higher)" % current_level
				cur_label.modulate = Color(0.5, 0.5, 0.5)
			else:
				cur_label.text = "Known: Lv.%d → Lv.%d" % [current_level, level]
				cur_label.modulate = Color(0.5, 1, 0.5)
			vbox.add_child(cur_label)

	# Price
	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)
	var cost_label := Label.new()
	cost_label.text = "Price: %d M" % int(item.get("cost", 0))
	cost_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(cost_label)

	# Note about usage
	var note := Label.new()
	note.text = "Use from inventory to learn"
	note.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(note)

	detail_panel.add_child(vbox)


func _add_line(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
