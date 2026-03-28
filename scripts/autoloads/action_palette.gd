extends Node
## ActionPalette — manages the player's configurable action palette.
## 2 pages of 3 action slots, cycled with palette_swap during gameplay.

signal page_changed(new_page: int)
signal config_changed()

const ICON_BASE := "res://assets/hud/"

const ALL_ACTIONS: Array = [
	{"id": "attack", "label": "Attack", "short": "Atk", "category": "combat", "icon": "attack.png"},
	{"id": "strong_attack", "label": "Strong Attack", "short": "S.Atk", "category": "combat", "icon": "strong_attack.png"},
	{"id": "dodge", "label": "Dodge Roll", "short": "Dodge", "category": "combat", "icon": "special_attack.png"},
	{"id": "monomate", "label": "Monomate", "short": "Mono", "category": "recovery", "icon": "monomate.png"},
	{"id": "dimate", "label": "Dimate", "short": "Di", "category": "recovery", "icon": "dimate.png"},
	{"id": "trimate", "label": "Trimate", "short": "Tri", "category": "recovery", "icon": "trimate.png"},
	{"id": "monofluid", "label": "Monofluid", "short": "M.Flu", "category": "recovery", "icon": "monofluid.png"},
	{"id": "difluid", "label": "Difluid", "short": "D.Flu", "category": "recovery", "icon": "monofluid.png"},
	{"id": "trifluid", "label": "Trifluid", "short": "T.Flu", "category": "recovery", "icon": "trifluid.png"},
	{"id": "kill_all", "label": "Kill All", "short": "Kill", "category": "debug", "icon": "icon.png"},
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


func get_action_icon(action_id: String) -> Texture2D:
	var data := get_action_data(action_id)
	var icon_file: String = data.get("icon", "")
	if icon_file.is_empty():
		return null
	var path := ICON_BASE + icon_file
	if ResourceLoader.exists(path):
		return load(path)
	return null


func load_from_character(character: Dictionary) -> void:
	var saved: Array = character.get("action_palette", [])
	if saved.size() == 2 and saved[0] is Array and saved[1] is Array:
		pages = saved.duplicate(true)
	else:
		pages = DEFAULT_PAGES.duplicate(true)
	current_page = 0
	config_changed.emit()
	page_changed.emit(0)
