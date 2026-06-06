class_name ShopBase
extends Control
## Shared base for the city's list-menu shop/counter screens. Owns scaffolding
## that was copy-pasted byte-for-byte across the screens. Subclasses extend this
## instead of Control. (Incremental extraction — see docs/shop-dedup.md.)


## The active character's meseta (0 if no active character).
func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0


## NavRepeat callback: re-emit a held nav action as a synthetic input event so
## the screen's own _unhandled_input handles it (hold-to-repeat navigation).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


## Buy-affordance check for a shop row. Returns {"ok": bool, "reason": String}.
##
## Lets a screen disable the Buy action up front (greyed row + reason) instead
## of letting the player confirm and then hit a rejection. The default mirrors
## ShopManager.buy_item's guards for a meseta-priced item — currency,
## affordability, and inventory room — so it can't drift from what actually
## succeeds. Shops with extra rules (weapon level/class requirements,
## non-meseta currency like photon drops) override and may super()-chain.
func _can_buy(item: Dictionary) -> Dictionary:
	var currency: String = str(item.get("currency", "Meseta"))
	if currency != "Meseta":
		return {"ok": false, "reason": currency}
	var cost: int = int(item.get("cost", 0))
	if _get_meseta() < cost:
		return {"ok": false, "reason": "Can't afford"}
	# Same name→id derivation ShopManager.buy_item uses, so the room check agrees.
	var item_name: String = str(item.get("item", item.get("name", "")))
	var item_id: String = item_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
	if not Inventory.can_add_item(item_id):
		return {"ok": false, "reason": "No room"}
	return {"ok": true, "reason": ""}
