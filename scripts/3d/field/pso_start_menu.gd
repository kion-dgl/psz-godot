extends CanvasLayer
## PSO-style start menu — global autoload, non-pausing overlay with L-shaped backdrop.
## Player can walk around with analog stick while d-pad navigates menu.
## Toggle with Start/ESC.  Sub-views: Items, Equip, Techs, Palette, Mags, Quest, System.
## Registered as autoload so it works in both field and city.

signal closed()

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

# ── State ───────────────────────────────────────────────────────────────────────
enum Mode { MAIN, ITEMS, ITEMS_MOVE, EQUIP, EQUIP_PICK, TECHS, PALETTE, PALETTE_PICK, MAGS, MAG_FEED, QUEST, SYSTEM, OPTIONS }

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
var _item_scroll: float = 0.0  # Pixel scroll offset for items list
var _action_message: String = ""  # One-shot message after Items use, cleared on navigation
var _move_from_idx: int = -1  # Origin row when in Mode.ITEMS_MOVE (Manual sort)
var _move_from_id: String = ""  # Origin item id, used to relocate cursor after move

var _canvas: Control  # Child control for drawing
var _is_open: bool = false
var _icon_cache: Dictionary = {}  # action_id → Texture2D
var _rstick_held: bool = false  # Prevents right stick repeat until released
var _active_modal: Control = null  # Yes/No confirmation overlay for state-change actions

# ── Directional scroll repeat (PSO GC timing) ──────────────────────────────────
# Match PSO's menu scroll: hold 6/30f (~0.2s) before auto-scroll, then 1/30f
# (~0.033s) between ticks. Applies to both keyboard and gamepad so controller
# holds repeat at the same rate as keyboard echo would.
const SCROLL_HOLD := 0.2
const SCROLL_REPEAT := 1.0 / 30.0
const NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
var _nav_hold: Dictionary = {}   # action → seconds currently held
var _nav_next: Dictionary = {}   # action → seconds until next repeat tick

## Menu labels built dynamically — Techs hidden for Cast race
func _get_menu_labels() -> Array:
	var labels: Array = ["Items", "Equip"]
	if _can_use_techs():
		labels.append("Techs")
	labels.append_array(["Palette", "Mags", "Quest", "System"])
	return labels

func _get_menu_descs() -> Array:
	var descs: Array = ["Use items.", "Equip weapons and armor."]
	if _can_use_techs():
		descs.append("Cast techniques.")
	descs.append_array(["Edit the action palette.", "Feed and manage your Mag.", "View current quest objectives.", "System settings and options."])
	return descs

func _can_use_techs() -> bool:
	var ch := _get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data and class_data.race == "Cast":
		return false
	return true
const SYSTEM_LABELS := ["Save", "Return to Title", "Options"]
const SYSTEM_DESCS := ["Save your progress.", "Return to the title screen.", "Adjust game settings."]
## Equipment slots are built dynamically based on equipped armor's max_slots
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
	for action in NAV_ACTIONS:
		_nav_hold[action] = 0.0
		_nav_next[action] = 0.0
	# Action-palette icons load lazily via _get_action_icon — they live in
	# the R2 asset pack which mounts after this autoload _ready runs, so a
	# pre-cache pass here would just store nulls.
	print("[PsoStartMenu] Ready — layer %d" % layer)

	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)


func _process(delta: float) -> void:
	_tick_nav_repeat(delta)


# Synthesize repeated ui_* action events when the player holds a direction,
# matching PSO GC's scroll timing. Works the same for keyboard and gamepad so
# controller users get auto-scroll even though Godot has no built-in gamepad
# echo. Menu handlers use `allow_echo = false` so OS keyboard echo doesn't
# also fire and double the tick rate.
func _tick_nav_repeat(delta: float) -> void:
	if not _is_open:
		for action in NAV_ACTIONS:
			_nav_hold[action] = 0.0
			_nav_next[action] = 0.0
		return
	for action in NAV_ACTIONS:
		if Input.is_action_pressed(action):
			var held: float = float(_nav_hold[action]) + delta
			_nav_hold[action] = held
			if held >= SCROLL_HOLD:
				# Decrement first and dispatch same frame so the effective
				# repeat rate actually is SCROLL_REPEAT, not SCROLL_REPEAT + delta.
				# The while-loop catches up if a long frame skipped multiple ticks.
				var next_at: float = float(_nav_next[action]) - delta
				while next_at <= 0.0:
					_dispatch_ui_action(action)
					next_at += SCROLL_REPEAT
				_nav_next[action] = next_at
		else:
			_nav_hold[action] = 0.0
			_nav_next[action] = 0.0


func _dispatch_ui_action(action: String) -> void:
	## Route a synthetic press directly to our own input handler. Going through
	## Input.parse_input_event would mark the action as globally pressed without
	## a matching release, so Input.is_action_pressed() would return true forever
	## and _tick_nav_repeat would keep dispatching after the player let go.
	# Modal owns input — don't fire menu-scroll synthetic events while a
	# confirm dialog is open, otherwise list cursor moves under the modal.
	if is_instance_valid(_active_modal):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


## Open a Yes/No ConfirmDialog overlay for state-changing actions (equip,
## feed mag, use item). On Yes the callback runs; on No or cancel the
## modal just closes. Adds the modal as a child of `_canvas` so it
## renders on top of the menu's _draw output.
##
## Without this confirmation step, accept-button presses would commit the
## action immediately with only a small inline visual change, which
## playtesters consistently missed (dashgl's 2026-05-07 feedback). The
## modal makes the commit point unmissable.
func _open_confirm(prompt: String, on_confirmed: Callable) -> void:
	var modal := ConfirmDialog.new()
	modal.confirmed.connect(func() -> void:
		_active_modal = null
		on_confirmed.call()
		_canvas.queue_redraw()
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
		_canvas.queue_redraw()
	)
	_active_modal = modal
	_canvas.add_child(modal)
	modal.ask(prompt)


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


func _input_items_move(event: InputEvent) -> bool:
	var count: int = _get_inventory().size()
	if event.is_action_pressed("ui_up", false) and count > 0:
		_sub_idx = wrapi(_sub_idx - 1, 0, count)
		# Recompute move origin index in case the list changed under us.
		_move_from_idx = _find_idx_for_id(_move_from_id)
		return true
	elif event.is_action_pressed("ui_down", false) and count > 0:
		_sub_idx = wrapi(_sub_idx + 1, 0, count)
		_move_from_idx = _find_idx_for_id(_move_from_id)
		return true
	elif event.is_action_pressed("ui_accept"):
		_do_move()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_action_message = ""
		_exit_move_mode()
		return true
	return false


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
	equip[slot_key] = item_id
	if slot_key == "frame":
		var armor = ArmorRegistry.get_armor(item_id)
		var new_max: int = armor.max_slots if armor else 0
		for i in range(4):
			if i >= new_max:
				equip["unit%d" % (i + 1)] = ""
	ch["equipment"] = equip
	var player_node = get_tree().get_first_node_in_group("player")
	if slot_key == "weapon" and player_node and player_node.has_method("refresh_weapon"):
		player_node.refresh_weapon()
	if slot_key == "mag" and player_node and player_node.has_method("refresh_mag"):
		player_node.refresh_mag()
	_action_message = "Equipped %s." % str(item.get("name", item_id))


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
		for i in range(4):
			equip["unit%d" % (i + 1)] = ""
	ch["equipment"] = equip
	var player_node = get_tree().get_first_node_in_group("player")
	if slot_key == "weapon" and player_node and player_node.has_method("refresh_weapon"):
		player_node.refresh_weapon()
	if slot_key == "mag" and player_node and player_node.has_method("refresh_mag"):
		player_node.refresh_mag()
	_action_message = "Unequipped %s." % str(item.get("name", item_id))


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
	match category:
		"Weapon":
			var item_id: String = str(item.get("id", ""))
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				return ""
			var class_data = ClassRegistry.get_class_data(str(ch.get("class_id", "")))
			if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
				return ""
			return "weapon"
		"Armor":
			return "frame"
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
	_item_scroll = 0.0
	_action_message = ""
	_canvas.queue_redraw()
	print("[PsoStartMenu] Opened")


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
func _unhandled_input(event: InputEvent) -> void:
	# Open menu from anywhere with ESC/pause (only when closed, no overlay, and in gameplay)
	if not _is_open:
		if event.is_action_pressed("pause") and SceneManager._overlay_stack.is_empty() and _is_gameplay_scene():
			open()
			get_viewport().set_input_as_handled()
		return

	# Modal owns input. ConfirmDialog uses _input (priority) and calls
	# set_input_as_handled, so events should be swallowed before they
	# reach _unhandled_input — but the synthetic events from
	# _tick_nav_repeat skip _input entirely, so we still need this gate.
	if is_instance_valid(_active_modal):
		return

	# ── Menu is open — consume ALL input except movement ──

	# Joypad Start button always closes the menu, regardless of mode.
	# Checked first because Start and pause share button index 6 — if the pause
	# branch ran first in a sub-mode it would fall through without closing.
	# Enter also maps to the "start" action so we guard on InputEventJoypadButton
	# to keep Enter usable as accept inside menus.
	if event is InputEventJoypadButton and event.is_action_pressed("start"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if _mode == Mode.MAIN:
			close()
			get_viewport().set_input_as_handled()
			return
		# In sub-menus, Esc/pause acts as back (falls through to mode handler)

	# Let movement actions pass through (WASD + left stick)
	if event.is_action("move_forward") or event.is_action("move_backward") or \
	   event.is_action("move_left") or event.is_action("move_right"):
		return  # Don't consume — let player walk

	# LB/RB → page flip when in main view
	if _mode == Mode.MAIN:
		if event.is_action_pressed("palette_swap"):  # LB
			_info_page = wrapi(_info_page - 1, 0, 4)
			_canvas.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("quest_log"):  # RB
			_info_page = wrapi(_info_page + 1, 0, 4)
			_canvas.queue_redraw()
			get_viewport().set_input_as_handled()
			return

	# Right stick Y axis → menu scroll (alternative to d-pad). Active threshold
	# 0.3 so a gentle tilt registers; release threshold 0.15 so the hysteresis
	# band (0.15–0.3) keeps the stick from re-triggering on small oscillations.
	if event is InputEventJoypadMotion:
		var joy: InputEventJoypadMotion = event as InputEventJoypadMotion
		if joy.axis == JOY_AXIS_RIGHT_Y and absf(joy.axis_value) > 0.3:
			# Throttle: only trigger once per stick deflection
			if not _rstick_held:
				_rstick_held = true
				if joy.axis_value > 0:
					_simulate_menu_down()
				else:
					_simulate_menu_up()
				_canvas.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		elif joy.axis == JOY_AXIS_RIGHT_Y and absf(joy.axis_value) < 0.15:
			_rstick_held = false
			# Consume the deadzone-return event after resetting hold state.
			get_viewport().set_input_as_handled()
			return

	# Route to mode-specific handler
	var handled := true
	match _mode:
		Mode.MAIN:
			handled = _input_main(event)
		Mode.ITEMS:
			handled = _input_list(event, _get_inventory().size())
		Mode.ITEMS_MOVE:
			handled = _input_items_move(event)
		Mode.EQUIP:
			handled = _input_list(event, _get_equip_slots().size())
		Mode.EQUIP_PICK:
			handled = _input_equip_pick(event)
		Mode.TECHS:
			handled = _input_list(event, _get_techniques().size())
		Mode.PALETTE:
			handled = _input_palette(event)
		Mode.PALETTE_PICK:
			handled = _input_palette_pick(event)
		Mode.MAGS:
			handled = _input_list(event, _get_mags().size())
		Mode.MAG_FEED:
			handled = _input_list(event, _get_feed_items().size())
		Mode.QUEST:
			handled = _input_back(event)
		Mode.SYSTEM:
			handled = _input_system(event)
		Mode.OPTIONS:
			handled = _input_options(event)

	if handled:
		# Skip generic SFX if menu was just closed — close() plays its own sound
		if not _is_open:
			_canvas.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# Play menu SFX
		if event.is_action_pressed("ui_accept"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		elif event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		elif event.is_action_pressed("ui_up", false) or event.is_action_pressed("ui_down", false) \
			or event.is_action_pressed("ui_left", false) or event.is_action_pressed("ui_right", false):
			SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_canvas.queue_redraw()

	# ALWAYS consume input when menu is open (blocks camera, interact, quick weapon, palette)
	get_viewport().set_input_as_handled()


func _simulate_menu_up() -> void:
	## Simulate pressing ui_up for right stick scroll
	var fake := InputEventAction.new()
	fake.action = "ui_up"
	fake.pressed = true
	_unhandled_input(fake)


func _simulate_menu_down() -> void:
	var fake := InputEventAction.new()
	fake.action = "ui_down"
	fake.pressed = true
	_unhandled_input(fake)


func _input_main(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_menu_idx = wrapi(_menu_idx - 1, 0, _get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_down", false):
		_menu_idx = wrapi(_menu_idx + 1, 0, _get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_left", false):
		_info_page = wrapi(_info_page - 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_right", false):
		_info_page = wrapi(_info_page + 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_accept"):
		_enter_sub(_menu_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		close()
		return true
	return false


func _input_list(event: InputEvent, count: int) -> bool:
	if event.is_action_pressed("ui_up", false) and count > 0:
		_sub_idx = wrapi(_sub_idx - 1, 0, count)
		_action_message = ""
		return true
	elif event.is_action_pressed("ui_down", false) and count > 0:
		_sub_idx = wrapi(_sub_idx + 1, 0, count)
		_action_message = ""
		return true
	elif event.is_action_pressed("ui_accept"):
		_sub_accept()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_action_message = ""
		_go_back()
		return true
	return false


func _input_equip_pick(event: InputEvent) -> bool:
	var candidates := _get_equip_candidates(_equip_slot_idx)
	if event.is_action_pressed("ui_up", false) and candidates.size() > 0:
		_equip_item_idx = wrapi(_equip_item_idx - 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_down", false) and candidates.size() > 0:
		_equip_item_idx = wrapi(_equip_item_idx + 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_do_equip()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.EQUIP
		return true
	return false


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
		if slot_key == "frame":
			var armor = ArmorRegistry.get_armor(item_id)
			var new_max: int = armor.max_slots if armor else 0
			for i in range(4):
				if i >= new_max:
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


func _input_palette(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_pal_slot_idx = wrapi(_pal_slot_idx - 1, 0, 3)
		return true
	elif event.is_action_pressed("ui_down", false):
		_pal_slot_idx = wrapi(_pal_slot_idx + 1, 0, 3)
		return true
	elif event.is_action_pressed("ui_left", false):
		_pal_page_idx = wrapi(_pal_page_idx - 1, 0, ActionPalette.pages.size())
		return true
	elif event.is_action_pressed("ui_right", false):
		_pal_page_idx = wrapi(_pal_page_idx + 1, 0, ActionPalette.pages.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_mode = Mode.PALETTE_PICK
		_sub_idx = 0
		var current_id: String = str(ActionPalette.pages[_pal_page_idx][_pal_slot_idx])
		var actions := _get_palette_actions()
		for i in range(actions.size()):
			if str(actions[i].get("id", "")) == current_id:
				_sub_idx = i
				break
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


const _PAL_PICKER_ROWS: Array = [
	{"label": "Combat", "ids": ["attack", "strong_attack", "dodge"]},
	{"label": "Recovery", "ids": ["monomate", "dimate", "trimate"]},
	{"ids": ["monofluid", "difluid", "trifluid"]},
	{"ids": ["sol_atomizer", "star_atomizer", "moon_atomizer"]},
	{"ids": ["telepipe"]},
	{"label": "Technique", "ids": ["foie", "barta", "zonde"]},
	{"ids": ["grants", "megid"]},
	{"ids": ["resta", "anti"]},
	{"ids": ["shifta", "deband"]},
	{"ids": ["jellen", "zalure"]},
]

func _pal_flat_to_row_col(flat_idx: int) -> Vector2i:
	var fi := 0
	for ri in range(_PAL_PICKER_ROWS.size()):
		var row_ids: Array = _PAL_PICKER_ROWS[ri].ids
		for ci in range(row_ids.size()):
			if fi == flat_idx:
				return Vector2i(ri, ci)
			fi += 1
	return Vector2i(0, 0)

func _pal_row_col_to_flat(row: int, col: int) -> int:
	var fi := 0
	for ri in range(row):
		fi += int(_PAL_PICKER_ROWS[ri].ids.size())
	fi += col
	return fi

func _input_palette_pick(event: InputEvent) -> bool:
	var actions := _get_palette_actions()
	var rc := _pal_flat_to_row_col(_sub_idx)
	if event.is_action_pressed("ui_up", false):
		var new_row: int = wrapi(rc.x - 1, 0, _PAL_PICKER_ROWS.size())
		var new_col: int = clampi(rc.y, 0, int(_PAL_PICKER_ROWS[new_row].ids.size()) - 1)
		_sub_idx = _pal_row_col_to_flat(new_row, new_col)
		return true
	elif event.is_action_pressed("ui_down", false):
		var new_row: int = wrapi(rc.x + 1, 0, _PAL_PICKER_ROWS.size())
		var new_col: int = clampi(rc.y, 0, int(_PAL_PICKER_ROWS[new_row].ids.size()) - 1)
		_sub_idx = _pal_row_col_to_flat(new_row, new_col)
		return true
	elif event.is_action_pressed("ui_left", false):
		var row_ids: Array = _PAL_PICKER_ROWS[rc.x].ids
		var new_col: int = wrapi(rc.y - 1, 0, row_ids.size())
		_sub_idx = _pal_row_col_to_flat(rc.x, new_col)
		return true
	elif event.is_action_pressed("ui_right", false):
		var row_ids: Array = _PAL_PICKER_ROWS[rc.x].ids
		var new_col: int = wrapi(rc.y + 1, 0, row_ids.size())
		_sub_idx = _pal_row_col_to_flat(rc.x, new_col)
		return true
	elif event.is_action_pressed("ui_accept"):
		if _sub_idx < actions.size():
			var action: Dictionary = actions[_sub_idx]
			var action_id: String = str(action.get("id", ""))
			if _is_palette_action_available(action_id):
				ActionPalette.set_action(_pal_page_idx, _pal_slot_idx, action_id)
				_mode = Mode.PALETTE
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.PALETTE
		return true
	return false


func _input_system(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_sub_idx = wrapi(_sub_idx - 1, 0, SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_down", false):
		_sub_idx = wrapi(_sub_idx + 1, 0, SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		match _sub_idx:
			0:
				SaveManager.save_game()
				SfxManager.play("res://assets/sfx/ui/game_saved.wav")
			1:
				SaveManager.save_game()
				SfxManager.play("res://assets/sfx/ui/game_saved.wav")
				close()
				SceneManager.goto_scene("res://scenes/2d/title.tscn")
			2:
				_mode = Mode.OPTIONS
				_options_idx = 0
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


func _input_options(event: InputEvent) -> bool:
	var opts := _get_options_list()
	if event.is_action_pressed("ui_up", false) and opts.size() > 0:
		_options_idx = wrapi(_options_idx - 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_down", false) and opts.size() > 0:
		_options_idx = wrapi(_options_idx + 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_left", false):
		if _options_idx == 0:
			_adjust_music_volume(-0.1)
			return true
		elif _options_idx == 1:
			_adjust_sfx_volume(-0.1)
			return true
		# (Controls: Reconfigure at idx 2 is action-only — Left/Right is a no-op.)
	elif event.is_action_pressed("ui_right", false):
		if _options_idx == 0:
			_adjust_music_volume(0.1)
			return true
		elif _options_idx == 1:
			_adjust_sfx_volume(0.1)
			return true
	elif event.is_action_pressed("ui_accept"):
		_toggle_option(_options_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.SYSTEM
		_sub_idx = 2
		return true
	return false


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
		"Floor Collision: %s" % (on if DebugConfig.show_floor_collision else off),
		"Gate Dots: %s" % (on if DebugConfig.show_gate_dots else off),
		"Hitboxes: %s" % (on if DebugConfig.show_hitboxes else off),
		"Combo Timing: %s" % (on if DebugConfig.show_combo_timing else off),
		"Time + Room: %s" % (on if DebugConfig.show_time_room else off),
		"Frame Profiler: %s" % (on if DebugConfig.profile_frames else off),
		"Show Player Position: %s" % (on if DebugConfig.show_player_position else off),
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
		6: Inventory.set_auto_sort(not Inventory.is_auto_sort())
		7: DebugConfig.show_floor_collision = not DebugConfig.show_floor_collision
		8: DebugConfig.show_gate_dots = not DebugConfig.show_gate_dots
		9: DebugConfig.show_hitboxes = not DebugConfig.show_hitboxes
		10: DebugConfig.show_combo_timing = not DebugConfig.show_combo_timing
		11:
			DebugConfig.show_time_room = not DebugConfig.show_time_room
			TimeManager.show_hud(DebugConfig.show_time_room)
		12:
			DebugConfig.profile_frames = not DebugConfig.profile_frames
		13:
			DebugConfig.show_player_position = not DebugConfig.show_player_position


func _input_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


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
		item["usable"] = (
			Inventory.CONSUMABLE_EFFECTS.has(item_id)
			or item_id.begins_with("disk_")
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
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(item_id) or WeaponRegistry.get_weapon(norm_id):
		return "Weapon"
	if ArmorRegistry.get_armor(item_id) or ArmorRegistry.get_armor(norm_id):
		return "Armor"
	if UnitRegistry.get_unit(item_id) or UnitRegistry.get_unit(norm_id):
		return "Unit"
	if MagManager.is_mag(item_id) or MagManager.is_mag(norm_id):
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
	## Build equipment slot list dynamically based on armor's max_slots
	var ch := _get_character()
	var equip: Dictionary = ch.get("equipment", {})
	var slots: Array = []

	# Weapon
	slots.append({"label": "Weapon", "key": "weapon", "type": "weapon", "item": str(equip.get("weapon", ""))})
	# Frame (armor)
	var frame_id: String = str(equip.get("frame", ""))
	slots.append({"label": "Frame", "key": "frame", "type": "armor", "item": frame_id})

	# Unit slots — count depends on equipped armor's max_slots
	var unit_count: int = 0
	if not frame_id.is_empty():
		var armor_data = ArmorRegistry.get_armor(frame_id) if ArmorRegistry.has_method("get_armor") else null
		if armor_data and "max_slots" in armor_data:
			unit_count = int(armor_data.max_slots)
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
		if _item_fits_slot(item_id, slot_key):
			var info: Dictionary = Inventory._lookup_item(item_id)
			result.append({"id": item_id, "name": str(info.get("name", item_id)), "equipped": false})

	# Unequip option if slot is occupied
	if not current_equipped.is_empty():
		result.append({"id": "__unequip__", "name": "-- Unequip --", "equipped": false})

	return result


func _item_fits_slot(item_id: String, slot_key: String) -> bool:
	match slot_key:
		"weapon":
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				return false
			var character = CharacterManager.get_active_character()
			if character:
				var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
				if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
					return false
			return true
		"frame":
			return ArmorRegistry.has_armor(item_id)
		"unit1", "unit2", "unit3", "unit4":
			return UnitRegistry.get_unit(item_id) != null
		"mag":
			return MagManager.is_mag(item_id)
	return false


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


func _get_palette_actions() -> Array:
	## Returns all assignable actions from ActionPalette.ALL_ACTIONS
	var result: Array = []
	for action in ActionPalette.ALL_ACTIONS:
		result.append(action)
	return result


func _is_palette_action_available(action_id: String) -> bool:
	if not TechniqueManager.TECHNIQUES.has(action_id):
		return true  # Non-technique actions always available
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	return TechniqueManager.get_technique_level(character, action_id) > 0


# ── Drawing ─────────────────────────────────────────────────────────────────────
func _draw_menu() -> void:
	var c := _canvas
	var font := ThemeDB.fallback_font
	var vp := Vector2(VIEWPORT_W, VIEWPORT_H)

	# L-shaped backdrop
	var left_top := Rect2(0, 0, LEFT_W, vp.y - BOTTOM_H)
	var bottom_right := Rect2(LEFT_W, vp.y - BOTTOM_H, vp.x - LEFT_W, BOTTOM_H)
	var bottom_left := Rect2(0, vp.y - BOTTOM_H, LEFT_W, BOTTOM_H)
	c.draw_rect(left_top, C_BACKDROP)
	c.draw_rect(bottom_right, C_BACKDROP)
	c.draw_rect(bottom_left, C_BACKDROP)
	# Subtle scanline overlay
	_draw_scanlines(c, left_top)
	_draw_scanlines(c, bottom_right)
	_draw_scanlines(c, bottom_left)
	# Borders
	c.draw_line(Vector2(LEFT_W, 0), Vector2(LEFT_W, vp.y - BOTTOM_H), C_BACKDROP_BORDER, 1.5)
	c.draw_line(Vector2(LEFT_W, vp.y - BOTTOM_H), Vector2(vp.x, vp.y - BOTTOM_H), C_BACKDROP_BORDER, 1.5)

	# HUD draws its own HP/PP — no duplicate status panel here

	match _mode:
		Mode.MAIN: _draw_main(c, font)
		Mode.ITEMS, Mode.ITEMS_MOVE: _draw_items(c, font)
		Mode.EQUIP, Mode.EQUIP_PICK: _draw_equip(c, font)
		Mode.TECHS: _draw_techs(c, font)
		Mode.PALETTE, Mode.PALETTE_PICK: _draw_palette(c, font)
		Mode.MAGS, Mode.MAG_FEED: _draw_mags(c, font)
		Mode.QUEST: _draw_quest(c, font)
		Mode.SYSTEM: _draw_system(c, font)
		Mode.OPTIONS: _draw_options(c, font)


func _draw_status(c: Control, font: Font, pos: Vector2) -> void:
	var ch := _get_character()
	var w: float = LEFT_W - PAD * 2
	_draw_inner_panel(c, Rect2(pos, Vector2(w, 60)))

	var name_str: String = str(ch.get("name", "Player"))
	c.draw_string(font, pos + Vector2(12, 20), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT)

	# HP bar
	var hp: float = float(ch.get("hp", 100))
	var max_hp: float = float(ch.get("max_hp", 100))
	var hp_pct: float = clampf(hp / maxf(max_hp, 1), 0, 1)
	_draw_bar(c, Rect2(pos.x + 30, pos.y + 28, w - 42, 10), hp_pct, C_HP)
	c.draw_string(font, pos + Vector2(8, 38), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT_MUTED)

	# PP bar
	var pp: float = float(ch.get("pp", 50))
	var max_pp: float = float(ch.get("max_pp", 50))
	var pp_pct: float = clampf(pp / maxf(max_pp, 1), 0, 1)
	_draw_bar(c, Rect2(pos.x + 30, pos.y + 42, w - 42, 10), pp_pct, C_PP)
	c.draw_string(font, pos + Vector2(8, 52), "PP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT_MUTED)


func _draw_bar(c: Control, rect: Rect2, pct: float, color: Color) -> void:
	c.draw_rect(rect, Color(0, 0, 0, 0.15))
	if pct > 0:
		c.draw_rect(Rect2(rect.position, Vector2(rect.size.x * pct, rect.size.y)), color)


func _draw_main(c: Control, font: Font) -> void:
	# Main menu uses the assets/ui/main.png sprite (200×292). Text area inside
	# the sprite: x=12, y=29, 176×233. Selection highlight and menu rows live
	# inside that region.
	var bg_x: float = PAD
	var bg_y: float = 110.0
	c.draw_texture(MAIN_BG, Vector2(bg_x, bg_y))

	var text_x: float = bg_x + 12
	var text_y: float = bg_y + 29
	var text_w: float = 176
	var text_h: float = 233

	# Menu list rows — distribute evenly across the full text area height so
	# we use the space the old description panel took.
	var labels: Array = _get_menu_labels()
	var row_h: float = text_h / float(maxi(labels.size(), 1))
	for i in range(labels.size()):
		var iy: float = text_y + i * row_h
		if i == _menu_idx:
			c.draw_rect(Rect2(text_x + 2, iy, text_w - 4, row_h - 2), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == _menu_idx else C_TEXT
		c.draw_string(font, Vector2(text_x + 12, iy + row_h * 0.7), labels[i], HORIZONTAL_ALIGNMENT_LEFT, text_w - 16, FONT_SIZE_LG, col)

	# Info panel (bottom right)
	_draw_info_panel(c, font)


func _draw_scanlines(c: Control, rect: Rect2) -> void:
	var x1: float = rect.position.x
	var x2: float = rect.position.x + rect.size.x
	var y_end: float = rect.position.y + rect.size.y
	# Start the first line one SPACING in so the very top edge of the rect
	# isn't always painted — otherwise a visible dark seam lands exactly on
	# the bottom-right rect's top border (y = VIEWPORT_H - BOTTOM_H).
	var y: float = rect.position.y + SCANLINE_SPACING
	while y < y_end:
		c.draw_line(Vector2(x1, y), Vector2(x2, y), C_SCANLINE, 1.0)
		y += SCANLINE_SPACING


func _draw_info_panel(c: Control, font: Font) -> void:
	# Stats panel uses the assets/ui/stats.png sprite (440×273, scaled 1.72×
	# from a 256×159 DS source). Layout coords inside the sprite:
	#   page indicator box: x=191, y=24, 65×28 (between the L/R icons)
	#   stat text area:     x=17,  y=58, 402×162
	var px: float = VIEWPORT_W - STATS_BG.get_width() - 50
	var py: float = VIEWPORT_H - STATS_BG.get_height() - 20
	c.draw_texture(STATS_BG, Vector2(px, py))

	# Page selector centered in the indicator box
	var page_label := "%d/4" % [_info_page + 1]
	c.draw_string(font, Vector2(px + 191, py + 44), page_label, HORIZONTAL_ALIGNMENT_CENTER, 65, FONT_SIZE_SM, C_TEXT)

	# Stat rows — pull real data from character + class + equipment
	var ch := _get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	var level: int = int(ch.get("level", 1))
	var equip: Dictionary = ch.get("equipment", {})

	# Base stats from class at current level
	var base_hp: int = class_data.get_stat_at_level("hp", level) if class_data else 0
	var base_pp: int = class_data.get_stat_at_level("pp", level) if class_data else 0
	var base_atk: int = class_data.get_stat_at_level("attack", level) if class_data else 0
	var base_def: int = class_data.get_stat_at_level("defense", level) if class_data else 0
	var base_acc: int = class_data.get_stat_at_level("accuracy", level) if class_data else 0
	var base_eva: int = class_data.get_stat_at_level("evasion", level) if class_data else 0
	var base_mst: int = class_data.get_stat_at_level("technique", level) if class_data else 0

	# Equipment bonuses
	var weapon_id: String = str(equip.get("weapon", ""))
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id)) if not weapon_id.is_empty() else null
	var weapon_grind: int = int(ch.get("weapon_grinds", {}).get(weapon_id, 0))
	var weapon_atk: int = weapon.get_attack_at_grind(weapon_grind) if weapon else 0
	var weapon_acc: int = weapon.get_accuracy_at_grind(weapon_grind) if weapon else 0
	var weapon_name: String = weapon.name if weapon else "--"

	var frame_id: String = str(equip.get("frame", ""))
	var armor = ArmorRegistry.get_armor(frame_id) if not frame_id.is_empty() else null
	var armor_def: int = int(armor.defense_base) if armor else 0
	var armor_eva: int = int(armor.evasion_base) if armor else 0
	var frame_name: String = armor.name if armor else "--"

	# Material bonuses
	var mat_bonuses: Dictionary = ch.get("material_bonuses", {})

	# EXP progress
	var exp_progress: Dictionary = CharacterManager.get_exp_progress() if CharacterManager.has_method("get_exp_progress") else {}
	var to_next: String = str(exp_progress.get("needed", "---"))

	# Weapon special
	var ws: Dictionary = ch.get("weapon_stats", {}).get(weapon_id, {})
	var special_el: String = str(ws.get("element", ""))
	var special_str: String = special_el.capitalize() if not special_el.is_empty() else "--"

	var pages := [
		[["Lv", str(level)], ["Type", class_data.name if class_data else class_id], ["Exp Pts", str(int(ch.get("experience", 0)))], ["To Next Lv", to_next], ["Meseta", str(int(ch.get("meseta", 0)))]],
		[["ATP", str(base_atk + weapon_atk + int(mat_bonuses.get("attack", 0)))], ["ATA", str(base_acc + weapon_acc + int(mat_bonuses.get("accuracy", 0)))], ["Weapon", weapon_name], ["Grind", "+%d" % weapon_grind if weapon_grind > 0 else "--"], ["Special", special_str]],
		[["DFP", str(base_def + armor_def + int(mat_bonuses.get("defense", 0)))], ["EVP", str(base_eva + armor_eva + int(mat_bonuses.get("evasion", 0)))], ["Frame", frame_name], ["Slots", str(armor.max_slots) if armor else "0"], ["Units", "%d / %d" % [_count_equipped_units(equip), armor.max_slots if armor else 0]]],
		[["MST", str(base_mst + int(mat_bonuses.get("technique", 0)))], ["HP", "%d / %d" % [int(ch.get("hp", base_hp)), base_hp + int(mat_bonuses.get("hp", 0))]], ["PP", "%d / %d" % [int(ch.get("pp", base_pp)), base_pp + int(mat_bonuses.get("pp", 0))]]],
	]
	var rows: Array = pages[_info_page] if _info_page < pages.size() else []
	# Text area inside the stats sprite: x=17, y=58, 402×162.
	# Row height targets ~30px so 5 rows fit in 162 with a bit of breathing room.
	var rows_x: float = px + 17
	var rows_y: float = py + 58
	var rows_w: float = 402
	var row_h: float = 30
	for i in range(rows.size()):
		var ry: float = rows_y + i * row_h + 22  # +22 for baseline offset inside the row
		c.draw_string(font, Vector2(rows_x + 8, ry), str(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, rows_w - 16, FONT_SIZE, C_TEXT_MUTED)
		# Right-align value within the same row box so long strings don't overflow off-screen.
		c.draw_string(font, Vector2(rows_x + 8, ry), str(rows[i][1]), HORIZONTAL_ALIGNMENT_RIGHT, rows_w - 16, FONT_SIZE, C_TEXT)


func _draw_items(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Items")
	var inv := _get_inventory()

	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	# Slot count header
	c.draw_string(font, Vector2(px + 10, py + 14), "%d/40 slots" % Inventory.get_total_slots(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)

	# Two-pass scroll calc: each row is one fixed-height entry now that
	# category banners are gone. Type is shown via the per-row icon instead.
	var content_y: float = 20.0
	var item_positions: Array = []
	for _i in range(inv.size()):
		item_positions.append(content_y)
		content_y += 22

	var view_h: float = ph - 6
	if _sub_idx >= 0 and _sub_idx < item_positions.size():
		var sel_y: float = item_positions[_sub_idx]
		if sel_y - _item_scroll < 20:
			_item_scroll = int(sel_y - 20)
		elif sel_y - _item_scroll + 22 > view_h:
			_item_scroll = int(sel_y + 22 - view_h)
	_item_scroll = maxf(_item_scroll, 0.0)

	# Origin row index when the player is mid-Manual-sort, so we can paint
	# it distinctively (cool blue) — distinct from the orange selection tint.
	var move_idx: int = _move_from_idx if _mode == Mode.ITEMS_MOVE else -1

	# Draw pass
	var draw_y: float = py + 20.0 - _item_scroll
	for i in range(inv.size()):
		if draw_y + 22 < py or draw_y > py + ph:
			draw_y += 22
			continue
		var item: Dictionary = inv[i]
		var is_sel: bool = i == _sub_idx
		var is_move_origin: bool = i == move_idx

		if is_sel:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), C_SELECT)
		elif is_move_origin:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), Color(0.34, 0.55, 0.85))
		else:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), Color(1, 1, 1, 0.85))
		var col: Color = C_SELECT_TEXT if (is_sel or is_move_origin) else C_TEXT

		# Per-item icon (PNG when known, fallback to colored letter block).
		var icon_rect := Rect2(px + 6, draw_y + 2, 16, 16)
		var item_id: String = str(item.get("id", ""))
		var category: String = str(item.get("category", "Other"))
		var tex: Texture2D = _get_item_icon(item_id, category)
		if tex:
			c.draw_texture_rect(tex, icon_rect, false)
		else:
			var type_key: String = _category_to_type(category)
			var icon_letter: String = str(TYPE_ICONS.get(type_key, "?"))
			var icon_color: Color = TYPE_COLORS.get(type_key, Color.GRAY)
			if is_sel or is_move_origin:
				icon_color = Color(1, 1, 1, 0.4)
			c.draw_rect(icon_rect, icon_color)
			c.draw_string(font, Vector2(px + 9, draw_y + 15), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

		# Item name (with [E] prefix for equipped — the type icon's slot
		# is now occupied by the type indicator, so the equipped pill
		# moves into the name string).
		var item_name: String = str(item.get("name", ""))
		if item.get("equipped", false):
			item_name = "[E] " + item_name
		c.draw_string(font, Vector2(px + 28, draw_y + 14), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)

		# Quantity
		var qty: int = int(item.get("quantity", 1))
		if qty > 1:
			c.draw_string(font, Vector2(px + pw - 40, draw_y + 14), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, Color(col, 0.7))

		draw_y += 22

	# Description
	var desc: String = ""
	if _sub_idx < inv.size():
		var item: Dictionary = inv[_sub_idx]
		var item_id: String = str(item.get("id", ""))
		desc = str(item.get("name", ""))
		# Try to get details from registries
		var weapon = WeaponRegistry.get_weapon(item_id)
		if weapon:
			desc += "\nATK: %d  ACC: %d" % [weapon.attack_base, weapon.accuracy_base]
			if not weapon.element.is_empty() and weapon.element != "None":
				desc += "\nElement: %s" % weapon.element
		var armor = ArmorRegistry.get_armor(item_id)
		if armor:
			desc += "\nDEF: %d  EVA: %d\nSlots: %d" % [armor.defense_base, armor.evasion_base, armor.max_slots]
		var consumable = ConsumableRegistry.get_consumable(item_id)
		if consumable and not str(consumable.details).is_empty():
			desc += "\n%s" % str(consumable.details)
		# Technique disks: show what they teach and the use prompt
		if item_id.begins_with("disk_"):
			var rest := item_id.substr(5)
			var us := rest.rfind("_")
			if us >= 0:
				var tech_id := rest.substr(0, us)
				var tech_lvl := rest.substr(us + 1)
				var tech_name := tech_id.capitalize()
				if TechniqueManager.TECHNIQUES.has(tech_id):
					tech_name = str(TechniqueManager.TECHNIQUES[tech_id].get("name", tech_name))
				desc += "\nTeaches %s Lv.%s" % [tech_name, tech_lvl]
		if _mode == Mode.ITEMS_MOVE:
			desc += "\n[Enter] Move here  [Esc] Cancel"
		else:
			desc += "\n[Enter] Open"
	if not _action_message.is_empty():
		desc += "\n\n" + _action_message
	_draw_bottom_desc(c, font, desc)


func _draw_equip(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Equip")
	var slots := _get_equip_slots()
	var idx: int = _sub_idx if _mode == Mode.EQUIP else _equip_slot_idx
	if idx >= slots.size():
		idx = 0

	# Custom equip list with headers and white rows
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var draw_y: float = py + 4
	var last_type := ""
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		var slot_type: String = str(s.get("type", ""))

		# Section header for each type group
		var header := ""
		match slot_type:
			"weapon": header = "Weapon" if last_type != "weapon" else ""
			"armor": header = "Armor" if last_type != "armor" else ""
			"unit": header = "Units" if last_type != "unit" else ""
			"mag": header = "Mag" if last_type != "mag" else ""
		if not header.is_empty():
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 18), Color(0.12, 0.16, 0.28))
			c.draw_string(font, Vector2(px + 8, draw_y + 13), header, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_LIGHT)
			draw_y += 20
		last_type = slot_type

		var is_sel: bool = i == idx
		if is_sel:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 22), C_SELECT)
		else:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 22), Color(1, 1, 1, 0.85))
		var col: Color = C_SELECT_TEXT if is_sel else C_TEXT

		# Slot label
		var slot_label: String = str(s.get("label", ""))
		c.draw_string(font, Vector2(px + 8, draw_y + 16), slot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, Color(col, 0.6) if not is_sel else col)

		# Item name — look up proper display name
		var item_id: String = str(s.get("item", ""))
		var display_name: String = "--"
		if not item_id.is_empty():
			var info: Dictionary = Inventory._lookup_item(item_id)
			display_name = str(info.get("name", item_id))
		c.draw_string(font, Vector2(px + 80, draw_y + 16), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)

		draw_y += 24

	if _mode == Mode.EQUIP_PICK:
		_draw_equip_picker(c, font)
	else:
		var desc: String = ""
		var desc_idx: int = _sub_idx if _sub_idx < slots.size() else 0
		if desc_idx < slots.size():
			var item_id: String = str(slots[desc_idx].get("item", ""))
			if not item_id.is_empty():
				var info: Dictionary = Inventory._lookup_item(item_id)
				desc = str(info.get("name", item_id))
				var wdata = WeaponRegistry.get_weapon(Inventory.get_base_id(item_id))
				var adata = ArmorRegistry.get_armor(item_id)
				if wdata:
					desc += "\nATK: %d  ACC: %d" % [wdata.attack_base, wdata.accuracy_base]
					if not wdata.element.is_empty() and wdata.element != "None":
						desc += "\nElement: %s" % wdata.element
				elif adata:
					desc += "\nDEF: %d  EVA: %d\nSlots: %d" % [adata.defense_base, adata.evasion_base, adata.max_slots]
			else:
				desc = "Empty slot\n\n[Enter] Equip"
		_draw_bottom_desc(c, font, desc)


func _draw_equip_picker(c: Control, font: Font) -> void:
	var candidates := _get_equip_candidates(_equip_slot_idx)
	var px: float = 310.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	for i in range(candidates.size()):
		var iy: float = py + 4 + i * 24
		if i == _equip_item_idx:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == _equip_item_idx else C_TEXT
		c.draw_string(font, Vector2(px + 10, iy + 16), str(candidates[i].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)


func _draw_techs(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Techs")
	var techs := _get_techniques()
	var in_field: bool = _is_in_field()

	# Draw tech list
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var scroll_offset: int = maxi(0, _sub_idx - 11)
	for i in range(techs.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * 24
		if iy > py + ph - 6:
			break
		var tech: Dictionary = techs[i]
		var is_sel: bool = i == _sub_idx
		var learned: bool = tech.get("learned", false)

		if is_sel:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), C_SELECT)

		var col: Color
		if is_sel:
			col = C_SELECT_TEXT
		elif not learned:
			col = Color(0.5, 0.5, 0.5)
		else:
			col = C_TEXT

		# Tech icon
		var icon: Texture2D = _get_action_icon(str(tech.get("id", "")))
		if icon:
			if not learned:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false, Color(0.4, 0.4, 0.4))
			else:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false)

		# Tech name
		var level_str: String = "Lv%d" % tech.level if learned else "--"
		c.draw_string(font, Vector2(px + 30, iy + 16), str(tech.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)
		c.draw_string(font, Vector2(px + pw - 80, iy + 16), level_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, col)
		c.draw_string(font, Vector2(px + pw - 30, iy + 16), "%dPP" % tech.pp, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, col)

	# Description
	var desc: String = ""
	if _sub_idx < techs.size():
		var tech: Dictionary = techs[_sub_idx]
		var td: Dictionary = TechniqueManager.TECHNIQUES.get(str(tech.get("id", "")), {})
		desc = str(td.get("name", ""))
		desc += "\n%s element" % str(td.get("element", "none")).capitalize()
		desc += "\nPP: %d" % int(td.get("pp", 0))
		desc += "\nTarget: %s" % str(td.get("target", "single")).capitalize()
		desc += "\nMax Level: %d" % tech.max_level
		if tech.get("learned", false):
			desc += "\nCurrent: Lv %d" % tech.level
			if in_field:
				desc += "\n\n[Enter] Cast"
			else:
				desc += "\n\n(Only in field)"
		else:
			desc += "\n\nNot yet learned"
	_draw_bottom_desc(c, font, desc)


func _draw_palette(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Palette")

	var base_y: float = VIEWPORT_H - BOTTOM_H + 8
	var panel_h: float = BOTTOM_H - 16

	# Left side: page tabs + HUD preview + slot list
	var lx: float = 5.0
	var lw: float = 230.0
	_draw_inner_panel(c, Rect2(lx, base_y, lw, panel_h))
	_draw_scanlines(c, Rect2(lx, base_y, lw, panel_h))

	# Page tabs
	var tab_y: float = base_y + 8
	for pi in range(ActionPalette.pages.size()):
		var tab_x: float = lx + 10 + pi * 70
		var is_active: bool = pi == _pal_page_idx
		if is_active:
			c.draw_rect(Rect2(tab_x, tab_y, 60, 24), C_SELECT)
		c.draw_string(font, Vector2(tab_x + 10, tab_y + 18), "Page %d" % (pi + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_SELECT_TEXT if is_active else C_TEXT_MUTED)

	# HUD preview with palette_bg
	var hud_y: float = tab_y + 34
	var hud_scale: float = 1.7
	var bg_path: String = "res://assets/ui/psz-palette/palette_bg%s.png" % ("_r" if _pal_page_idx == 1 else "")
	if ResourceLoader.exists(bg_path):
		var bg_tex: Texture2D = load(bg_path)
		c.draw_texture_rect(bg_tex, Rect2(lx + 8, hud_y, 128.0 * hud_scale, 67.0 * hud_scale), false)

	var slot_centers := [Vector2(26.0, 27.0), Vector2(58.0, 41.0), Vector2(90.0, 27.0)]
	var page: Array = ActionPalette.pages[_pal_page_idx]
	for si in range(3):
		var center: Vector2 = slot_centers[si] * hud_scale + Vector2(lx + 8, hud_y)
		var icon: Texture2D = _get_action_icon(page[si])
		if icon:
			c.draw_texture_rect(icon, Rect2(center.x - 16, center.y - 16, 32, 32), false)
		if si == _pal_slot_idx:
			c.draw_rect(Rect2(center.x - 18, center.y - 18, 36, 36), Color(0.3, 0.8, 0.3, 0.8), false, 2.0)

	# Slot list under preview (highlight only when browsing slots, not when picking)
	var slot_y: float = hud_y + 67.0 * hud_scale + 10
	var show_slot_cursor: bool = _mode == Mode.PALETTE
	for si in range(3):
		var action_id: String = str(page[si])
		var data: Dictionary = ActionPalette.get_action_data(action_id)
		var label: String = str(data.get("label", action_id))
		var is_sel: bool = si == _pal_slot_idx
		var row_y: float = slot_y + si * 30

		if is_sel and show_slot_cursor:
			c.draw_rect(Rect2(lx + 4, row_y, lw - 8, 28), C_SELECT)

		var slot_col: Color = C_SELECT_TEXT if (is_sel and show_slot_cursor) else C_TEXT_MUTED
		var label_col: Color = C_SELECT_TEXT if (is_sel and show_slot_cursor) else C_TEXT
		c.draw_string(font, Vector2(lx + 12, row_y + 20), "Slot %d" % (si + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, slot_col)
		c.draw_string(font, Vector2(lx + 78, row_y + 20), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, label_col)

	# Actions panel (single rect for both columns)
	var mx: float = 240.0
	var mw: float = 280.0
	var rx: float = 524.0
	var rw: float = 280.0
	var total_w: float = (rx + rw) - mx
	_draw_inner_panel(c, Rect2(mx, base_y, total_w, panel_h))
	_draw_scanlines(c, Rect2(mx, base_y, total_w, panel_h))

	var sel_flat: int = _sub_idx if _mode == Mode.PALETTE_PICK else -1
	var current_id: String = str(page[_pal_slot_idx])
	_draw_palette_grid_split(c, font, mx, base_y, mw, rx, base_y, rw, panel_h, current_id, sel_flat)


const _PAL_COMBAT_RECOVERY_ROWS: Array = [
	{"label": "Combat", "ids": ["attack", "strong_attack", "dodge"]},
	{"label": "Recovery", "ids": ["monomate", "dimate", "trimate"]},
	{"ids": ["monofluid", "difluid", "trifluid"]},
	{"ids": ["sol_atomizer", "star_atomizer", "moon_atomizer"]},
	{"ids": ["telepipe"]},
]

const _PAL_TECHNIQUE_ROWS: Array = [
	{"label": "Technique", "ids": ["foie", "barta", "zonde"]},
	{"ids": ["grants", "megid"]},
	{"ids": ["resta", "anti"]},
	{"ids": ["shifta", "deband"]},
	{"ids": ["jellen", "zalure"]},
]


func _draw_palette_grid_split(c: Control, font: Font, mx: float, my: float, mw: float, rx: float, ry: float, rw: float, ph: float, current_id: String, selected_flat: int) -> void:
	var flat_idx: int = 0
	flat_idx = _draw_palette_column(c, font, mx, my, mw, ph, _PAL_COMBAT_RECOVERY_ROWS, current_id, selected_flat, flat_idx)
	_draw_palette_column(c, font, rx, ry, rw, ph, _PAL_TECHNIQUE_ROWS, current_id, selected_flat, flat_idx)


func _draw_palette_column(c: Control, font: Font, px: float, py: float, pw: float, _ph: float, rows: Array, current_id: String, selected_flat: int, start_flat: int) -> int:
	var cell_h: float = 30.0
	var icon_sz: float = 26.0
	var draw_y: float = py + 6
	var flat_idx: int = start_flat

	for row_def in rows:
		if row_def.has("label"):
			c.draw_string(font, Vector2(px + 10, draw_y + 16), str(row_def.label),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT_LIGHT)
			draw_y += 22

		var row_ids: Array = row_def.ids
		var cell_w: float = (pw - 12.0) / 3.0
		for ci in range(row_ids.size()):
			var action_id: String = row_ids[ci]
			var data: Dictionary = ActionPalette.get_action_data(action_id)
			var label: String = str(data.get("label", action_id))
			var is_current: bool = action_id == current_id
			var is_sel: bool = flat_idx == selected_flat
			var available: bool = _is_palette_action_available(action_id)

			var cx: float = px + 6 + ci * cell_w

			if is_sel:
				c.draw_rect(Rect2(cx, draw_y, cell_w - 2, cell_h), C_SELECT)
			elif is_current:
				c.draw_rect(Rect2(cx, draw_y, cell_w - 2, cell_h), Color(0.15, 0.3, 0.15, 0.6))

			var icon_y: float = draw_y + (cell_h - icon_sz) * 0.5
			c.draw_rect(Rect2(cx + 3, icon_y, icon_sz, icon_sz), Color(0.05, 0.05, 0.1, 0.9))
			var icon: Texture2D = _get_action_icon(action_id)
			if icon:
				var icon_mod: Color = Color(0.4, 0.4, 0.4) if not available else Color.WHITE
				c.draw_texture_rect(icon, Rect2(cx + 3, icon_y, icon_sz, icon_sz), false, icon_mod)

			var col: Color
			if is_sel:
				col = C_SELECT_TEXT
			elif is_current:
				col = Color(0.3, 0.8, 0.3)
			elif not available:
				col = Color(0.5, 0.5, 0.5)
			else:
				col = C_TEXT
			c.draw_string(font, Vector2(cx + icon_sz + 8, draw_y + 20), label,
				HORIZONTAL_ALIGNMENT_LEFT, cell_w - icon_sz - 12, FONT_SIZE_SM, col)

			flat_idx += 1

		draw_y += cell_h + 2

	return flat_idx


func _draw_mags(c: Control, font: Font) -> void:
	var ch := _get_character()
	var mags := _get_mags()

	if _mode == Mode.MAG_FEED:
		_draw_section_label(c, font, "Feed Mag")

		# Left panel: mag stats with gauge bars
		var px: float = 5.0
		var py: float = VIEWPORT_H - 305.0
		var pw: float = 300.0
		var ph: float = 300.0
		_draw_inner_panel(c, Rect2(px, py, pw, ph))

		var mag_id: String = str(mags[_mag_idx].get("id", "")) if _mag_idx < mags.size() else ""
		var mag_state: Dictionary = MagManager.get_mag_state(ch, mag_id) if not ch.is_empty() and not mag_id.is_empty() else {}

		var dy: float = py + 4
		if not mag_state.is_empty():
			var form_id: String = str(mag_state.get("form_id", "mag"))
			var form = MagManager.get_mag_form(form_id)
			var form_name: String = form.name if form else "Mag"
			var level: int = MagManager.get_level(mag_state)

			c.draw_rect(Rect2(px + 2, dy, pw - 4, 18), Color(0.12, 0.16, 0.28))
			c.draw_string(font, Vector2(px + 8, dy + 13), "%s  Lv.%d" % [form_name, level], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT_LIGHT)
			dy += 22

			var stats_dict: Dictionary = mag_state.get("stats", {})
			var stat_colors := {"power": Color(0.9, 0.3, 0.3), "guard": Color(0.3, 0.5, 0.9), "hit": Color(0.3, 0.8, 0.3), "mind": Color(0.7, 0.3, 0.9)}
			var stat_labels := {"power": "POW", "guard": "GRD", "hit": "HIT", "mind": "MND"}
			for stat_key in ["power", "guard", "hit", "mind"]:
				var raw: int = int(stats_dict.get(stat_key, 0))
				var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
				var gauge: int = raw % MagManager.STATS_PER_LEVEL
				var gauge_pct: float = float(gauge) / float(MagManager.STATS_PER_LEVEL)

				c.draw_rect(Rect2(px + 2, dy, pw - 4, 24), Color(1, 1, 1, 0.85))
				c.draw_string(font, Vector2(px + 8, dy + 17), stat_labels[stat_key], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)
				c.draw_string(font, Vector2(px + 55, dy + 17), str(stat_lvl), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)
				# Gauge bar
				var bar_x: float = px + 80
				var bar_w: float = pw - 90
				c.draw_rect(Rect2(bar_x, dy + 6, bar_w, 12), Color(0, 0, 0, 0.15))
				if gauge_pct > 0:
					c.draw_rect(Rect2(bar_x, dy + 6, bar_w * gauge_pct, 12), stat_colors[stat_key])
				dy += 26

			dy += 4
			c.draw_rect(Rect2(px + 2, dy, pw - 4, 20), Color(1, 1, 1, 0.85))
			c.draw_string(font, Vector2(px + 8, dy + 14), "Sync: %d/%d" % [int(mag_state.get("sync", 0)), MagManager.MAX_SYNC], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)
			c.draw_string(font, Vector2(px + 150, dy + 14), "IQ: %d/%d" % [int(mag_state.get("iq", 0)), MagManager.MAX_IQ], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)
			dy += 22

			if form and not str(form.photon_blast).is_empty():
				c.draw_rect(Rect2(px + 2, dy, pw - 4, 20), Color(1, 1, 1, 0.85))
				c.draw_string(font, Vector2(px + 8, dy + 14), "P.Blast: %s" % str(form.photon_blast), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, Color(0.2, 0.6, 0.3))
				dy += 22

		# Right panel: feedable items
		var feed := _get_feed_items()
		var dpx: float = 310.0
		var dpy: float = VIEWPORT_H - 305.0
		var dpw: float = 200.0
		var dph: float = 300.0
		_draw_inner_panel(c, Rect2(dpx, dpy, dpw, dph))
		c.draw_rect(Rect2(dpx + 2, dpy + 2, dpw - 4, 16), Color(0.12, 0.16, 0.28))
		c.draw_string(font, Vector2(dpx + 6, dpy + 14), "Feed Item", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_LIGHT)
		var feed_y: float = dpy + 20
		for i in range(feed.size()):
			if feed_y > dpy + dph - 6:
				break
			var is_sel: bool = i == _sub_idx
			if is_sel:
				c.draw_rect(Rect2(dpx + 2, feed_y, dpw - 4, 20), C_SELECT)
			else:
				c.draw_rect(Rect2(dpx + 2, feed_y, dpw - 4, 20), Color(1, 1, 1, 0.85))
			var col: Color = C_SELECT_TEXT if is_sel else C_TEXT
			c.draw_string(font, Vector2(dpx + 6, feed_y + 14), str(feed[i].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, col)
			var qty: int = int(feed[i].get("quantity", 0))
			if qty > 1:
				c.draw_string(font, Vector2(dpx + dpw - 30, feed_y + 14), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, Color(col, 0.7))
			feed_y += 22
	else:
		_draw_section_label(c, font, "Mags")
		var items: Array = []
		for m in mags:
			var tag: String = " [E]" if m.get("equipped", false) else ""
			items.append({"name": str(m.get("name", "")) + tag, "type": "mag", "equipped": m.get("equipped", false)})
		_draw_bottom_list(c, font, items, _sub_idx)
		var desc: String = ""
		if _sub_idx < mags.size():
			var mag: Dictionary = mags[_sub_idx]
			var mag_state: Dictionary = MagManager.get_mag_state(ch, str(mag.get("id", ""))) if not ch.is_empty() else {}
			if not mag_state.is_empty():
				var form_id: String = str(mag_state.get("form_id", "mag"))
				var form = MagManager.get_mag_form(form_id)
				if form:
					desc += "Form: %s\n" % form.name
					if not str(form.photon_blast).is_empty():
						desc += "P.Blast: %s\n" % str(form.photon_blast)
				var stats_dict: Dictionary = mag_state.get("stats", {})
				for stat_key in ["power", "guard", "hit", "mind"]:
					var raw: int = int(stats_dict.get(stat_key, 0))
					var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
					desc += "%s: %d\n" % [stat_key.capitalize(), stat_lvl]
				desc += "\n[Enter] Feed"
		_draw_bottom_desc(c, font, desc)


func _draw_quest(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Quest")
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 505.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# TODO: pull real quest data from session
	c.draw_string(font, Vector2(px + 16, py + 30), "No active quest.", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_MUTED)


func _draw_system(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "System")
	var items: Array = []
	for s in SYSTEM_LABELS:
		items.append({"name": s, "type": "tool"})
	_draw_bottom_list(c, font, items, _sub_idx)
	var desc: String = SYSTEM_DESCS[_sub_idx] if _sub_idx < SYSTEM_DESCS.size() else ""
	_draw_bottom_desc(c, font, desc)


func _draw_options(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Options")
	var opts := _get_options_list()
	var items: Array = []
	for o in opts:
		items.append({"name": o, "type": "tool"})
	_draw_bottom_list(c, font, items, _options_idx)
	_draw_bottom_desc(c, font, "Toggle debug settings.\n\n[Enter] Toggle\n[Esc] Back")


# ── Draw helpers ────────────────────────────────────────────────────────────────
func _draw_inner_panel(c: Control, rect: Rect2) -> void:
	c.draw_rect(rect, C_PANEL)
	c.draw_rect(rect, C_PANEL_BORDER, false, 1.5)


func _draw_section_label(c: Control, font: Font, text: String) -> void:
	var lx := PAD
	var ly := 110.0  # Below the HUD stats panel
	var lw: float = LEFT_W - PAD * 2
	c.draw_rect(Rect2(lx, ly, lw, 28), C_LABEL_BG)
	c.draw_string(font, Vector2(lx + 12, ly + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_LIGHT)


func _draw_bottom_list(c: Control, font: Font, items: Array, selected: int) -> void:
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Visible-row count derived from panel size and 22px row height. Scroll
	# the window to keep the selected row in view — same pattern as
	# _draw_techs and _draw_palette_picker.
	const ROW_H: int = 22
	var visible_rows: int = int(floor((ph - 8) / ROW_H))
	var scroll_offset: int = maxi(0, selected - (visible_rows - 1))
	var max_scroll: int = maxi(0, items.size() - visible_rows)
	scroll_offset = mini(scroll_offset, max_scroll)
	for i in range(items.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * ROW_H
		if iy > py + ph - ROW_H + 2:
			break
		if i == selected:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 20), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == selected else C_TEXT
		var item_name: String = str(items[i].get("name", ""))
		var item_type: String = str(items[i].get("type", ""))
		# Type icon: PNG for the few types we have art for, otherwise the
		# colored letter block (System/Options menu rows pass type="tool"
		# even though they aren't items, so we don't try to look those up
		# as inventory items).
		var icon_rect := Rect2(px + 6, iy + 2, 16, 16)
		var tex: Texture2D = null
		match item_type:
			"mag": tex = InventoryIcons.for_item("", "Mag")
		if tex:
			c.draw_texture_rect(tex, icon_rect, false)
		else:
			var icon_letter: String = str(TYPE_ICONS.get(item_type, "?"))
			var icon_color: Color = TYPE_COLORS.get(item_type, Color.GRAY) if i != selected else Color(1, 1, 1, 0.4)
			c.draw_rect(icon_rect, icon_color)
			c.draw_string(font, Vector2(px + 9, iy + 15), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
		var qty: int = int(items[i].get("quantity", 0))
		var qty_str: String = "x%d" % qty if qty > 1 else ""
		c.draw_string(font, Vector2(px + 28, iy + 15), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)
		if not qty_str.is_empty():
			c.draw_string(font, Vector2(px + pw - 40, iy + 15), qty_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, Color(col, 0.7))
	# Scroll cue: "▲ more" / "▼ more" hints in the corners when content
	# extends past the visible window.
	if scroll_offset > 0:
		c.draw_string(font, Vector2(px + pw - 60, py + 14), "▲ more", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)
	if scroll_offset + visible_rows < items.size():
		c.draw_string(font, Vector2(px + pw - 60, py + ph - 8), "▼ more", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)


func _draw_bottom_desc(c: Control, font: Font, text: String) -> void:
	var px: float = 310.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Simple multi-line text
	var lines := text.split("\n")
	for i in range(lines.size()):
		c.draw_string(font, Vector2(px + 12, py + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)
