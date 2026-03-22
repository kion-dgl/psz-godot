extends Control
## Crafting Shop — learn synthesis boards and craft weapons.

enum Mode { LEARN, CRAFT }

const TAB_NAMES := ["Learn Board", "Craft"]
const PHOTON_OPTIONS := ["None", "El-Photon", "Im-Photon", "Di-Photon"]
const PHOTON_IDS := ["", "el_photon", "im_photon", "di_photon"]

var _mode: int = Mode.LEARN
var _selected_index: int = 0
var _board_items: Array = []       # Array of {id, name, rarity}
var _learned_recipes: Array = []   # Array of RecipeBoardData

var _selecting_photon: bool = false
var _photon_index: int = 0
var _pending_recipe_index: int = -1

var _mode_bar_parent: Control
var _tab_row: HBoxContainer
var _portrait: TextureRect

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Synthesis Shop"
	_setup_portrait()
	hint_label.text = "Left/Right: Switch Mode  Up/Down: Select  Enter: Confirm  Esc: Leave"
	_build_lists()
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


func _build_lists() -> void:
	_board_items.clear()
	_learned_recipes.clear()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Find recipe boards in inventory
	var all_items: Array = Inventory.get_all_items()
	for item in all_items:
		var item_id: String = item.get("id", "")
		var recipe = RecipeRegistry.get_recipe(item_id)
		if recipe:
			_board_items.append({
				"id": recipe.id,
				"name": recipe.name,
				"rarity": recipe.rarity,
				"quantity": item.get("quantity", 1),
			})

	# Get learned recipes
	var learned_ids: Array = character.get("learned_recipes", [])
	for recipe_id in learned_ids:
		var recipe = RecipeRegistry.get_recipe(recipe_id)
		if recipe:
			_learned_recipes.append(recipe)


func _unhandled_input(event: InputEvent) -> void:
	if _selecting_photon:
		_handle_photon_input(event)
		return

	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_mode = Mode.CRAFT if _mode == Mode.LEARN else Mode.LEARN
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var max_items: int = _board_items.size() if _mode == Mode.LEARN else _learned_recipes.size()
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_items: int = _board_items.size() if _mode == Mode.LEARN else _learned_recipes.size()
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _mode == Mode.LEARN:
			_learn_selected()
		else:
			_craft_selected()
		get_viewport().set_input_as_handled()


func _handle_photon_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_selecting_photon = false
		_pending_recipe_index = -1
		hint_label.text = "Left/Right: Switch Mode  Up/Down: Select  Enter: Confirm  Esc: Leave"
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_photon_index = wrapi(_photon_index - 1, 0, PHOTON_OPTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_photon_index = wrapi(_photon_index + 1, 0, PHOTON_OPTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm_craft_with_photon()
		get_viewport().set_input_as_handled()


func _learn_selected() -> void:
	if _board_items.is_empty() or _selected_index >= _board_items.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var board_info: Dictionary = _board_items[_selected_index]
	var board_id: String = board_info["id"]

	# Check if already learned
	var learned: Array = character.get("learned_recipes", [])
	if learned.has(board_id):
		hint_label.text = "Already learned this recipe!"
		return

	# Consume board from inventory
	Inventory.remove_item(board_id, 1)

	# Add to learned recipes
	if not character.has("learned_recipes"):
		character["learned_recipes"] = []
	character["learned_recipes"].append(board_id)

	hint_label.text = "Learned %s!" % board_info["name"]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_board_items.size() - 1, 0))
	_refresh_display()


func _craft_selected() -> void:
	if _learned_recipes.is_empty() or _selected_index >= _learned_recipes.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var recipe: RecipeBoardData = _learned_recipes[_selected_index]

	# Check meseta
	if int(character.get("meseta", 0)) < recipe.craft_cost:
		hint_label.text = "Not enough meseta! Need %d M" % recipe.craft_cost
		return

	# Check ingredients
	for ingredient in recipe.ingredients:
		var owned: int = Inventory.get_item_count(ingredient["item_id"])
		if owned < int(ingredient["quantity"]):
			var mat = MaterialRegistry.get_material(ingredient["item_id"])
			var mat_name: String = mat.name if mat else ingredient["item_id"]
			hint_label.text = "Not enough %s!" % mat_name
			return

	# If has photon slot, enter photon selection
	if recipe.has_photon_slot:
		_selecting_photon = true
		_photon_index = 0
		_pending_recipe_index = _selected_index
		hint_label.text = "Choose a photon element (or None)  Up/Down: Select  Enter: Confirm  Esc: Back"
		_refresh_display()
		return

	# No photon slot — craft directly
	_execute_craft(recipe, "")


func _confirm_craft_with_photon() -> void:
	if _pending_recipe_index < 0 or _pending_recipe_index >= _learned_recipes.size():
		_selecting_photon = false
		return

	var recipe: RecipeBoardData = _learned_recipes[_pending_recipe_index]
	var photon_id: String = PHOTON_IDS[_photon_index]

	# If a photon is selected, check that we have it
	if not photon_id.is_empty():
		if not Inventory.has_item(photon_id):
			hint_label.text = "You don't have %s!" % PHOTON_OPTIONS[_photon_index]
			return

	_execute_craft(recipe, photon_id)
	_selecting_photon = false
	_pending_recipe_index = -1


func _execute_craft(recipe: RecipeBoardData, photon_id: String) -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - recipe.craft_cost
	GameState.meseta = int(character["meseta"])

	# Deduct ingredients
	for ingredient in recipe.ingredients:
		Inventory.remove_item(ingredient["item_id"], int(ingredient["quantity"]))

	# Deduct photon if used
	if not photon_id.is_empty():
		Inventory.remove_item(photon_id, 1)

	# Add crafted weapon to inventory
	Inventory.add_item(recipe.output_weapon_id, 1)

	# Store photon element on weapon if used
	if not photon_id.is_empty():
		if not character.has("weapon_elements"):
			character["weapon_elements"] = {}
		character["weapon_elements"][recipe.output_weapon_id] = photon_id

	var photon_text: String = ""
	if not photon_id.is_empty():
		photon_text = " [%s]" % PHOTON_OPTIONS[_photon_index]
	hint_label.text = "Crafted %s%s! (-%d M)" % [recipe.name.replace(" Board", ""), photon_text, recipe.craft_cost]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_learned_recipes.size() - 1, 0))
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
	_tab_row.add_child(PszStyle.create_tab_bar(TAB_NAMES, _mode))
	_tab_row.add_child(PszStyle.create_meseta_label(_get_meseta()))

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

	if _selecting_photon:
		vbox.add_child(PszStyle.create_section_header("Select photon element for crafting:"))
		for i in range(PHOTON_OPTIONS.size()):
			var option_name: String = PHOTON_OPTIONS[i]
			var has_it: bool = true
			if i > 0:
				has_it = Inventory.has_item(PHOTON_IDS[i])
			var text_color := Color.TRANSPARENT
			if i > 0 and not has_it:
				text_color = PszStyle.TEXT_DANGER
			var count_text: String = ""
			if i > 0:
				count_text = "x%d" % Inventory.get_item_count(PHOTON_IDS[i])
			var pill := PszStyle.create_pill(option_name, i == _photon_index, count_text, text_color)
			vbox.add_child(pill)
			if i == _photon_index:
				selected_pill = pill
	elif _mode == Mode.LEARN:
		vbox.add_child(PszStyle.create_section_header("Use a board to learn a new recipe."))

		if _board_items.is_empty():
			vbox.add_child(PszStyle.create_pill("(No recipe boards in inventory)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_board_items.size()):
				var b: Dictionary = _board_items[i]
				var star_text: String = "%d star" % b["rarity"]
				var pill := PszStyle.create_pill(
					"%s" % b["name"],
					i == _selected_index, star_text)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill
	else:
		vbox.add_child(PszStyle.create_section_header("Craft weapons from learned recipes."))

		if _learned_recipes.is_empty():
			vbox.add_child(PszStyle.create_pill("(No learned recipes)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_learned_recipes.size()):
				var recipe: RecipeBoardData = _learned_recipes[i]
				var can_craft: bool = _can_craft_recipe(recipe)
				var text_color := Color.TRANSPARENT
				if not can_craft:
					text_color = PszStyle.TEXT_DANGER

				# Build ingredient summary
				var ing_parts: PackedStringArray = []
				for ingredient in recipe.ingredients:
					var mat = MaterialRegistry.get_material(ingredient["item_id"])
					var mat_name: String = mat.name if mat else ingredient["item_id"]
					var owned: int = Inventory.get_item_count(ingredient["item_id"])
					var needed: int = int(ingredient["quantity"])
					ing_parts.append("%s %d/%d" % [mat_name, owned, needed])

				var pill := PszStyle.create_pill(
					"%s  (%s)" % [recipe.name.replace(" Board", ""), ", ".join(ing_parts)],
					i == _selected_index, "%d M" % recipe.craft_cost, text_color)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)


func _can_craft_recipe(recipe: RecipeBoardData) -> bool:
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	if int(character.get("meseta", 0)) < recipe.craft_cost:
		return false
	for ingredient in recipe.ingredients:
		if Inventory.get_item_count(ingredient["item_id"]) < int(ingredient["quantity"]):
			return false
	return true


func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0
