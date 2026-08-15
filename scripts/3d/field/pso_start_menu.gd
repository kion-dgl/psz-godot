extends CanvasLayer
## PSO-style start menu — global autoload, non-pausing overlay with L-shaped backdrop.
## Player can walk around with analog stick while d-pad navigates menu.
## Toggle with Start/ESC.  Sub-views: Items, Equip, Techs, Palette, Mags, Quest, System.
## Registered as autoload so it works in both field and city.

signal closed()
## Emitted when the menu opens. There was no project-wide "menu open" signal
## (mobile_controls polls is_open() for this reason); added so the player can
## drop an in-progress technique charge on menu open (#352).
signal opened()

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

# ── Layout ──────────────────────────────────────────────────────────────────────
const VIEWPORT_W := 1280.0
const VIEWPORT_H := 720.0
const LEFT_W := 240.0       # Left backdrop strip
const BOTTOM_H := 320.0     # Bottom backdrop strip
const HUD_STATS_LAYER := 200  # HUD stats drawn above start menu
const PAD := 12.0           # Inner padding

const STATS_BG: Texture2D = preload("res://assets/ui/stats.png")
const MAIN_BG: Texture2D = preload("res://assets/ui/main.png")

# ── Colors ──────────────────────────────────────────────────────────────────────
const C_BACKDROP := Color(0.16, 0.24, 0.39, 0.82)
const C_BACKDROP_BORDER := Color(0.39, 0.59, 0.82, 0.6)
## Subtle CRT scanline overlay painted on top of the backdrop rects.
const C_SCANLINE := Color(0, 0, 0, 0.12)
const SCANLINE_SPACING := 3  # 1 dim line every N pixels
const C_PANEL := Color(0.78, 0.84, 0.92, 0.92)
const C_PANEL_BORDER := Color(0.47, 0.63, 0.82, 0.7)
const C_TEXT := Color(0.10, 0.15, 0.25)
const C_TEXT_MUTED := Color(0.29, 0.35, 0.47)
# Grey for DISABLED inventory rows (cannot-use / already-known disks). This is
# the SAME value the 2D shops mute their rows with (PszStyle.TEXT_MUTED), so an
# already-known disk greys identically whether the player sees it in the start
# menu or a shop list (#417 — Rozalin: "the graying color isn't identical between
# the two"). Single source of truth → they can't drift. Disabled rows also dim
# their icon (PszStyle.DISABLED_ICON_MOD), matching the shop.
const C_TEXT_DISABLED := PszStyle.TEXT_MUTED
const C_TEXT_LIGHT := Color(0.91, 0.93, 0.97)
const C_SELECT := Color(0.88, 0.53, 0.13)
const C_SELECT_TEXT := Color.WHITE
const C_HP := Color(0.16, 0.72, 0.28)
const C_PP := Color(0.16, 0.47, 0.85)
const C_LABEL_BG := Color(0.20, 0.29, 0.47, 0.9)
const C_ICON_BG := Color(0.91, 0.93, 0.96)
const C_ICON_FG := Color(0.17, 0.23, 0.31)

const FONT_SIZE := 15
const FONT_SIZE_SM := 13
const FONT_SIZE_XS := 11
const FONT_SIZE_LG := 17
## Inventory item-name size — matches the 2D shop row name size (PszStyle.FONT_ITEM)
## so the start-menu items list and the shop lists read at the same weight (#417).
const FONT_SIZE_ITEM := 14

# ── State ───────────────────────────────────────────────────────────────────────
enum Mode { MAIN, ITEMS, ITEMS_MOVE, EQUIP, EQUIP_PICK, TECHS, PALETTE, PALETTE_PICK, MAGS, MAG_FEED, QUEST, SYSTEM, OPTIONS, DEBUG }

var _mode: Mode = Mode.MAIN
var _menu_idx: int = 0
var _info_page: int = 0
var _sub_idx: int = 0
var _equip_slot_idx: int = 0
var _equip_item_idx: int = 0
var _pal_page_idx: int = 0
var _pal_slot_idx: int = 0
var _mag_idx: int = 0
var _mag_feed_idx: int = 0
var _options_idx: int = 0
var _debug_idx: int = 0
var _debug_msg: String = ""  # One-shot result line for a Debug action (e.g. Unlock All), cleared on nav
var _action_message: String = ""  # One-shot message after Items use, cleared on navigation
var _move_from_idx: int = -1  # Origin row when in Mode.ITEMS_MOVE (Manual sort)
var _move_from_id: String = ""  # Origin item id, used to relocate cursor after move

var _canvas: Control  # Child control for drawing
var _is_open: bool = false
var _icon_cache: Dictionary = {}  # action_id → Texture2D
var _pal_bg_cache: Dictionary = {}  # palette page_idx → background Texture2D (#421)
var _active_modal: Control = null  # Yes/No confirmation overlay for state-change actions
var _renderer: StartMenuRenderer  # Canvas rendering, extracted to StartMenuRenderer
var _input: StartMenuInput  # Input / navigation routing, extracted to StartMenuInput

# ── Directional scroll repeat ──────────────────────────────────────────────────
# Hold-to-repeat for d-pad AND right stick, shared with the shops/counters via
# NavRepeat (PSO GC timing: ~0.2s hold then 30Hz). Right-stick scroll matches
# the d-pad instead of moving once per deflection.
const NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
var _nav: NavRepeat

## Menu labels built dynamically — Techs hidden for Cast race
func _get_menu_labels() -> Array:
	var labels: Array = ["Items", "Equip"]
	if _can_use_techs():
		labels.append("Techs")
	labels.append_array(["Palette", "Mags", "Quest", "System"])
	return labels

func _can_use_techs() -> bool:
	var ch := _get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data and class_data.race == "Cast":
		return false
	return true
const SYSTEM_LABELS := ["Save", "Return to Title", "Options", "Debug"]
const SYSTEM_DESCS := ["Save your progress.", "Return to the title screen.", "Adjust game settings.", "Debug tools and cheats."]
## Equipment slots are built dynamically from the equipped frame instance's slots
const TYPE_ICONS := {"weapon": "W", "armor": "A", "shield": "S", "unit": "U", "tool": "T", "tech": "M", "material": "R", "mag": "G"}
const TYPE_COLORS := {
	"weapon": Color(0.8, 0.27, 0.27), "armor": Color(0.27, 0.53, 0.8),
	"shield": Color(0.27, 0.67, 0.67), "unit": Color(0.53, 0.27, 0.67),
	"tool": Color(0.27, 0.67, 0.27), "tech": Color(0.67, 0.27, 0.8),
	"material": Color(0.67, 0.53, 0.2), "mag": Color(0.8, 0.53, 0.27),
}



func _ready() -> void:
	layer = 150
	name = "PsoStartMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Action-palette icons load lazily via _get_action_icon — they live in
	# the R2 asset pack which mounts after this autoload _ready runs, so a
	# pre-cache pass here would just store nulls.
	print("[PsoStartMenu] Ready — layer %d" % layer)

	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_renderer = StartMenuRenderer.new(self)
	_input = StartMenuInput.new(self)
	# Shared hold-to-repeat (d-pad + right stick). Repeats route back through the
	# input handler; the initial d-pad/keyboard press still arrives via the
	# normal event flow, so only the right stick's first move is synthesized here.
	_nav = NavRepeat.new(NAV_ACTIONS, _input._dispatch_ui_action)
	_canvas.draw.connect(_renderer._draw_menu)
	add_child(_canvas)

	# An area transition is a full change_scene_to_file: this autoload survives
	# the tree rebuild, but its canvas only repaints on input/open. If the menu
	# was open on the Palette page across a warp, the canvas could repaint at a
	# moment a fresh load() of the background transiently missed and never repaint
	# again until input — the player had to exit/re-enter the page to recover it
	# (#421). Re-issue a redraw on the area-load signal so an open menu repaints
	# in place from the cached background. SceneManager is registered before this
	# autoload (project.godot order), so it is ready here.
	if SceneManager and not SceneManager.scene_changed.is_connected(_on_scene_changed_rebind):
		SceneManager.scene_changed.connect(_on_scene_changed_rebind)


## Repaint the menu when an area transition rebuilds the scene tree. Guarded on
## _is_open so push_scene overlays (which also emit scene_changed) don't trigger
## spurious redraws on a closed menu. The cached palette background (#421) means
## this redraw re-binds the image from memory and can never silently skip it.
func _on_scene_changed_rebind(_scene_path: String) -> void:
	if _is_open and _canvas:
		_canvas.queue_redraw()
		print("[sanity] checkpoint: start-menu-rebind")


func _process(delta: float) -> void:
	# Tick repeat only while open; reset when closed so the right stick stays
	# free for camera control in gameplay.
	if _nav:
		if _is_open:
			_nav.tick(delta)
		else:
			_nav.reset()


## Open a multi-button ChoiceDialog. The callback receives the chosen
## index (into the original `choices` array). On cancel the modal just
## closes. Used for the unified inventory item menu (Equip / Use / Drop
## / Sort) and its Sort sub-menu (Auto / Manual).
func _open_choice(prompt: String, choices: Array, on_chosen: Callable) -> void:
	var modal := ChoiceDialog.new()
	modal.chosen.connect(func(idx: int) -> void:
		_active_modal = null
		on_chosen.call(idx)
		_canvas.queue_redraw()
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
		_canvas.queue_redraw()
	)
	_active_modal = modal
	_canvas.add_child(modal)
	modal.ask(prompt, choices)


## Inventory item modal: show Equip/Unequip, Use, Drop, Sort filtered by
## what applies to this item. Replaces #208's per-action Yes/No flow —
## the modal action button IS the commit point. Disabled options render
## greyed in PSO style (e.g. "Drop" is greyed for equipped gear).
func _open_item_menu(item: Dictionary) -> void:
	var item_id: String = str(item.get("id", ""))
	var item_name: String = str(item.get("name", item_id))
	var category: String = str(item.get("category", "Other"))
	var equipped: bool = bool(item.get("equipped", false))
	var usable: bool = bool(item.get("usable", false))
	var equippable: bool = category in ["Weapon", "Armor", "Unit", "Mag"]

	var choices: Array = []
	var actions: Array = []
	if equippable:
		if equipped:
			choices.append({"label": "Unequip", "enabled": true})
			actions.append("unequip")
		else:
			choices.append({"label": "Equip", "enabled": _can_equip_from_inventory(item)})
			actions.append("equip")
	elif usable:
		choices.append({"label": "Use", "enabled": true})
		actions.append("use")
	choices.append({"label": "Drop", "enabled": not equipped})
	actions.append("drop")
	choices.append({"label": "Sort", "enabled": Inventory._items.size() > 1})
	actions.append("sort")

	_open_choice(item_name, choices, func(idx: int) -> void:
		var action: String = str(actions[idx]) if idx < actions.size() else ""
		match action:
			"equip": _equip_from_inventory(item)
			"unequip": _unequip_from_inventory(item)
			"use": _execute_use_item(item_id, item_name)
			"drop": _drop_inventory_item(item)
			"sort": _open_sort_menu()
	)


## Sort sub-modal (one-shot): Auto rebuilds in canonical order,
## Manual enters Mode.ITEMS_MOVE so the player picks a destination row
## and the selected item moves there (items shift around it).
func _open_sort_menu() -> void:
	var choices: Array = [
		{"label": "Auto", "enabled": true},
		{"label": "Manual", "enabled": Inventory._items.size() > 1},
	]
	_open_choice("Sort Items", choices, func(idx: int) -> void:
		match idx:
			0:
				Inventory.sort_in_place()
				# Persist immediately. Without this, sort_in_place mutates only
				# the runtime Inventory._items dict — set_active_slot syncs that
				# back into the character record on slot-change (so returning
				# to title and re-selecting preserves the order), but the JSON
				# on disk doesn't get rewritten until a separate save event
				# fires, and a hard reboot in between loses the new order.
				# Reported by Rozalin 2026-05-09.
				SaveManager.save_game()
				_action_message = "Inventory sorted."
				SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			1:
				_enter_move_mode()
	)


func _enter_move_mode() -> void:
	var inv := _get_inventory()
	if _sub_idx >= inv.size():
		return
	_move_from_idx = _sub_idx
	_move_from_id = str(inv[_sub_idx].get("id", ""))
	_mode = Mode.ITEMS_MOVE
	_action_message = "Pick a position — Accept moves here, Cancel exits."


func _exit_move_mode() -> void:
	_move_from_idx = -1
	_move_from_id = ""
	_mode = Mode.ITEMS


func _do_move() -> void:
	var inv := _get_inventory()
	if _sub_idx >= inv.size() or _move_from_id.is_empty():
		_exit_move_mode()
		return
	if _sub_idx == _move_from_idx:
		# Same row — treat as cancel.
		_exit_move_mode()
		return
	Inventory.move_item(_move_from_id, _sub_idx)
	# Cursor follows the moved item — after move the moved row is at
	# _sub_idx (Inventory.move_item lands the moved id at exactly the
	# target visual index), so no cursor adjustment needed.
	# Persist for the same reason as the auto-sort branch above —
	# otherwise a hard reboot loses the new ordering.
	SaveManager.save_game()
	_action_message = "Moved."
	_exit_move_mode()


func _find_idx_for_id(item_id: String) -> int:
	if item_id.is_empty():
		return -1
	var inv := _get_inventory()
	for i in range(inv.size()):
		if str(inv[i].get("id", "")) == item_id:
			return i
	return -1


## Equip the selected inventory item into its natural slot. Mirrors
## _do_equip's body but takes the slot key from the item's category
## instead of from the EQUIP_PICK indices, so it can be invoked from
## the inventory item modal without the player walking through the
## Equip submenu.
func _equip_from_inventory(item: Dictionary) -> void:
	var slot_key := _slot_key_for_inventory_item(item)
	if slot_key.is_empty():
		_action_message = "No slot available."
		return
	var ch := _get_character()
	if ch.is_empty():
		return
	var equip: Dictionary = ch.get("equipment", {})
	var item_id: String = str(item.get("id", ""))
	# Changing to a different frame clears every equipped unit (spec: /mechanics/inventory).
	if slot_key == "frame" and item_id != str(equip.get("frame", "")):
		_clear_all_units(equip)
	equip[slot_key] = item_id
	_commit_equipment(ch, equip, slot_key, "Equipped %s." % str(item.get("name", item_id)))


func _unequip_from_inventory(item: Dictionary) -> void:
	var ch := _get_character()
	if ch.is_empty():
		return
	var equip: Dictionary = ch.get("equipment", {})
	var item_id: String = str(item.get("id", ""))
	var slot_key := ""
	for key in equip:
		if str(equip[key]) == item_id:
			slot_key = str(key)
			break
	if slot_key.is_empty():
		return
	equip[slot_key] = ""
	if slot_key == "frame":
		_clear_all_units(equip)
	_commit_equipment(ch, equip, slot_key, "Unequipped %s." % str(item.get("name", item_id)))


## Empty all four unit slots (frame changes clear units — spec /mechanics/inventory).
func _clear_all_units(equip: Dictionary) -> void:
	for i in range(4):
		equip["unit%d" % (i + 1)] = ""


## Write the equipment dict back to the character, refresh the held weapon/mag
## model when those slots changed, and set the action-bar message.
func _commit_equipment(ch: Dictionary, equip: Dictionary, slot_key: String, message: String) -> void:
	ch["equipment"] = equip
	var player_node = get_tree().get_first_node_in_group("player")
	if slot_key == "weapon" and player_node and player_node.has_method("refresh_weapon"):
		player_node.refresh_weapon()
	if slot_key == "mag" and player_node and player_node.has_method("refresh_mag"):
		player_node.refresh_mag()
	_action_message = message


func _drop_inventory_item(item: Dictionary) -> void:
	var item_id: String = str(item.get("id", ""))
	if item_id.is_empty():
		return
	var item_name: String = str(item.get("name", item_id))
	Inventory.remove_item(item_id, 1)
	_action_message = "Dropped %s." % item_name
	var inv_size: int = _get_inventory().size()
	if _sub_idx >= inv_size:
		_sub_idx = maxi(inv_size - 1, 0)


func _can_equip_from_inventory(item: Dictionary) -> bool:
	return not _slot_key_for_inventory_item(item).is_empty()


## Pick the slot key this inventory item would equip into. Empty string
## means "no available slot for this item right now" (e.g. no free Unit
## slot, or a class can't equip this weapon type).
func _slot_key_for_inventory_item(item: Dictionary) -> String:
	var ch := _get_character()
	if ch.is_empty():
		return ""
	var equip: Dictionary = ch.get("equipment", {})
	var category: String = str(item.get("category", ""))
	var item_id: String = str(item.get("id", ""))
	# Legality routes through the single canonical gate (EquipmentUtils.item_fits_slot
	# → class weapon-type gate / armor class list, honoring DebugConfig.equip_all;
	# spec /mechanics/equip-legality) so this equip action can NEVER disagree with the
	# ✕ "cannot equip" markers the shops, storage, and the items list show. Returning
	# "" disables the Equip choice for gear the class can't use.
	match category:
		"Weapon":
			return "weapon" if EquipmentUtils.item_fits_slot(item_id, "weapon") else ""
		"Armor":
			return "frame" if EquipmentUtils.item_fits_slot(item_id, "frame") else ""
		"Unit":
			for i in range(4):
				var key := "unit%d" % (i + 1)
				if str(equip.get(key, "")).is_empty():
					return key
			return ""
		"Mag":
			return "mag"
	return ""


func open() -> void:
	if _is_open:
		return
	SfxManager.play("res://assets/sfx/ui/menu_open.wav")
	GameState.push_modal()
	_is_open = true
	visible = true
	_mode = Mode.MAIN
	_menu_idx = 0
	# Reset all per-mode cursor state so reopening always lands on a clean
	# main menu and doesn't resume in a sub-mode the player already backed out of.
	_sub_idx = 0
	_equip_slot_idx = 0
	_equip_item_idx = 0
	_pal_page_idx = 0
	_pal_slot_idx = 0
	_mag_idx = 0
	_mag_feed_idx = 0
	_options_idx = 0
	_debug_idx = 0
	_debug_msg = ""
	_action_message = ""
	_canvas.queue_redraw()
	print("[PsoStartMenu] Opened")
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	SfxManager.play("res://assets/sfx/ui/menu_close.wav")
	GameState.pop_modal()
	_is_open = false
	visible = false
	closed.emit()


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


# ── Input ───────────────────────────────────────────────────────────────────────
# Thin delegator — the engine calls this on the Node; the actual routing lives
# in StartMenuInput (a RefCounted, so it gets no lifecycle callbacks).
func _unhandled_input(event: InputEvent) -> void:
	if _input: _input.handle_input(event)


func _do_equip() -> void:
	var slots := _get_equip_slots()
	if _equip_slot_idx >= slots.size():
		_mode = Mode.EQUIP
		return
	var candidates := _get_equip_candidates(_equip_slot_idx)
	if _equip_item_idx >= candidates.size():
		_mode = Mode.EQUIP
		return

	var ch := _get_character()
	if ch.is_empty():
		_mode = Mode.EQUIP
		return

	var equip: Dictionary = ch.get("equipment", {})
	var slot_key: String = str(slots[_equip_slot_idx].get("key", ""))
	var item: Dictionary = candidates[_equip_item_idx]
	var item_id: String = str(item.get("id", ""))

	if item_id == "__unequip__":
		equip[slot_key] = ""
		if slot_key == "frame":
			for i in range(4):
				equip["unit%d" % (i + 1)] = ""
	elif item.get("equipped", false):
		pass  # Already equipped, no-op
	else:
		equip[slot_key] = item_id
		# A frame change clears every equipped unit (spec: /mechanics/inventory).
		if slot_key == "frame":
			for i in range(4):
				equip["unit%d" % (i + 1)] = ""

	ch["equipment"] = equip

	# Notify player of weapon/mag changes
	var player_node = get_tree().get_first_node_in_group("player")
	if slot_key == "weapon" and player_node and player_node.has_method("refresh_weapon"):
		player_node.refresh_weapon()
	if slot_key == "mag" and player_node and player_node.has_method("refresh_mag"):
		player_node.refresh_mag()

	_mode = Mode.EQUIP
	_sub_idx = _equip_slot_idx


## The palette picker grid — the SINGLE source of truth for what the picker
## shows, in what order, and what selecting a cell assigns. Rows 0.._PAL_LEFT_COL_SIZE-1
## draw in the left column, the rest in the right.
##
## This used to be duplicated in start_menu_renderer.gd (as two per-column
## consts) and coupled BY POSITION to ActionPalette.ALL_ACTIONS — the picker
## navigated this grid but assigned ALL_ACTIONS[flat_index]. Inserting an entry
## anywhere in ALL_ACTIONS silently shifted every later cell onto the wrong
## action (#575 added four traps and made "Foie" assign "Ice Trap"). Selection
## now resolves through the id in this table, so the two lists no longer have to
## agree on order — but an action missing from here is unreachable, which
## test_runner's palette-grid test pins.
const _PAL_PICKER_ROWS: Array = [
	{"label": "Combat", "ids": ["attack", "strong_attack", "dodge"]},
	{"label": "Recovery", "ids": ["monomate", "dimate", "trimate"]},
	{"ids": ["monofluid", "difluid", "trifluid"]},
	{"ids": ["sol_atomizer", "star_atomizer", "moon_atomizer"]},
	{"ids": ["telepipe", "kill_all"]},
	# Traps sit opposite Technique on purpose: they are the CAST counterpart to
	# techniques (a CAST can't cast, and only a CAST places traps).
	{"label": "Traps", "ids": ["heat_trap", "ice_trap", "light_trap", "heal_trap"]},
	{"label": "Technique", "ids": ["foie", "barta", "zonde"]},
	{"ids": ["grants", "megid"]},
	# reverser rides along with the other two support techs. It has been in
	# ALL_ACTIONS but absent from this grid — i.e. unassignable — since the grid
	# was introduced; the row had a free third cell all along.
	{"ids": ["resta", "anti", "reverser"]},
	{"ids": ["shifta", "deband"]},
	{"ids": ["jellen", "zalure"]},
]

const _PAL_LEFT_COL_SIZE: int = 5   # rows 0-4: combat + recovery
const _PAL_RIGHT_COL_SIZE: int = 6  # rows 5-10: traps + techniques


## Flat list of every id in the picker grid, in navigation order. Cell N of the
## picker assigns palette_grid_ids()[N].
static func palette_grid_ids() -> Array:
	var ids: Array = []
	for row in _PAL_PICKER_ROWS:
		for id in row.ids:
			ids.append(str(id))
	return ids


func _adjust_sfx_volume(delta: float) -> void:
	SfxManager.sfx_volume = clampf(SfxManager.sfx_volume + delta, 0.0, 1.0)
	var bus_idx: int = AudioServer.get_bus_index("SFX")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(SfxManager.sfx_volume))
	MusicManager.save_volume_config()


func _adjust_music_volume(delta: float) -> void:
	MusicManager.music_volume = clampf(MusicManager.music_volume + delta, 0.0, 1.0)
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(MusicManager.music_volume))
	MusicManager.save_volume_config()


func _get_options_list() -> Array:
	var on := "ON"
	var off := "OFF"
	var music_pct: int = roundi(MusicManager.music_volume * 100)
	var sfx_pct: int = roundi(SfxManager.sfx_volume * 100)
	var mc := get_node_or_null("/root/MobileControls")
	var mc_state: String = (on if (mc and mc.has_method("is_enabled") and mc.is_enabled()) else off)
	return [
		"Music Volume: %d%%" % music_pct,
		"SFX Volume: %d%%" % sfx_pct,
		"Controls: Reconfigure",
		"On-Screen Controls: %s" % mc_state,
		"Camera Rotation: %s" % ("Inverted" if InputConfig.invert_camera_x else "Direct"),
		"Camera Y-Axis: %s" % (on if InputConfig.enable_camera_y else off),
		"Auto-Sort Inventory: %s" % (on if Inventory.is_auto_sort() else off),
		"CRT Filter: %s" % CrtFilter.get_mode_label(),
	]


## Debug submenu — developer toggles + cheats, split out of Options (#menu-debug).
## Row 0 is the one-shot "Unlock All Missions" action; the rest mirror the
## DebugConfig boolean flags. Kept index-aligned with _toggle_debug().
func _get_debug_list() -> Array:
	var on := "ON"
	var off := "OFF"
	return [
		"Unlock All Missions",
		"Floor Collision: %s" % (on if DebugConfig.show_floor_collision else off),
		"Gate Dots: %s" % (on if DebugConfig.show_gate_dots else off),
		"Hitboxes: %s" % (on if DebugConfig.show_hitboxes else off),
		"Combo Timing: %s" % (on if DebugConfig.show_combo_timing else off),
		"Time + Room: %s" % (on if DebugConfig.show_time_room else off),
		"Frame Profiler: %s" % (on if DebugConfig.profile_frames else off),
		"Show Player Position: %s" % (on if DebugConfig.show_player_position else off),
		"Equip All (debug): %s" % (on if DebugConfig.equip_all else off),
		"Reveal Map (debug): %s" % (on if DebugConfig.reveal_map else off),
		"Unlock All Areas (warp): %s" % (on if DebugConfig.unlock_all_areas else off),
	]


func _toggle_option(idx: int) -> void:
	match idx:
		0: _adjust_music_volume(0.1)
		1: _adjust_sfx_volume(0.1)
		2:
			# "Reconfigure Controls" — close the start menu (this is an
			# autoload CanvasLayer at layer 150, so change_scene_to_file
			# wouldn't take it down), nuke the saved config, and push
			# input_select as an overlay via SceneManager so the gameplay
			# scene underneath is preserved. input_select._finish() pops
			# the overlay when done and the player lands back where they
			# were instead of getting dumped to the title.
			close()
			InputConfig.clear()
			SceneManager.push_scene("res://scenes/2d/input_select.tscn")
		3:
			var mc := get_node_or_null("/root/MobileControls")
			if mc and mc.has_method("toggle"):
				mc.toggle()
		4: InputConfig.toggle_invert_camera_x()
		5: InputConfig.toggle_enable_camera_y()
		6:
			Inventory.set_auto_sort(not Inventory.is_auto_sort())
			# Persist the toggle + the immediate re-sort it triggers. Without
			# this the change lived only in memory: it survived a return-to-title
			# (state not wiped) but a reboot loaded the old save — i.e. it never
			# actually saved. Manual Sort/Move already save_game (above); the
			# option toggle was the gap.
			SaveManager.save_game()
		7:
			# CrtFilter persists itself to user://video_settings.cfg — a video
			# setting belongs to the machine, not to the character, so it
			# deliberately does NOT ride along with SaveManager.save_game().
			CrtFilter.cycle(1)


## Dispatch a Debug-submenu row. Index-aligned with _get_debug_list().
func _toggle_debug(idx: int) -> void:
	_debug_msg = ""
	match idx:
		0:
			var n: int = GameState.unlock_all_missions()
			SaveManager.save_game()
			SfxManager.play("res://assets/sfx/ui/game_saved.wav")
			_debug_msg = "Unlocked all missions (%d newly cleared)." % n
		1: DebugConfig.show_floor_collision = not DebugConfig.show_floor_collision
		2: DebugConfig.show_gate_dots = not DebugConfig.show_gate_dots
		3: DebugConfig.show_hitboxes = not DebugConfig.show_hitboxes
		4: DebugConfig.show_combo_timing = not DebugConfig.show_combo_timing
		5:
			DebugConfig.show_time_room = not DebugConfig.show_time_room
			TimeManager.show_hud(DebugConfig.show_time_room)
		6:
			DebugConfig.profile_frames = not DebugConfig.profile_frames
		7:
			DebugConfig.show_player_position = not DebugConfig.show_player_position
		8:
			DebugConfig.equip_all = not DebugConfig.equip_all
		9:
			DebugConfig.reveal_map = not DebugConfig.reveal_map
		10:
			DebugConfig.unlock_all_areas = not DebugConfig.unlock_all_areas
			_debug_msg = (
				"Every field listed in the city warp."
				if DebugConfig.unlock_all_areas
				else "Warp back to quest-unlocked fields only."
			)


func _enter_sub(idx: int) -> void:
	_sub_idx = 0
	var labels := _get_menu_labels()
	if idx >= labels.size():
		return
	var label: String = labels[idx]
	match label:
		"Items": _mode = Mode.ITEMS
		"Equip": _mode = Mode.EQUIP; _equip_slot_idx = 0
		"Techs": _mode = Mode.TECHS
		"Palette": _mode = Mode.PALETTE; _pal_page_idx = 0; _pal_slot_idx = 0
		"Mags": _mode = Mode.MAGS; _mag_idx = 0
		"Quest": _mode = Mode.QUEST
		"System": _mode = Mode.SYSTEM


func _sub_accept() -> void:
	match _mode:
		Mode.ITEMS:
			var inv := _get_inventory()
			if _sub_idx < inv.size():
				_open_item_menu(inv[_sub_idx])
		Mode.EQUIP:
			var slots := _get_equip_slots()
			_equip_slot_idx = _sub_idx
			_equip_item_idx = 0
			if _equip_slot_idx < slots.size():
				_mode = Mode.EQUIP_PICK
		Mode.TECHS:
			var techs := _get_techniques()
			if _sub_idx < techs.size():
				var tech: Dictionary = techs[_sub_idx]
				if tech.get("learned", false) and _is_in_field():
					var tech_id: String = str(tech.get("id", ""))
					var player_node = get_tree().get_first_node_in_group("player")
					if player_node and player_node.has_method("_cast_technique"):
						player_node._cast_technique(tech_id)
		Mode.MAGS:
			_mag_idx = _sub_idx
			_mag_feed_idx = 0
			_sub_idx = 0
			_mode = Mode.MAG_FEED
		Mode.MAG_FEED:
			_do_feed_mag()


## Run the actual Inventory.use_item() call after the player confirms via
## the modal in _sub_accept Mode.ITEMS. Sets _action_message so the menu
## redraws with the result line.
func _execute_use_item(item_id: String, item_name: String) -> void:
	var ok := Inventory.use_item(item_id)
	if ok:
		var info: Dictionary = Inventory.get_last_use_info()
		var t: String = str(info.get("type", ""))
		match t:
			"hp": _action_message = "Restored %d HP" % int(info.get("amount", 0))
			"pp": _action_message = "Restored %d PP" % int(info.get("amount", 0))
			"tech": _action_message = "Learned %s!" % item_name
			"telepipe": _action_message = "Telepipe placed — step into it to warp"
			_: _action_message = "Used %s" % item_name
	else:
		# Telepipe fails specifically when the player tries to use one
		# outside a field (e.g. opened the start menu while in city).
		# Give a clearer hint rather than the generic "Couldn't use".
		var fail_info: Dictionary = Inventory.get_last_use_info()
		if str(fail_info.get("type", "")) == "telepipe_fail":
			_action_message = "Telepipe only works in the field"
		else:
			_action_message = "Couldn't use %s" % item_name


func _do_feed_mag() -> void:
	var feed := _get_feed_items()
	if _sub_idx >= feed.size():
		return
	var mags := _get_mags()
	if _mag_idx >= mags.size():
		return
	var ch := _get_character()
	if ch.is_empty():
		return
	var mag_id: String = str(mags[_mag_idx].get("id", ""))
	var mag_state: Dictionary = MagManager.get_mag_state(ch, mag_id)
	if mag_state.is_empty():
		return
	var item: Dictionary = feed[_sub_idx]
	var item_id: String = str(item.get("id", ""))
	var result: Dictionary = MagManager.feed_mag(mag_state, item_id)
	if result.get("success", false):
		SfxManager.play("res://assets/sfx/ui/mag_feed.wav")
		Inventory.remove_item(item_id, 1)


func _go_back() -> void:
	match _mode:
		Mode.EQUIP_PICK: _mode = Mode.EQUIP
		Mode.PALETTE_PICK: _mode = Mode.PALETTE
		Mode.MAG_FEED: _mode = Mode.MAGS
		Mode.OPTIONS: _mode = Mode.SYSTEM; _sub_idx = 2
		Mode.ITEMS_MOVE: _exit_move_mode()
		_: _mode = Mode.MAIN


# ── Data helpers ────────────────────────────────────────────────────────────────
func _get_character() -> Dictionary:
	var ch = CharacterManager.get_active_character()
	return ch if ch else {}


func _get_inventory() -> Array:
	## Returns inventory in storage order (pickup-by-default, re-ordered
	## by Auto-Sort Inventory option, by Sort → Auto in the item modal,
	## or by Sort → Manual moves). Inventory.sort_in_place() and
	## Inventory.move_item() handle the actual ordering.
	var items := Inventory.get_all_items()
	# Add category and equipped flags
	var ch := _get_character()
	var equipped_ids: Array = []
	if not ch.is_empty():
		var equip: Dictionary = ch.get("equipment", {})
		for key in equip:
			var eid: String = str(equip.get(key, ""))
			if not eid.is_empty():
				equipped_ids.append(eid)
	for item in items:
		var item_id: String = str(item.get("id", ""))
		item["category"] = _get_item_category(item_id)
		item["equipped"] = item_id in equipped_ids
		# Items the start-menu's "Use" action will dispatch to Inventory.use_item().
		# Add new use-handler ids here when wiring more consumables — see
		# inventory.gd's use_item() switchboard for the dispatch logic.
		# A technique disk is only "usable" when it can actually be learned right
		# now: an already-known-at-level (or too-low-level / class-illegal) disk
		# offers NO Use action — it routes through the same shared predicates that
		# grey its row, so the modal can't offer a Use the row says is disabled.
		var disk_usable: bool = item_id.begins_with("disk_") \
			and not ShopNav.sell_cannot_use(item_id) \
			and not ShopNav.sell_disabled(item_id)
		item["usable"] = (
			Inventory.CONSUMABLE_EFFECTS.has(item_id)
			or disk_usable
			or item_id == "telepipe"
		)
	return items


## Inventory row icon — thin wrapper around InventoryIcons so the
## inventory list can fall back to its colored letter block when the
## helper returns null.
func _get_item_icon(item_id: String, category: String) -> Texture2D:
	return InventoryIcons.for_item(item_id, category)


## Lazy lookup for action-palette icons (Foie / Barta / attack /
## monomate / etc.). These live in the R2 asset pack, which mounts
## after this autoloads _ready runs — so pre-caching at startup yields
## an empty cache. We retry on every miss until the icon resolves, then
## cache the non-null result; nulls are NOT cached so a later mount of
## the pack starts working without restart.
func _get_action_icon(action_id: String) -> Texture2D:
	if action_id.is_empty():
		return null
	if _icon_cache.has(action_id):
		return _icon_cache[action_id]
	var icon: Texture2D = ActionPalette.get_action_icon(action_id)
	if icon:
		_icon_cache[action_id] = icon
	return icon


## Lazy lookup for the Palette HUD-preview background (page 0 → palette_bg.png,
## page 1 → palette_bg_r.png). Cached on this persistent autoload exactly like
## _get_action_icon. The start menu survives change_scene_to_file, so an area
## transition can fire a redraw at a moment a fresh load()/ResourceLoader.exists
## transiently missed — the pre-#421 renderer re-load()ed on every draw and could
## silently skip the background, forcing the player to exit/re-enter the page to
## recover it. Caching the Texture2D ref here means a post-transition redraw
## re-binds from memory and can never skip. Nulls are NOT cached so a later pack
## mount recovers without a restart (mirrors the action-icon contract).
func _get_palette_bg(page_idx: int) -> Texture2D:
	if _pal_bg_cache.has(page_idx):
		return _pal_bg_cache[page_idx]
	var bg_path: String = "res://assets/ui/psz-palette/palette_bg%s.png" % ("_r" if page_idx == 1 else "")
	if not ResourceLoader.exists(bg_path):
		return null
	var tex: Texture2D = load(bg_path)
	if tex:
		_pal_bg_cache[page_idx] = tex
	return tex


## Map an inventory category ("Weapon", "Armor", ...) to one of the
## TYPE_* keys used by the small per-row icon (16x16 colored block +
## letter). Centralized here so _draw_items and _draw_bottom_list agree
## on what icon shows for each category.
func _category_to_type(category: String) -> String:
	match category:
		"Weapon": return "weapon"
		"Armor": return "armor"
		"Unit": return "unit"
		"Mag": return "mag"
		"Disk": return "tech"
		"Consumable": return "tool"
		"Material": return "material"
		"Modifier": return "material"
		"Key Item": return "tool"
	return "tool"


func _get_item_category(item_id: String) -> String:
	# Strip the per-slot instance suffix (frame#2) before the registry lookups,
	# then normalize dash/slash — else a same-stat copy mislabels as Other/tool
	# (the #357 bug; mirrors Inventory.get_item_category).
	var base_id: String = Inventory.get_base_id(item_id)
	var norm_id: String = base_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(base_id) or WeaponRegistry.get_weapon(norm_id):
		return "Weapon"
	if ArmorRegistry.get_armor(base_id) or ArmorRegistry.get_armor(norm_id):
		return "Armor"
	if UnitRegistry.get_unit(base_id) or UnitRegistry.get_unit(norm_id):
		return "Unit"
	if MagManager.is_mag(base_id) or MagManager.is_mag(norm_id):
		return "Mag"
	if item_id.begins_with("disk_"):
		return "Disk"
	if ConsumableRegistry.get_consumable(item_id) or ConsumableRegistry.get_consumable(norm_id):
		return "Consumable"
	if CombatManager.MATERIAL_STAT_MAP.has(item_id) or MaterialRegistry.get_material(item_id):
		return "Material"
	if ModifierRegistry.get_modifier(item_id) or ModifierRegistry.get_modifier(norm_id):
		return "Modifier"
	return "Other"


func _get_techniques() -> Array:
	## Returns all techniques the character's class can use (same list as palette techs).
	## Learned techs show their level, unlearned ones show as disabled.
	var ch := _get_character()
	if ch.is_empty():
		return []
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data == null or class_data.technique_limits.is_empty():
		return []
	var learned: Dictionary = ch.get("techniques", {})
	var result: Array = []
	for tech_id in TechniqueManager.TECHNIQUES:
		var data: Dictionary = TechniqueManager.TECHNIQUES[tech_id]
		# Only base-tier techniques are learnable / shown. The gi-/ra- variants
		# (tier "mid"/"advanced") are charge-only — produced by holding a base
		# tech (CHARGE_MAP), never separate menu entries (matches ActionPalette).
		if str(data.get("tier", "basic")) != "basic":
			continue
		var group: String = str(data.get("group", ""))
		if not class_data.technique_limits.has(group):
			continue
		var max_level: int = int(class_data.technique_limits.get(group, 0))
		if max_level <= 0:
			continue
		var current_level: int = int(learned.get(tech_id, 0))
		result.append({
			"id": tech_id,
			"name": str(data.get("name", tech_id)),
			"level": current_level,
			"max_level": max_level,
			"pp": int(data.get("pp", 0)),
			"learned": current_level > 0,
		})
	return result


func _count_equipped_units(equip: Dictionary) -> int:
	var count: int = 0
	for i in range(4):
		if not str(equip.get("unit%d" % (i + 1), "")).is_empty():
			count += 1
	return count


func _is_gameplay_scene() -> bool:
	## Returns true if we're in a city or field scene (not title/select/create)
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path: String = scene.scene_file_path if "scene_file_path" in scene else ""
	if path.is_empty() and scene.has_method("get_scene_file_path"):
		path = scene.get_scene_file_path()
	# Block on menu/UI screens
	var blocked := ["title.tscn", "character_select.tscn", "character_create.tscn"]
	for b in blocked:
		if b in path:
			return false
	# Must have a player in the scene
	return get_tree().get_first_node_in_group("player") != null


func _is_in_field() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("_is_in_city"):
		return not player._is_in_city()
	return false


func _get_equip_slots() -> Array:
	## Build equipment slot list dynamically based on the frame instance's slots
	var ch := _get_character()
	var equip: Dictionary = ch.get("equipment", {})
	var slots: Array = []

	# Weapon
	slots.append({"label": "Weapon", "key": "weapon", "type": "weapon", "item": str(equip.get("weapon", ""))})
	# Frame (armor)
	var frame_id: String = str(equip.get("frame", ""))
	slots.append({"label": "Frame", "key": "frame", "type": "armor", "item": frame_id})

	# Unit slots — count is the equipped frame instance's own rolled slot count
	var unit_count: int = EquipmentUtils.get_unit_slot_count(frame_id, ch)
	for i in range(unit_count):
		var key: String = "unit%d" % (i + 1)
		slots.append({"label": "Unit %d" % (i + 1), "key": key, "type": "unit", "item": str(equip.get(key, ""))})

	# Mag
	slots.append({"label": "Mag", "key": "mag", "type": "mag", "item": str(equip.get("mag", ""))})
	return slots


func _get_equip_candidates(slot_idx: int) -> Array:
	## Build equippable item list for the given slot, matching equipment_screen.gd logic.
	var slots := _get_equip_slots()
	if slot_idx >= slots.size():
		return []
	var slot_key: String = str(slots[slot_idx].get("key", ""))
	var ch := _get_character()
	if ch.is_empty():
		return []
	var equip: Dictionary = ch.get("equipment", {})
	var current_equipped: String = str(equip.get(slot_key, ""))

	# IDs equipped in OTHER slots (exclude from candidates)
	var other_ids: Array = []
	for s in slots:
		var sk: String = str(s.get("key", ""))
		if sk == slot_key:
			continue
		var eid: String = str(equip.get(sk, ""))
		if not eid.is_empty():
			other_ids.append(eid)

	var result: Array = []
	# Show currently equipped first
	if not current_equipped.is_empty():
		var info: Dictionary = Inventory._lookup_item(current_equipped)
		result.append({"id": current_equipped, "name": str(info.get("name", current_equipped)), "equipped": true})

	# Scan inventory for matching items
	for item_id in Inventory._items:
		if item_id == current_equipped:
			continue
		if item_id in other_ids:
			continue
		if EquipmentUtils.item_fits_slot(item_id, slot_key):
			var info: Dictionary = Inventory._lookup_item(item_id)
			result.append({"id": item_id, "name": str(info.get("name", item_id)), "equipped": false})

	# Unequip option if slot is occupied
	if not current_equipped.is_empty():
		result.append({"id": "__unequip__", "name": "-- Unequip --", "equipped": false})

	return result




func _get_mags() -> Array:
	## Scan inventory for all mags, matching mag_list.gd logic.
	var ch := _get_character()
	if ch.is_empty():
		return []
	var equipped_mag: String = str(ch.get("equipment", {}).get("mag", ""))
	var result: Array = []
	for item_id in Inventory._items:
		if not MagManager.is_mag(item_id):
			continue
		var mag_state: Dictionary = MagManager.get_mag_state(ch, item_id)
		var form_id := "mag"
		var level := 0
		if not mag_state.is_empty():
			form_id = str(mag_state.get("form_id", "mag"))
			level = MagManager.get_level(mag_state)
		var form = MagManager.get_mag_form(form_id)
		var form_name: String = form.name if form else "Mag"
		result.append({
			"id": item_id,
			"name": "%s Lv.%d" % [form_name, level],
			"level": level,
			"form_id": form_id,
			"equipped": item_id == equipped_mag,
			"type": "mag",
		})
	# Equipped first, then by level descending
	result.sort_custom(func(a, b):
		if a.equipped != b.equipped:
			return a.equipped
		return int(a.level) > int(b.level)
	)
	return result


func _get_feed_items() -> Array:
	## Get feedable items matching mag_feeder.gd logic
	var result: Array = []
	for item_id in Inventory._items:
		if MagManager.can_feed(item_id):
			var qty: int = int(Inventory._items[item_id])
			var info: Dictionary = Inventory._lookup_item(item_id)
			var effects: Dictionary = MagManager.FEED_EFFECTS.get(item_id, {})
			result.append({"id": item_id, "name": str(info.get("name", item_id)), "quantity": qty, "effects": effects, "type": "tool"})
	return result


func _is_palette_action_available(action_id: String) -> bool:
	if not TechniqueManager.TECHNIQUES.has(action_id):
		return true  # Non-technique actions always available
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	return TechniqueManager.get_technique_level(character, action_id) > 0
