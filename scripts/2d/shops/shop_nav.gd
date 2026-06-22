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
		if sfx:
			SfxManager.play(SFX_SELECT)
		(opts["on_accept"] as Callable).call()
		_mark_handled(shop)
		return true
	if opts.has("on_other"):
		return (opts["on_other"] as Callable).call(event)
	return false


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
	SfxManager.play(SFX_DENIED)


## Report a blocking failure the player *could* start (a commit-time reject):
## the denied cue + an info modal that states the reason. Use this instead of a
## silent hint when a confirmed action can't complete. Spec /states/shops #feedback.
static func deny(shop: Control, reason: String, on_dismiss := Callable()) -> void:
	SfxManager.play(SFX_DENIED)
	info(shop, reason, on_dismiss)


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
