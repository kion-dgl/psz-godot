extends Control
## Tech shop — buy technique disks.

var _items: Array = []
var _selected_index: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var list_panel: PanelContainer = $VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ TECH SHOP ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Buy  [ESC] Leave"
	_load_items()
	_refresh_display()


func _load_items() -> void:
	_items = ShopManager.get_shop_inventory("tech_shop")
	if _items.is_empty():
		for shop in ShopRegistry.get_all_shops():
			if "tech" in shop.name.to_lower():
				_items = shop.items.duplicate()
				break


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
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return

	# Parse technique_id and level from disk name ("Disk: Foie Lv.5" → "foie", 5)
	var item_name: String = str(item.get("item", ""))
	var parsed := _parse_disk_name(item_name)
	if parsed.is_empty():
		hint_label.text = "Invalid disk!"
		return

	var technique_id: String = parsed["technique_id"]
	var level: int = parsed["level"]

	# Check if character can learn this technique
	var check := TechniqueManager.can_learn(character, technique_id, level)
	if not check["allowed"]:
		hint_label.text = str(check["reason"])
		return

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# Learn the technique (disks are used immediately, not added to inventory)
	var disk := TechniqueManager.create_disk(technique_id, level)
	var result := TechniqueManager.use_disk(character, disk)
	hint_label.text = str(result["message"])
	_refresh_display()


## Parse "Disk: Foie Lv.5" → {technique_id: "foie", level: 5}
func _parse_disk_name(disk_name: String) -> Dictionary:
	if not disk_name.begins_with("Disk: "):
		return {}
	var rest := disk_name.substr(6)  # Remove "Disk: "
	var lv_pos := rest.find(" Lv.")
	if lv_pos < 0:
		return {}
	var tech_name := rest.substr(0, lv_pos)
	var level_str := rest.substr(lv_pos + 4)
	var level := int(level_str)
	# Find technique_id by matching name
	for tech_id in TechniqueManager.TECHNIQUES:
		if TechniqueManager.TECHNIQUES[tech_id]["name"] == tech_name:
			return {"technique_id": tech_id, "level": level}
	return {}


func _refresh_display() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "  (No techniques available)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var label := Label.new()
			label.text = "%-22s %6d M" % [str(item.get("item", "???")), int(item.get("cost", 0))]
			if i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	# Detail
	for child in detail_panel.get_children():
		child.queue_free()
	if not _items.is_empty() and _selected_index < _items.size():
		var item: Dictionary = _items[_selected_index]
		var info_vbox := VBoxContainer.new()
		var n := Label.new()
		n.text = "── %s ──" % str(item.get("item", "???"))
		n.modulate = Color(0, 0.733, 0.8)
		info_vbox.add_child(n)
		var c := Label.new()
		c.text = "Category: %s" % str(item.get("category", "technique"))
		info_vbox.add_child(c)
		var p := Label.new()
		p.text = "Price: %d Meseta" % int(item.get("cost", 0))
		p.modulate = Color(1, 0.8, 0)
		info_vbox.add_child(p)
		detail_panel.add_child(info_vbox)


func _get_meseta_str() -> String:
	var character = CharacterManager.get_active_character()
	if character:
		return str(int(character.get("meseta", 0)))
	return "0"
