extends Node
## ActionPalette — manages the player's configurable action palette.
## 2 pages of 3 action slots, cycled with palette_swap during gameplay.

signal page_changed(new_page: int)
signal config_changed()

const ICON_BASE := "res://assets/hud/"

const ALL_ACTIONS: Array = [
	{"id": "attack", "label": "Attack", "short": "Atk", "category": "combat", "icon": "attack.png"},
	{"id": "strong_attack", "label": "Strong Attack", "short": "S.Atk", "category": "combat", "icon": "strong_attack.png"},
	{"id": "dodge", "label": "Dodge Roll", "short": "Dodge", "category": "combat", "icon": "dodge.png"},
	{"id": "monomate", "label": "Monomate", "short": "Mono", "category": "recovery", "icon": "monomate.png"},
	{"id": "dimate", "label": "Dimate", "short": "Di", "category": "recovery", "icon": "dimate.png"},
	{"id": "trimate", "label": "Trimate", "short": "Tri", "category": "recovery", "icon": "trimate.png"},
	{"id": "monofluid", "label": "Monofluid", "short": "M.Flu", "category": "recovery", "icon": "monofluid.png"},
	{"id": "difluid", "label": "Difluid", "short": "D.Flu", "category": "recovery", "icon": "monofluid.png"},
	{"id": "trifluid", "label": "Trifluid", "short": "T.Flu", "category": "recovery", "icon": "trifluid.png"},
	{"id": "kill_all", "label": "Kill All", "short": "Kill", "category": "debug", "icon": "icon.png"},
	# Techniques — offensive
	{"id": "foie", "label": "Foie", "short": "Foie", "category": "technique", "icon": "Foie.png"},
	{"id": "gifoie", "label": "Gifoie", "short": "Gifoie", "category": "technique", "icon": "Gifoie.png"},
	{"id": "rafoie", "label": "Rafoie", "short": "Rafoie", "category": "technique", "icon": "Rafoie.png"},
	{"id": "barta", "label": "Barta", "short": "Barta", "category": "technique", "icon": "Barta.png"},
	{"id": "gibarta", "label": "Gibarta", "short": "Gibarta", "category": "technique", "icon": "Gibarta.png"},
	{"id": "rabarta", "label": "Rabarta", "short": "Rabarta", "category": "technique", "icon": "Rabarta.png"},
	{"id": "zonde", "label": "Zonde", "short": "Zonde", "category": "technique", "icon": "Zonde.png"},
	{"id": "gizonde", "label": "Gizonde", "short": "Gizonde", "category": "technique", "icon": "Gizonde.png"},
	{"id": "razonde", "label": "Razonde", "short": "Razonde", "category": "technique", "icon": "Razonde.png"},
	{"id": "grants", "label": "Grants", "short": "Grants", "category": "technique", "icon": "Grants.png"},
	{"id": "megid", "label": "Megid", "short": "Megid", "category": "technique", "icon": "Megid.png"},
	# Techniques — support
	{"id": "resta", "label": "Resta", "short": "Resta", "category": "technique", "icon": "Resta.png"},
	{"id": "anti", "label": "Anti", "short": "Anti", "category": "technique", "icon": "Anti.png"},
	{"id": "reverser", "label": "Reverser", "short": "Reverser", "category": "technique", "icon": "Reverser.png"},
	{"id": "shifta", "label": "Shifta", "short": "Shifta", "category": "technique", "icon": "Shifta.png"},
	{"id": "deband", "label": "Deband", "short": "Deband", "category": "technique", "icon": "Deband.png"},
	{"id": "jellen", "label": "Jellen", "short": "Jellen", "category": "technique", "icon": "Jellen.png"},
	{"id": "zalure", "label": "Zalure", "short": "Zalure", "category": "technique", "icon": "Zalure.png"},
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
	var data: Dictionary = get_action_data(action_id)
	var icon_file: String = str(data.get("icon", ""))
	if icon_file.is_empty():
		if Engine.get_process_frames() < 3:
			print("[ActionPalette] get_action_icon('%s'): no icon field, data=%s" % [action_id, data])
		return null
	var path: String = ICON_BASE + icon_file
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if Engine.get_process_frames() < 3:
		print("[ActionPalette] get_action_icon('%s'): file not found: %s" % [action_id, path])
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
