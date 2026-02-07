extends Control
## Tekker — grind weapons and identify unknown weapons.

enum Mode { GRIND, IDENTIFY }

var _mode: int = Mode.GRIND
var _selected_index: int = 0
var _grindable_weapons: Array = []  # Array of {id, name, grind, max_grind, rarity}
var _unidentified_weapons: Array = []  # Array of {id, name, rarity}

## Grinder requirements by weapon rarity
const GRINDER_FOR_RARITY := {
	1: "monogrinder", 2: "monogrinder", 3: "monogrinder",
	4: "digrinder", 5: "digrinder",
	6: "trigrinder", 7: "trigrinder",
}

const RARITY_COST_MULT := {1: 1.0, 2: 1.5, 3: 2.0, 4: 3.0, 5: 4.0, 6: 6.0, 7: 10.0}

const IDENTIFY_COST := {5: 1000, 6: 2500, 7: 5000}

@onready var title_label: Label = $VBox/TitleLabel
@onready var mode_label: Label = $VBox/ModeLabel
@onready var content_panel: PanelContainer = $VBox/ContentPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ TEKKER ══════"
	hint_label.text = "[←/→] Switch Mode  [↑/↓] Select  [ENTER] Confirm  [ESC] Leave"
	_build_lists()
	_refresh_display()


func _build_lists() -> void:
	_grindable_weapons.clear()
	_unidentified_weapons.clear()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Grindable: weapons in inventory
	var all_items: Array = Inventory.get_all_items()
	for item in all_items:
		var weapon = WeaponRegistry.get_weapon(item.get("id", ""))
		if weapon and weapon.max_grind > 0:
			var current_grind: int = int(character.get("weapon_grinds", {}).get(weapon.id, 0))
			if current_grind < weapon.max_grind:
				_grindable_weapons.append({
					"id": weapon.id,
					"name": weapon.name,
					"grind": current_grind,
					"max_grind": weapon.max_grind,
					"rarity": weapon.rarity,
				})

	# Unidentified weapons
	for weapon_id in character.get("unidentified_weapons", []):
		var weapon = WeaponRegistry.get_weapon(weapon_id)
		if weapon:
			_unidentified_weapons.append({
				"id": weapon.id,
				"name": weapon.name,
				"rarity": weapon.rarity,
			})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_mode = Mode.IDENTIFY if _mode == Mode.GRIND else Mode.GRIND
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var max_items: int = _grindable_weapons.size() if _mode == Mode.GRIND else _unidentified_weapons.size()
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_items: int = _grindable_weapons.size() if _mode == Mode.GRIND else _unidentified_weapons.size()
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _mode == Mode.GRIND:
			_grind_selected()
		else:
			_identify_selected()
		get_viewport().set_input_as_handled()


func _grind_selected() -> void:
	if _grindable_weapons.is_empty() or _selected_index >= _grindable_weapons.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var weapon_info: Dictionary = _grindable_weapons[_selected_index]
	var weapon_id: String = weapon_info["id"]
	var current_grind: int = weapon_info["grind"]
	var rarity: int = weapon_info["rarity"]

	# Check grinder requirement
	var grinder_id: String = GRINDER_FOR_RARITY.get(rarity, "monogrinder")
	if not Inventory.has_item(grinder_id):
		var grinder_name: String = grinder_id.replace("_", " ").capitalize()
		hint_label.text = "Need a %s to grind this weapon!" % grinder_name
		return

	# Calculate cost
	var cost := int((200 + current_grind * 100) * RARITY_COST_MULT.get(rarity, 1.0))
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta! Need %d M" % cost
		return

	# Grind always succeeds in PSZ
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])
	Inventory.remove_item(grinder_id, 1)

	if not character.has("weapon_grinds"):
		character["weapon_grinds"] = {}
	character["weapon_grinds"][weapon_id] = current_grind + 1

	hint_label.text = "Ground %s to +%d! (-%d M)" % [weapon_info["name"], current_grind + 1, cost]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_grindable_weapons.size() - 1, 0))
	_refresh_display()


func _identify_selected() -> void:
	if _unidentified_weapons.is_empty() or _selected_index >= _unidentified_weapons.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var weapon_info: Dictionary = _unidentified_weapons[_selected_index]
	var weapon_id: String = weapon_info["id"]
	var rarity: int = weapon_info["rarity"]

	var cost: int = IDENTIFY_COST.get(rarity, 1000)
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta! Need %d M" % cost
		return

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# Remove from unidentified list
	var unid_list: Array = character.get("unidentified_weapons", [])
	var idx: int = unid_list.find(weapon_id)
	if idx >= 0:
		unid_list.remove_at(idx)

	# Add to inventory
	Inventory.add_item(weapon_id, 1)

	hint_label.text = "Identified %s! (-%d M)" % [weapon_info["name"], cost]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_unidentified_weapons.size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	if _mode == Mode.GRIND:
		mode_label.text = "[◄ GRIND ►]    IDENTIFY"
	else:
		mode_label.text = "   GRIND    [◄ IDENTIFY ►]"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var character = CharacterManager.get_active_character()
	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %d" % (int(character.get("meseta", 0)) if character else 0)
	meseta_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(meseta_label)

	if _mode == Mode.GRIND:
		var desc := Label.new()
		desc.text = "Grinding increases a weapon's attack power."
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

		if _grindable_weapons.is_empty():
			var placeholder := Label.new()
			placeholder.text = "(No grindable weapons in inventory)"
			placeholder.modulate = Color(0.333, 0.333, 0.333)
			vbox.add_child(placeholder)
		else:
			for i in range(_grindable_weapons.size()):
				var w: Dictionary = _grindable_weapons[i]
				var grinder_id: String = GRINDER_FOR_RARITY.get(w["rarity"], "monogrinder")
				var has_grinder: bool = Inventory.has_item(grinder_id)
				var cost := int((200 + w["grind"] * 100) * RARITY_COST_MULT.get(w["rarity"], 1.0))
				var label := Label.new()
				label.text = "%-18s +%d/%d  %d M  [%s]" % [w["name"], w["grind"], w["max_grind"], cost, grinder_id.replace("_", " ")]
				if i == _selected_index:
					label.text = "> " + label.text
					label.modulate = Color(1, 0.8, 0) if has_grinder else Color(1, 0.267, 0.267)
				else:
					label.text = "  " + label.text
					if not has_grinder:
						label.modulate = Color(0.5, 0.5, 0.5)
				vbox.add_child(label)
	else:
		var desc := Label.new()
		desc.text = "Identification reveals the true stats of\nunidentified weapons (5-7★ rarity)."
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

		if _unidentified_weapons.is_empty():
			var placeholder := Label.new()
			placeholder.text = "(No unidentified weapons)"
			placeholder.modulate = Color(0.333, 0.333, 0.333)
			vbox.add_child(placeholder)
		else:
			for i in range(_unidentified_weapons.size()):
				var w: Dictionary = _unidentified_weapons[i]
				var cost: int = IDENTIFY_COST.get(w["rarity"], 1000)
				var label := Label.new()
				label.text = "%-18s %s★  %d M" % [w["name"], str(w["rarity"]), cost]
				if i == _selected_index:
					label.text = "> " + label.text
					label.modulate = Color(1, 0.8, 0)
				else:
					label.text = "  " + label.text
				vbox.add_child(label)

	content_panel.add_child(vbox)
