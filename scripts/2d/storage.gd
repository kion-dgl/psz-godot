extends Control
## Storage screen — move items between character inventory and shared storage.

var _selected_side: int = 0  # 0 = inventory, 1 = storage
var _selected_index: int = 0
var _inventory_items: Array = []
var _storage_items: Array = []

@onready var title_label: Label = $VBox/TitleLabel
@onready var inventory_panel: PanelContainer = $VBox/HBox/InventoryPanel
@onready var storage_panel: PanelContainer = $VBox/HBox/StoragePanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ STORAGE ══════"
	hint_label.text = "[←/→] Switch  [↑/↓] Select  [ENTER] Move  [ESC] Back"
	_load_items()
	_refresh_display()


func _load_items() -> void:
	_inventory_items = Inventory.get_all_items()
	_storage_items = _get_storage_items()


func _get_storage_items() -> Array:
	var character = CharacterManager.get_active_character()
	if character == null:
		return []
	return character.get("storage", [])


func _set_storage_items(items: Array) -> void:
	var character = CharacterManager.get_active_character()
	if character:
		character["storage"] = items


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_selected_side = 0
		_selected_index = clampi(_selected_index, 0, maxi(_inventory_items.size() - 1, 0))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_selected_side = 1
		_selected_index = clampi(_selected_index, 0, maxi(_storage_items.size() - 1, 0))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var max_idx: int = _get_current_list_size() - 1
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_idx: int = _get_current_list_size() - 1
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_move_item()
		get_viewport().set_input_as_handled()


func _get_current_list_size() -> int:
	if _selected_side == 0:
		return _inventory_items.size()
	else:
		return _storage_items.size()


func _move_item() -> void:
	if _selected_side == 0:
		# Move from inventory to storage
		if _inventory_items.is_empty() or _selected_index >= _inventory_items.size():
			return
		var item: Dictionary = _inventory_items[_selected_index]
		_storage_items.append(item.duplicate())
		Inventory.remove_item(str(item.get("id", "")), int(item.get("quantity", 1)))
	else:
		# Move from storage to inventory
		if _storage_items.is_empty() or _selected_index >= _storage_items.size():
			return
		var item: Dictionary = _storage_items[_selected_index]
		var item_id: String = str(item.get("id", ""))
		if not Inventory.can_add_item(item_id):
			return
		Inventory.add_item(item_id, int(item.get("quantity", 1)))
		_storage_items.remove_at(_selected_index)

	_set_storage_items(_storage_items)
	_load_items()
	_selected_index = clampi(_selected_index, 0, maxi(_get_current_list_size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	_refresh_inventory_panel()
	_refresh_storage_panel()


func _refresh_inventory_panel() -> void:
	for child in inventory_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = "── INVENTORY (%d/40) ──" % _inventory_items.size()
	if _selected_side == 0:
		header.modulate = Color(1, 0.8, 0)
	else:
		header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	if _inventory_items.is_empty():
		var empty := Label.new()
		empty.text = "  (Empty)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_inventory_items.size()):
			var item: Dictionary = _inventory_items[i]
			var label := Label.new()
			var name_str: String = str(item.get("name", str(item.get("id", "???"))))
			var qty: int = int(item.get("quantity", 1))
			if qty > 1:
				label.text = "%-20s x%d" % [name_str, qty]
			else:
				label.text = name_str
			if _selected_side == 0 and i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	inventory_panel.add_child(scroll)


func _refresh_storage_panel() -> void:
	for child in storage_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = "── STORAGE (%d) ──" % _storage_items.size()
	if _selected_side == 1:
		header.modulate = Color(1, 0.8, 0)
	else:
		header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	if _storage_items.is_empty():
		var empty := Label.new()
		empty.text = "  (Empty)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_storage_items.size()):
			var item: Dictionary = _storage_items[i]
			var label := Label.new()
			var name_str: String = str(item.get("name", str(item.get("id", "???"))))
			var qty: int = int(item.get("quantity", 1))
			if qty > 1:
				label.text = "%-20s x%d" % [name_str, qty]
			else:
				label.text = name_str
			if _selected_side == 1 and i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	storage_panel.add_child(scroll)
