extends Node
## ActionPalette — manages the player's configurable action palette.
## 2 pages of 3 action slots, cycled with palette_swap during gameplay.

signal page_changed(new_page: int)
signal config_changed()

const ICON_BASE := "res://assets/ui/psz-palette/"

const ALL_ACTIONS: Array = [
	{"id": "attack", "label": "Attack", "short": "Atk", "category": "combat", "icon": "attack.png"},
	{"id": "strong_attack", "label": "Strong Attack", "short": "S.Atk", "category": "combat", "icon": "strong_attack.png"},
	{"id": "dodge", "label": "Dodge", "short": "Dodge", "category": "combat", "icon": "dodge.png"},
	{"id": "monomate", "label": "Monomate", "short": "Mono", "category": "recovery", "icon": "monomate.png"},
	{"id": "dimate", "label": "Dimate", "short": "Di", "category": "recovery", "icon": "dimate.png"},
	{"id": "trimate", "label": "Trimate", "short": "Tri", "category": "recovery", "icon": "trimate.png"},
	{"id": "monofluid", "label": "Monofluid", "short": "M.Flu", "category": "recovery", "icon": "monofluid.png"},
	{"id": "difluid", "label": "Difluid", "short": "D.Flu", "category": "recovery", "icon": "difluid.png"},
	{"id": "trifluid", "label": "Trifluid", "short": "T.Flu", "category": "recovery", "icon": "trifluid.png"},
	{"id": "sol_atomizer", "label": "Sol Atomizer", "short": "Sol", "category": "recovery", "icon": "sol_atomizer.png"},
	{"id": "star_atomizer", "label": "Star Atomizer", "short": "Star", "category": "recovery", "icon": "star_atomizer.png"},
	{"id": "moon_atomizer", "label": "Moon Atomizer", "short": "Moon", "category": "recovery", "icon": "moon_atomizer.png"},
	{"id": "telepipe", "label": "Telepipe", "short": "Pipe", "category": "recovery", "icon": "telepipe.png"},
	{"id": "kill_all", "label": "Kill All", "short": "Kill", "category": "debug", "icon": "attack.png"},
	# Techniques — base only; charged variants accessed via hold-to-charge
	{"id": "foie", "label": "Foie", "short": "Foie", "category": "technique", "icon": "foie.png"},
	{"id": "barta", "label": "Barta", "short": "Barta", "category": "technique", "icon": "barta.png"},
	{"id": "zonde", "label": "Zonde", "short": "Zonde", "category": "technique", "icon": "zonde.png"},
	{"id": "grants", "label": "Grants", "short": "Grants", "category": "technique", "icon": "grants.png"},
	{"id": "megid", "label": "Megid", "short": "Megid", "category": "technique", "icon": "megid.png"},
	# Techniques — support
	{"id": "resta", "label": "Resta", "short": "Resta", "category": "technique", "icon": "resta.png"},
	{"id": "anti", "label": "Anti", "short": "Anti", "category": "technique", "icon": "anti.png"},
	{"id": "reverser", "label": "Reverser", "short": "Reverser", "category": "technique", "icon": "resta.png"},
	{"id": "shifta", "label": "Shifta", "short": "Shifta", "category": "technique", "icon": "shifta.png"},
	{"id": "deband", "label": "Deband", "short": "Deband", "category": "technique", "icon": "deband.png"},
	{"id": "jellen", "label": "Jellen", "short": "Jellen", "category": "technique", "icon": "jellen.png"},
	{"id": "zalure", "label": "Zalure", "short": "Zalure", "category": "technique", "icon": "zalure.png"},
]

const CHARGE_ICONS := {
	"attack": "charged_photon_art.png",
	"strong_attack": "charged_photon_art.png",
	"foie": "charged_foie.png",
	"barta": "charged_barta.png",
	"zonde": "charged_zonde.png",
	"grants": "charged_grants.png",
	"megid": "charged_megid.png",
	"resta": "charged_resta.png",
	"anti": "charged_anti.png",
	"shifta": "charged_shifta.png",
	"deband": "charged_deband.png",
	"jellen": "charged_jellen.png",
	"zalure": "charged_zalure.png",
}

const CONSUMABLE_IDS := [
	"monomate", "dimate", "trimate",
	"monofluid", "difluid", "trifluid",
	"sol_atomizer", "star_atomizer", "moon_atomizer",
	"telepipe",
]

const DEFAULT_PAGES: Array = [
	["attack", "strong_attack", "monomate"],
	["attack", "foie", "dimate"],
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


var _icon_debug_done: bool = false

func get_action_icon(action_id: String) -> Texture2D:
	var data: Dictionary = get_action_data(action_id)
	var icon_file: String = str(data.get("icon", ""))
	if icon_file.is_empty():
		if not _icon_debug_done:
			print("[ActionPalette] get_action_icon('%s'): no icon field, data=%s" % [action_id, data])
		return null
	var path: String = ICON_BASE + icon_file
	if ResourceLoader.exists(path):
		if not _icon_debug_done:
			print("[ActionPalette] get_action_icon('%s'): LOADED %s" % [action_id, path])
			_icon_debug_done = true
		return load(path) as Texture2D
	if not _icon_debug_done:
		print("[ActionPalette] get_action_icon('%s'): NOT FOUND %s" % [action_id, path])
	return null


func get_charge_icon(action_id: String) -> Texture2D:
	var icon_file: String = CHARGE_ICONS.get(action_id, "")
	if icon_file.is_empty():
		return null
	var path: String = ICON_BASE + icon_file
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func is_consumable(action_id: String) -> bool:
	return action_id in CONSUMABLE_IDS


func load_from_character(character: Dictionary) -> void:
	var saved: Array = character.get("action_palette", [])
	if saved.size() == 2 and saved[0] is Array and saved[1] is Array:
		pages = saved.duplicate(true)
	else:
		pages = DEFAULT_PAGES.duplicate(true)
	current_page = 0
	config_changed.emit()
	page_changed.emit(0)
