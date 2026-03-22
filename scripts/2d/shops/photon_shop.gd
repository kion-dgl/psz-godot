extends Control
## Photon Collector — trade Photon Drops for grinders, photon crystals, and materials.

const EXCHANGE_ITEMS := [
	{"name": "Monogrinder", "id": "monogrinder", "cost": 1, "category": "Grinders"},
	{"name": "Digrinder", "id": "digrinder", "cost": 3, "category": "Grinders"},
	{"name": "Trigrinder", "id": "trigrinder", "cost": 5, "category": "Grinders"},
	{"name": "Im Photon", "id": "im_photon", "cost": 1, "category": "Photon Crystals"},
	{"name": "El Photon", "id": "el_photon", "cost": 3, "category": "Photon Crystals"},
	{"name": "Ban Photon", "id": "ban_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Ray Photon", "id": "ray_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Zon Photon", "id": "zon_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Megi Photon", "id": "megi_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Gra Photon", "id": "gra_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Grinder Base C", "id": "grinder_base_c", "cost": 3, "category": "Materials"},
	{"name": "Grinder Base B", "id": "grinder_base_b", "cost": 5, "category": "Materials"},
	{"name": "Grinder Base A", "id": "grinder_base_a", "cost": 8, "category": "Materials"},
]

var _selected_index: int = 0
var _mode_bar_parent: Control
var _tab_row: HBoxContainer
var _portrait: Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Photon Collector"
	_setup_portrait()
	hint_label.text = "Up/Down: Select  Enter: Exchange  Esc: Leave"
	_refresh_display()


func _setup_portrait() -> void:
	var data := SceneManager.get_transition_data()
	var model_path: String = data.get("npc_model_path", "")
	if model_path.is_empty():
		return
	var panel: PanelContainer = $Panel
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var fs := StyleBoxFlat.new()
	fs.bg_color = PszStyle.BG
	fs.content_margin_left = 12.0
	fs.content_margin_top = 8.0
	fs.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", fs)

	var vbox := panel.get_child(0) as VBoxContainer
	panel.remove_child(vbox)
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 3.0
	outer.add_child(vbox)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 1.0
	right.add_child(spacer)
	_portrait = PszStyle.create_npc_portrait(model_path)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_stretch_ratio = 1.0
	right.add_child(_portrait)
	outer.add_child(right)
	panel.add_child(outer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, EXCHANGE_ITEMS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, EXCHANGE_ITEMS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_exchange_selected()
		get_viewport().set_input_as_handled()


func _exchange_selected() -> void:
	if _selected_index >= EXCHANGE_ITEMS.size():
		return

	var item: Dictionary = EXCHANGE_ITEMS[_selected_index]
	var cost: int = int(item["cost"])
	var item_id: String = item["id"]
	var item_name: String = item["name"]

	var pd_count: int = Inventory.get_item_count("photon_drop")
	if pd_count < cost:
		hint_label.text = "Not enough Photon Drops! Need %d" % cost
		return

	if not Inventory.can_add_item(item_id):
		hint_label.text = "Inventory full!"
		return

	Inventory.remove_item("photon_drop", cost)
	Inventory.add_item(item_id, 1)
	hint_label.text = "Exchanged %d Photon Drops for %s!" % [cost, item_name]
	_refresh_display()


func _refresh_display() -> void:
	mode_label.visible = false

	if not is_instance_valid(_tab_row):
		_tab_row = HBoxContainer.new()
		_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tab_row.add_theme_constant_override("separation", 8)
		_mode_bar_parent.add_child(_tab_row)
		_mode_bar_parent.move_child(_tab_row, mode_label.get_index() + 1)
	for child in _tab_row.get_children():
		child.queue_free()

	var pd_count: int = Inventory.get_item_count("photon_drop")
	var pd_label := Label.new()
	pd_label.text = "Photon Drops: %d" % pd_count
	pd_label.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
	pd_label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
	pd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_row.add_child(pd_label)

	for child in content_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var selected_pill: Control = null
	var last_category: String = ""

	for i in range(EXCHANGE_ITEMS.size()):
		var item: Dictionary = EXCHANGE_ITEMS[i]
		var category: String = item["category"]
		var cost: int = int(item["cost"])

		if category != last_category:
			last_category = category
			vbox.add_child(PszStyle.create_section_header(category))

		var can_afford: bool = pd_count >= cost
		var text_color := Color.TRANSPARENT
		if not can_afford:
			text_color = PszStyle.TEXT_DANGER

		var held: int = Inventory.get_item_count(item["id"])
		var held_str: String = " (x%d)" % held if held > 0 else ""

		var pill := PszStyle.create_pill(
			"%s%s" % [item["name"], held_str],
			i == _selected_index, "%d PD" % cost, text_color)
		vbox.add_child(pill)
		if i == _selected_index:
			selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)
