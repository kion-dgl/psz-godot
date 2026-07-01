extends RefCounted
## Shared input skeleton for shop / menu list screens (#274 increment 3).
##
## Composition, not inheritance: screens `preload()` this and delegate from
## `_unhandled_input` — a cross-script base class breaks the Android export
## when a screen is lazily loaded (see docs/shop-dedup.md), so shared shop
## behavior must stay in preloaded static helpers.
##
## The skeleton: modal guard → cancel → left/right tabs → up/down selection
## → accept → screen-specific tail. Every branch a screen opts into behaves
## identically across screens (sfx, wrap, input-as-handled); everything
## per-screen arrives as a Callable hook.
##
## opts keys (all optional):
##   modal: Object            — while valid, the modal owns input; skip all
##   sfx: bool = true         — play the shared menu sfx per branch
##   on_cancel: Callable      — default: SceneManager.pop_scene()
##   on_tab: Callable(dir)    — left/right handler; omit = keys fall through
##   list_size: Callable->int — up/down wrap bound; omit = keys fall through
##   on_move: Callable(old_index) — after _selected_index changed
##   on_accept: Callable      — omit = accept falls through
##   on_other: Callable(event)->bool — tail hook for screen-specific keys
##
## The screen must declare `var _selected_index: int` when using list_size.
## Returns true when the event was consumed.

const SFX_MOVE := "res://assets/sfx/ui/menu_move.wav"
const SFX_SELECT := "res://assets/sfx/ui/menu_select.wav"
const SFX_BACK := "res://assets/sfx/ui/menu_back.wav"
## The shared "denied" cue — a blocked action: Accept on a greyed/un-actionable
## row, or a transaction that fails at commit. Distinct from SFX_BACK (close);
## screens used to play the close cue on a blocked buy, which read as "closed".
const SFX_DENIED := "res://assets/sfx/ui/menu_invalid.wav"

## Canonical economy-screen failure vocabulary (spec /states/shops #feedback).
## Defined once here — screens MUST reference these, never a local literal, so
## the message can't drift ("Inventory full!" vs "No room" across screens).
const MSG_NO_ROOM := "No room"
const MSG_NOT_ENOUGH_MESETA := "Not enough meseta"

## Set by deny()/denied_sfx() so the accept branch can tell an Accept that
## opened something apart from one that was immediately blocked. on_accept runs
## synchronously inside handle(), so a deny during that call lands here before
## handle() decides whether to play the accept cue — without it, a blocked buy
## plays SFX_SELECT *and* SFX_DENIED stacked. Spec /states/shops #feedback:
## a blocked action plays the denied cue once, never the accept cue.
static var _denied_during_accept := false


static func handle(shop: Control, event: InputEvent, opts: Dictionary) -> bool:
	if is_instance_valid(opts.get("modal")):
		return false
	var sfx: bool = opts.get("sfx", true)
	if event.is_action_pressed("ui_cancel"):
		if sfx:
			SfxManager.play(SFX_BACK)
		if opts.has("on_cancel"):
			(opts["on_cancel"] as Callable).call()
		else:
			SceneManager.pop_scene()
		_mark_handled(shop)
		return true
	if opts.has("on_tab") \
			and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		if sfx:
			SfxManager.play(SFX_MOVE)
		(opts["on_tab"] as Callable).call(1 if event.is_action_pressed("ui_right") else -1)
		_mark_handled(shop)
		return true
	if opts.has("list_size") \
			and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
		if sfx:
			SfxManager.play(SFX_MOVE)
		var dir: int = -1 if event.is_action_pressed("ui_up") else 1
		var old_index: int = shop.get("_selected_index")
		var size: int = (opts["list_size"] as Callable).call()
		shop.set("_selected_index", wrapi(old_index + dir, 0, maxi(size, 1)))
		if opts.has("on_move"):
			(opts["on_move"] as Callable).call(old_index)
		_mark_handled(shop)
		return true
	if opts.has("on_accept") and event.is_action_pressed("ui_accept"):
		_run_accept(shop, opts["on_accept"] as Callable, sfx)
		return true
	if opts.has("on_other"):
		return (opts["on_other"] as Callable).call(event)
	return false


## Run an accept branch: invoke the handler, then play the accept cue *unless*
## the handler blocked the action (deny/denied_sfx flips _denied_during_accept).
## Playing after on_accept is what lets a rejected buy sound the denied cue
## alone instead of select+denied stacked. Spec /states/shops #feedback.
## (Split out of handle() so the cue-suppression branch doesn't push it over
## the complexity bound.)
static func _run_accept(shop: Control, on_accept: Callable, sfx: bool) -> void:
	_denied_during_accept = false
	on_accept.call()
	if sfx and not _denied_during_accept:
		SfxManager.play(SFX_SELECT)
	_mark_handled(shop)


## Guard for "confirm acts on the selected row" (#274 inc 4): the selected
## entry of `list`, or null when the list is empty / selection out of bounds.
## The screen must declare `var _selected_index: int`.
static func selected_item(shop: Control, list: Array) -> Variant:
	var idx: int = int(shop.get("_selected_index"))
	if list.is_empty() or idx >= list.size():
		return null
	return list[idx]


## Open a yes/no ConfirmDialog owned by the screen's `_active_modal` guard
## (the guard ShopNav.handle and the screens' NavRepeat checks key off).
## on_yes runs on confirm, on_cancel (optional) on cancel — both after the
## modal has released `_active_modal`.
static func confirm(shop: Control, prompt: String, on_yes: Callable, on_cancel := Callable()) -> void:
	var modal := ConfirmDialog.new()
	modal.ask(prompt)
	modal.confirmed.connect(func() -> void:
		shop.set("_active_modal", null)
		on_yes.call()
	)
	modal.cancelled.connect(func() -> void:
		shop.set("_active_modal", null)
		if on_cancel.is_valid():
			on_cancel.call()
	)
	shop.set("_active_modal", modal)
	shop.add_child(modal)


## Sell-tab confirm that mirrors the buy flow's quantity awareness (#416). True
## item stacks (consumables/materials with quantity > 1) get the QuantityDialog
## picker — "Sell 5× Monomate for 50 M?"; per-slot gear (weapons/armor/units/
## mags/disks, always one instance per row) collapses to a plain Yes/No confirm.
## `on_confirm` is called with the chosen quantity (1 on the simple path), so a
## caller's `_sell_selected(qty := 1)` works for both. Shared by the item + weapon
## shops; `on_cancel` (optional) runs on dismissal — same `_active_modal` lifecycle
## as confirm().
static func sell_confirm(shop: Control, item: Dictionary, on_confirm: Callable, on_cancel := Callable()) -> void:
	var name_str: String = str(item.get("name", "???"))
	var unit_price: int = int(item.get("sell_price", 0))
	var item_id: String = str(item.get("id", ""))
	var available: int = int(item.get("quantity", 1))
	if Inventory._is_per_slot(item_id) or available <= 1:
		confirm(shop, "Sell %s for %d M?" % [name_str, unit_price],
			func() -> void: on_confirm.call(1), on_cancel)
		return
	var modal := QuantityDialog.new()
	modal.set_item(name_str, unit_price, available, "Sell")
	modal.ask("Sell %s?" % name_str)
	modal.confirmed_qty.connect(func(qty: int) -> void:
		shop.set("_active_modal", null)
		on_confirm.call(qty)
	)
	modal.cancelled.connect(func() -> void:
		shop.set("_active_modal", null)
		if on_cancel.is_valid():
			on_cancel.call()
	)
	shop.set("_active_modal", modal)
	shop.add_child(modal)


## Single-button info modal for blocking error states (inventory full,
## can't afford, …) so the failure is unmissable. Same `_active_modal`
## lifecycle as confirm(); on_dismiss (optional) runs after dismissal.
static func info(shop: Control, msg: String, on_dismiss := Callable()) -> void:
	var modal := ConfirmDialog.new()
	modal.confirmed.connect(func() -> void:
		shop.set("_active_modal", null)
		if on_dismiss.is_valid():
			on_dismiss.call()
	)
	shop.set("_active_modal", modal)
	shop.add_child(modal)
	modal.info(msg)


## Play the shared "denied" cue for a blocked action that opens nothing — Accept
## on a greyed/un-actionable row whose reason already shows in the detail panel.
## Once, never the back/close or accept cue. Spec /states/shops #feedback.
static func denied_sfx() -> void:
	_denied_during_accept = true
	SfxManager.play(SFX_DENIED)


## Report a blocking failure the player *could* start (a commit-time reject):
## the denied cue + an info modal that states the reason. Use this instead of a
## silent hint when a confirmed action can't complete. Spec /states/shops #feedback.
static func deny(shop: Control, reason: String, on_dismiss := Callable()) -> void:
	_denied_during_accept = true
	SfxManager.play(SFX_DENIED)
	info(shop, reason, on_dismiss)


## Shared cursor-move handler for shop lists that cache their pill nodes for an
## incremental update: restyle the selection (PszStyle.restyle_selection) and
## re-render the screen's detail panel. Composition, not a base class (the
## Android export can't resolve a cross-script shop base — see the file header),
## so screens call this from their ShopNav.handle `on_move` hook instead of each
## hand-rolling an identical `_update_selection`.
static func cursor_move(pill_nodes: Array, old_index: int, new_index: int, on_detail := Callable()) -> void:
	PszStyle.restyle_selection(pill_nodes, old_index, new_index)
	if on_detail.is_valid():
		on_detail.call()


## The active character's "Type Race" capability string (e.g. "Force Newman"), or
## "" when unavailable — the format WeaponData/ArmorData/ConsumableData
## can_be_used_by expect. Shared so the shops don't each re-derive it.
static func active_class_use_string() -> String:
	var character = CharacterManager.get_active_character()
	if character == null:
		return ""
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data == null:
		return ""
	return "%s %s" % [class_data.type, class_data.race]


## True when the active character can NEVER use/equip `item_id` — THE shared
## permanent-capability ✕ predicate. Every ✕ "cannot use/equip" marker routes
## through here so they can't drift: shop SELL rows, and the inventory screens
## (storage, the 3D field start menu). The buy lists use the same gate via
## EquipmentUtils.item_fits_slot, so buy and sell agree. Covers:
##   • Weapons whose type the class can't equip — the canonical equip-legality
##     gate (ClassData.allowed_weapon_types, via EquipmentUtils.item_fits_slot;
##     spec /mechanics/equip-legality). WeaponData.usable_by is deliberately NOT
##     consulted — it has drifted and is not the source of truth.
##   • Armor the class can't wear — the per-item class restriction
##     (ArmorData.usable_by, via item_fits_slot("frame")). This is the ONLY
##     armor-legality source (ClassData has no armor analog), so it is NOT dead
##     data like the weapon list — it stays canonical.
##   • Technique disks the race/class can never learn (TechniqueManager.class_can_learn).
## Units, mags, materials, and consumables carry no permanent class block, so
## they never get the ✕. A temporary block (e.g. too-low level) is NOT a ✕ —
## item_fits_slot deliberately omits the level gate.
static func sell_cannot_use(item_id: String) -> bool:
	var base_id: String = Inventory.get_base_id(item_id)
	if WeaponRegistry.get_weapon(base_id) != null:
		# item_fits_slot applies the class weapon-type gate (and DebugConfig.equip_all),
		# without the level gate — exactly the permanent-only check the ✕ wants.
		return not EquipmentUtils.item_fits_slot(item_id, "weapon")
	if ArmorRegistry.get_armor(base_id) != null:
		# Same permanent-only check for armor: the per-item class restriction,
		# honoring DebugConfig.equip_all, without the level gate.
		return not EquipmentUtils.item_fits_slot(item_id, "frame")
	if base_id.begins_with("disk_"):
		var character = CharacterManager.get_active_character()
		if character == null:
			return false
		var parsed: Dictionary = _parse_disk_id(base_id)
		if parsed.is_empty():
			return false
		return not TechniqueManager.class_can_learn(
			character, str(parsed.get("technique_id", "")), int(parsed.get("level", 1)))
	return false


## The grey-WITHOUT-✕ companion to sell_cannot_use: a *temporary / already-
## satisfied* block that mutes the row but carries no permanent ✕ marker (spec
## /states/shops "row contract", /mechanics/equip-legality). For a technique
## disk the class CAN learn, this is true when can_learn currently rejects it —
## the technique is already known at this level or higher, or the player is below
## the disk's required level. Every item-list surface (sell lists, storage,
## start-menu inventory) routes its grey tier through here so already-known disks
## mute consistently — the same single-predicate, no-drift rule as the ✕ marker.
## Non-disks (and the permanent class-block, which is the ✕ tier) return false.
static func sell_disabled(item_id: String) -> bool:
	var base_id: String = Inventory.get_base_id(item_id)
	if not base_id.begins_with("disk_"):
		return false
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	var parsed: Dictionary = _parse_disk_id(base_id)
	if parsed.is_empty():
		return false
	var technique_id: String = str(parsed.get("technique_id", ""))
	var level: int = int(parsed.get("level", 1))
	# A permanent class block is the ✕ tier (sell_cannot_use), not the grey tier.
	if not TechniqueManager.class_can_learn(character, technique_id, level):
		return false
	# Class can learn it, but not right now → already known at >= level, or the
	# player level is too low. Both are temporary/satisfied blocks → grey, no ✕.
	return not TechniqueManager.can_learn(character, technique_id, level).get("allowed", false)


## Parse a technique-disk inventory id "disk_<technique>_<level>" into
## {technique_id, level}, or {} when it doesn't match. Technique ids are single
## tokens (foie, gizonde, …), so the final underscore field is the level.
static func _parse_disk_id(disk_id: String) -> Dictionary:
	var rest: String = disk_id.trim_prefix("disk_")
	var cut: int = rest.rfind("_")
	if cut <= 0:
		return {}
	var lvl_str: String = rest.substr(cut + 1)
	if not lvl_str.is_valid_int():
		return {}
	return {"technique_id": rest.substr(0, cut), "level": int(lvl_str)}


## Standard tab switch for buy/sell shops (item + weapon): wrap `_tab`,
## reset the selection, regenerate the sell list when landing on it,
## refresh hint + display. The shop must define those members.
static func switch_shop_tab(shop: Control, dir: int, tab_count: int, sell_tab: int) -> void:
	shop.set("_tab", wrapi(int(shop.get("_tab")) + dir, 0, tab_count))
	shop.set("_selected_index", 0)
	if int(shop.get("_tab")) == sell_tab:
		shop.call("_generate_sell_list")
	shop.call("_update_hint")
	shop.call("_refresh_display")


static func _mark_handled(shop: Control) -> void:
	if shop.is_inside_tree():
		shop.get_viewport().set_input_as_handled()
