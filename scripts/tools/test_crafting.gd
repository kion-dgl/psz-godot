extends Node
## Headless test: simulate crafting with each photon type

func _ready() -> void:
	_run_tests()
	get_tree().quit()


func _run_tests() -> void:
	print("=== Crafting Special Attack Test ===\n")

	var character = CharacterManager.get_active_character()
	if character == null:
		CharacterManager.create_character(0, "humar", "TestCrafter")
		CharacterManager.set_active_slot(0)
		character = CharacterManager.get_active_character()
	if character == null:
		print("ERROR: Could not create character")
		return

	# Give the player materials for testing
	for mat_id in ["carlian", "acenaline"]:
		for i in range(20):
			Inventory.add_item(mat_id, 1)

	# Give all photon types
	var photon_ids := ["im_photon", "el_photon", "ban_photon", "ray_photon", "zon_photon", "megi_photon", "gra_photon"]
	for pid in photon_ids:
		Inventory.add_item(pid, 5)

	# Give plenty of meseta
	character["meseta"] = 999999
	GameState.meseta = 999999

	# Get a recipe to test with
	var recipes: Array = RecipeRegistry.get_all_recipes()
	if recipes.is_empty():
		print("ERROR: No recipes found")
		return

	var recipe: RecipeBoardData = recipes[0]
	print("Using recipe: %s → %s (rarity: %s)\n" % [recipe.id, recipe.output_weapon_id, WeaponRegistry.get_weapon(recipe.output_weapon_id).rarity if WeaponRegistry.get_weapon(recipe.output_weapon_id) else "?"])

	# Test each photon
	for pid in photon_ids:
		# Add ingredients fresh each time
		for ingredient in recipe.ingredients:
			Inventory.add_item(ingredient["item_id"], int(ingredient["quantity"]))
		Inventory.add_item(pid, 1)

		# Simulate the craft logic
		var inst_id: String = Inventory.add_weapon(recipe.output_weapon_id)
		if inst_id.is_empty():
			print("%s: FAILED (inventory full)" % pid)
			continue

		var weapon = WeaponRegistry.get_weapon(recipe.output_weapon_id)
		var w_rarity: int = int(weapon.rarity) if weapon else 1

		# Import the constants from crafting_shop
		var PHOTON_ELEMENT := {
			"ban_photon": {"element": "fire", "tiers": ["Heat", "Fire", "Flame", "Burning"]},
			"ray_photon": {"element": "ice", "tiers": ["Ice", "Frost", "Freeze", "Blizzard"]},
			"zon_photon": {"element": "lightning", "tiers": ["Shock", "Thunder", "Storm", "Tempest"]},
			"megi_photon": {"element": "dark", "tiers": ["Dim", "Shadow", "Dark", "Hell"]},
			"gra_photon": {"element": "light", "tiers": ["Heart", "Mind", "Soul", "Geist"]},
			"el_photon": {"element": "none", "tiers": ["Draw", "Drain", "Fill", "Gush"]},
		}

		var TIER_WEIGHTS := {
			1: [70, 25, 5, 0],
			2: [55, 30, 12, 3],
			3: [40, 35, 18, 7],
		}

		var element_info: Dictionary = PHOTON_ELEMENT.get(pid, {})
		var special_prefix := ""
		var special_tier := 0

		if not element_info.is_empty() and element_info.has("tiers"):
			# Roll tier
			var weights: Array = TIER_WEIGHTS.get(clampi(w_rarity, 1, 3), TIER_WEIGHTS[1])
			var total := 0
			for w in weights:
				total += int(w)
			var roll := randi_range(0, total - 1)
			var cumulative := 0
			for i in range(weights.size()):
				cumulative += int(weights[i])
				if roll < cumulative:
					special_tier = i
					break
			var tiers: Array = element_info.tiers
			if special_tier < tiers.size():
				special_prefix = str(tiers[special_tier])

		var element_name: String = str(element_info.get("element", ""))
		var weapon_name: String = weapon.name if weapon else "???"
		var display_name: String = (special_prefix + " " + weapon_name).strip_edges()

		print("  %s → \"%s\" (element=%s, tier=%d, prefix=%s)" % [
			pid, display_name, element_name, special_tier + 1, special_prefix if not special_prefix.is_empty() else "(none)"])

		# Cleanup
		Inventory.remove_item(inst_id, 1)

	print("\n=== Done ===")
