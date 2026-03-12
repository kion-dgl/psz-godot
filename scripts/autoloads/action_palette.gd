extends Node
## ActionPalette — manages the player's configurable action palette.
## 2 pages of 3 action slots, cycled with palette_swap during gameplay.

signal page_changed(new_page: int)
signal config_changed()

const ALL_ACTIONS: Array = [
	{"id": "attack", "label": "Attack", "short": "Atk", "category": "combat"},
	{"id": "strong_attack", "label": "Strong Attack", "short": "S.Atk", "category": "combat"},
	{"id": "dodge", "label": "Dodge Roll", "short": "Dodge", "category": "combat"},
	{"id": "monomate", "label": "Monomate", "short": "Mono", "category": "recovery"},
	{"id": "dimate", "label": "Dimate", "short": "Di", "category": "recovery"},
	{"id": "trimate", "label": "Trimate", "short": "Tri", "category": "recovery"},
	{"id": "monofluid", "label": "Monofluid", "short": "M.Flu", "category": "recovery"},
	{"id": "difluid", "label": "Difluid", "short": "D.Flu", "category": "recovery"},
	{"id": "trifluid", "label": "Trifluid", "short": "T.Flu", "category": "recovery"},
]

const DEFAULT_PAGES: Array = [
	["attack", "strong_attack", "monomate"],
	["attack", "dodge", "dimate"],
]

var pages: Array = []
var current_page: int = 0


func _ready() -> void:
	pages = DEFAULT_PAGES.duplicate(true)


func swap_page() -> void:
	current_page = (current_page + 1) % pages.size()
	page_changed.emit(current_page)


func get_current_slots() -> Array:
	return pages[current_page]


func get_action_for_slot(slot: int) -> String:
	var slots: Array = pages[current_page]
	if slot < 0 or slot >= slots.size():
		return ""
	return slots[slot]


func set_action(page: int, slot: int, action_id: String) -> void:
	if page < 0 or page >= pages.size():
		return
	if slot < 0 or slot >= pages[page].size():
		return
	pages[page][slot] = action_id
	config_changed.emit()


func get_action_data(action_id: String) -> Dictionary:
	for action in ALL_ACTIONS:
		if action.id == action_id:
			return action
	return {}


func load_from_character(character: Dictionary) -> void:
	var saved: Array = character.get("action_palette", [])
	if saved.size() == 2 and saved[0] is Array and saved[1] is Array:
		pages = saved.duplicate(true)
	else:
		pages = DEFAULT_PAGES.duplicate(true)
	current_page = 0
	config_changed.emit()
	page_changed.emit(0)
