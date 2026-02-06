extends Node
## ShopManager — handles buy/sell transactions.
## Ported from psz-sketch/src/api/shop.ts

signal item_bought(item_name: String, cost: int)
signal item_sold(item_name: String, meseta_gained: int)


## Get the item list for a shop
func get_shop_inventory(shop_id: String) -> Array:
	var shop = ShopRegistry.get_shop(shop_id)
	if shop == null:
		return []
	return shop.items.duplicate()


## Buy an item from a shop
func buy_item(shop_id: String, item_name: String, quantity: int = 1) -> bool:
	var shop = ShopRegistry.get_shop(shop_id)
	if shop == null:
		return false

	# Find item in shop
	var shop_item: Dictionary = {}
	for item in shop.items:
		if item.get("item", "") == item_name:
			shop_item = item
			break

	if shop_item.is_empty():
		return false

	var cost: int = int(shop_item.get("cost", 0)) * quantity
	var currency: String = shop_item.get("currency", "Meseta")

	if currency != "Meseta":
		# Non-meseta currencies not yet implemented
		return false

	var character = CharacterManager.get_active_character()
	if character == null:
		return false

	if int(character.get("meseta", 0)) < cost:
		return false

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# TODO: Add item to inventory based on category
	# For now, just track the transaction
	item_bought.emit(item_name, cost)
	print("[ShopManager] Bought %dx %s for %d meseta" % [quantity, item_name, cost])
	return true


## Sell an item for meseta
func sell_item(item_name: String, sell_price: int, quantity: int = 1) -> int:
	var meseta_gained := sell_price * quantity
	var character = CharacterManager.get_active_character()
	if character == null:
		return 0

	character["meseta"] = int(character["meseta"]) + meseta_gained
	GameState.meseta = int(character["meseta"])

	item_sold.emit(item_name, meseta_gained)
	print("[ShopManager] Sold %dx %s for %d meseta" % [quantity, item_name, meseta_gained])
	return meseta_gained
