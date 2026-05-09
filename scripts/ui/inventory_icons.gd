class_name InventoryIcons extends Object
## Static helpers that resolve a Texture2D for an inventory row, weapon
## type, or rarity tier — shared between the start menu, storage, and
## the shop screens so every list shows the same iconography.
##
## All icons live under res://assets/ui/pso2/ (sourced from the PSO2
## Arks Visiphone wiki, see SOURCES.md). The lookup priority for
## items is: per-item id → disk_ prefix → category fallback. Weapons
## additionally have a per-weapon-type icon resolved by
## for_weapon_type().
##
## Note: callers that draw into a Control via _draw should call these
## from inside _draw so the cache hit path is fast; callers building
## scene-tree pills should keep one resolved Texture2D per row instead
## of re-resolving on every redraw.

const ITEM_ICON_PATHS := {
	"monomate": "res://assets/ui/pso2/icon_monomate.png",
	"dimate": "res://assets/ui/pso2/icon_dimate.png",
	"trimate": "res://assets/ui/pso2/icon_trimate.png",
	"telepipe": "res://assets/ui/pso2/icon_telepipe.png",
	"scape_doll": "res://assets/ui/pso2/icon_scape_doll.png",
	"sol_atomizer": "res://assets/ui/pso2/icon_sol_atomizer.png",
	"moon_atomizer": "res://assets/ui/pso2/icon_moon_atomizer.png",
	"star_atomizer": "res://assets/ui/pso2/icon_star_atomizer.png",
	"cosmo_atomizer": "res://assets/ui/pso2/icon_cosmo_atomizer.png",
	"shifta_drink": "res://assets/ui/pso2/icon_shifta_drink.png",
	"deband_drink": "res://assets/ui/pso2/icon_deband_drink.png",
	"half_doll": "res://assets/ui/pso2/icon_half_doll.png",
	"challenge_doll": "res://assets/ui/pso2/icon_challenge_doll.png",
}

const CATEGORY_ICON_PATHS := {
	"Disk": "res://assets/ui/pso2/icon_photon_art.png",
	"Mag": "res://assets/ui/pso2/icon_mag.png",
	"Material": "res://assets/ui/pso2/icon_material.png",
	"Modifier": "res://assets/ui/pso2/icon_material.png",
	"Consumable": "res://assets/ui/pso2/icon_tool.png",
	"Armor": "res://assets/ui/pso2/icon_costume.png",
	"Unit": "res://assets/ui/pso2/icon_costume.png",
	"Key Item": "res://assets/ui/pso2/icon_tool.png",
	"Other": "res://assets/ui/pso2/icon_tool.png",
}

## WeaponData.WeaponType enum int → PSO2 weapon-type icon. PSZ's PSO1
## roster doesn't 1:1 with PSO2's, so a few are visual-closest matches.
const WEAPON_TYPE_ICON_PATHS := {
	0: "res://assets/ui/pso2/icon_sword.png",            # SABER
	1: "res://assets/ui/pso2/icon_sword.png",            # SWORD
	2: "res://assets/ui/pso2/icon_twin_daggers.png",     # DAGGERS
	3: "res://assets/ui/pso2/icon_knuckles.png",         # CLAW
	4: "res://assets/ui/pso2/icon_double_saber.png",     # DOUBLE_SABER
	5: "res://assets/ui/pso2/icon_partizan.png",         # SPEAR
	6: "res://assets/ui/pso2/icon_dual_blades.png",      # SLICER
	7: "res://assets/ui/pso2/icon_gunslash.png",         # GUN_BLADE
	8: "res://assets/ui/pso2/icon_tool.png",             # SHIELD
	9: "res://assets/ui/pso2/icon_assault_rifle.png",    # HANDGUN
	10: "res://assets/ui/pso2/icon_twin_machineguns.png",# MECH_GUN
	11: "res://assets/ui/pso2/icon_assault_rifle.png",   # RIFLE
	12: "res://assets/ui/pso2/icon_launcher.png",        # BAZOOKA
	13: "res://assets/ui/pso2/icon_launcher.png",        # LASER_CANNON
	14: "res://assets/ui/pso2/icon_rod.png",             # ROD
	15: "res://assets/ui/pso2/icon_wand.png",            # WAND
}

## Rarity tier → star color icon. PSO2 convention: 1-3 blue, 4-6 green,
## 7-9 red, 10-12 gold, 13+ rainbow. Out-of-range ranks clamp.
const RARITY_BANDS := [
	{"max": 3, "path": "res://assets/ui/pso2/icon_rarity_blue.png"},
	{"max": 6, "path": "res://assets/ui/pso2/icon_rarity_green.png"},
	{"max": 9, "path": "res://assets/ui/pso2/icon_rarity_red.png"},
	{"max": 12, "path": "res://assets/ui/pso2/icon_rarity_gold.png"},
	{"max": 99, "path": "res://assets/ui/pso2/icon_rarity_rainbow.png"},
]

## Process-wide texture cache. Static so every UI screen shares one
## copy of each icon — populated lazily on first call.
static var _cache: Dictionary = {}


## Resolve the row icon for an inventory item. category is the same
## string `Inventory.get_item_category()` returns (Weapon / Armor /
## Disk / Consumable / Mag / etc.). Returns null if nothing matches.
static func for_item(item_id: String, category: String = "") -> Texture2D:
	# Per-item id (with base-id strip for weapons that have an instance
	# suffix like "ein_blade#3").
	var base_id: String = item_id
	var hash_idx: int = item_id.rfind("#")
	if hash_idx >= 0:
		base_id = item_id.substr(0, hash_idx)
	if ITEM_ICON_PATHS.has(base_id):
		return _load(str(ITEM_ICON_PATHS[base_id]))
	if base_id.begins_with("disk_"):
		return _load("res://assets/ui/pso2/icon_photon_art.png")
	# Weapon: per-type icon
	if category == "Weapon" or _is_weapon(base_id):
		var weapon = WeaponRegistry.get_weapon(base_id)
		if weapon == null:
			var norm: String = base_id.replace("-", "_").replace("/", "_")
			weapon = WeaponRegistry.get_weapon(norm)
		if weapon and WEAPON_TYPE_ICON_PATHS.has(int(weapon.weapon_type)):
			return _load(str(WEAPON_TYPE_ICON_PATHS[int(weapon.weapon_type)]))
	# Mag check (covered by category but also by id pattern when caller
	# didn't pass a category).
	if category == "Mag" or MagManager.is_mag(base_id):
		return _load("res://assets/ui/pso2/icon_mag.png")
	# Resolve category from the inventory autoload when caller didn't
	# pass one — this lets shop/storage screens call `for_item(id)`
	# without re-implementing the registry walk.
	if category.is_empty() and not base_id.is_empty():
		category = Inventory.get_item_category(base_id)
	if not category.is_empty() and CATEGORY_ICON_PATHS.has(category):
		return _load(str(CATEGORY_ICON_PATHS[category]))
	return null


## Icon for a specific WeaponData.WeaponType int. Returns null if the
## type isn't mapped (current map covers 0-15, the PSO1 roster).
static func for_weapon_type(weapon_type: int) -> Texture2D:
	if not WEAPON_TYPE_ICON_PATHS.has(weapon_type):
		return null
	return _load(str(WEAPON_TYPE_ICON_PATHS[weapon_type]))


## Tier-banded rarity star icon. Falls back to the rainbow icon for
## anything past 12 stars, blue for anything below 1.
static func for_rarity(rarity: int) -> Texture2D:
	for band in RARITY_BANDS:
		if rarity <= int(band["max"]):
			return _load(str(band["path"]))
	return _load(str(RARITY_BANDS[-1]["path"]))


static func _is_weapon(item_id: String) -> bool:
	if WeaponRegistry.get_weapon(item_id) != null:
		return true
	var norm: String = item_id.replace("-", "_").replace("/", "_")
	return WeaponRegistry.get_weapon(norm) != null


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var tex: Texture2D = load(path) as Texture2D
	_cache[path] = tex
	return tex
