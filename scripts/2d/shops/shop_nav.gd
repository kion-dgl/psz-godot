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
