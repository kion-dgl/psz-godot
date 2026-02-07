extends Node
## ShopManager — handles buy/sell transactions.
## Ported from psz-sketch/src/api/shop.ts

signal item_bought(item_name: String, cost: int)
signal item_sold(item_name: String, meseta_gained: int)

var _last_refresh_count: int = -1


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

	# Convert shop item name to registry ID (e.g. "Monomate" → "monomate")
	var item_id: String = item_name.to_lower().replace(" ", "_")

	# Check if inventory can hold the item
	if not Inventory.can_add_item(item_id):
		return false

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# Add item to inventory
	Inventory.add_item(item_id, quantity)

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


## Check if weapon shop should refresh and return a refreshed weapon list.
## Returns array of weapon IDs appropriate for the player's level.
func get_refreshed_weapon_pool() -> Array:
	var character = CharacterManager.get_active_character()
	var level: int = int(character.get("level", 1)) if character else 1
	var missions_done: int = GameState.completed_missions.size()

	# Refresh if missions count changed by 3+
	if missions_done - _last_refresh_count < 3 and _last_refresh_count >= 0:
		return []  # No refresh needed
	_last_refresh_count = missions_done

	# Gather level-appropriate weapons
	var all_ids: Array = WeaponRegistry.get_all_weapon_ids()
	var pool: Array = []
	for wid in all_ids:
		var w = WeaponRegistry.get_weapon(wid)
		if w == null:
			continue
		# Only include weapons within ±10 levels of player
		if w.level <= level + 10 and w.rarity <= 4:
			pool.append(wid)

	# Shuffle and pick 8-12
	pool.shuffle()
	var count: int = mini(randi_range(8, 12), pool.size())
	var result: Array = pool.slice(0, count)
	print("[ShopManager] Refreshed weapon pool: %d weapons for Lv.%d" % [result.size(), level])
	return result
