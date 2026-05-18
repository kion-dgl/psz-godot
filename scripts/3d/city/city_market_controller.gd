extends "res://scripts/3d/city/city_area_base.gd"
## Market area controller — first city area with 3 shop NPCs.

const DEFAULT_SPAWN := Vector3(0.98, 2, 62.79)
const DEFAULT_ROT := PI

## In-house replacement for the original weapon-shop cart. The market
## GLB referenced by city_market.tscn has been pre-edited (via the
## /market-editor download workflow) to remove the old cart geometry,
## leaving an empty spot for this model. Transform was dialed in inside
## the same web tool's Place mode and pasted here verbatim.
const WEAPON_SHOP_CART_SCENE := preload("res://assets/stages/city_e/market/weapon_shop/weapon_shop_cart.glb")
const ITEM_SHOP_CART_SCENE := preload("res://assets/stages/city_e/market/item_shop/item_cart.glb")

const SPAWN_VARIANTS := {
	"counter-exit": {
		"position": Vector3(0.98, 2, 18.84),
		"rotation": PI,
	},
	"underground-exit": {
		"position": Vector3(-13.44, 2, 55.0),
		"rotation": 0.0,
	},
}


func _ready() -> void:
	# s00e_sa1 uses baked textures from psz-asset-viewer — no runtime fixes needed
	_add_interior_lights([Vector3(0, 5, 0), Vector3(0, 5, -15), Vector3(0, 5, 15)])

	# Drop in the replacement weapon-shop cart over the empty spot
	# the no-cart GLB left behind.
	_add_weapon_shop_cart()
	_add_item_shop_cart()

	# Heal on city entry
	_heal_character()

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~14 to ~67)
	_add_floor_collision(Vector3(0, 0, 40), Vector3(50, 0.2, 70))

	# NPCs
	_add_npc(
		"ShopNPC", Vector3(-10.34, 0, 27.67), 1.4207,
		"res://assets/npcs/item_shop/item_shop.glb",
		"Shop",
		"res://scenes/2d/shops/item_shop.tscn",
		# VRM-targeted retargeted idle. See web/scripts/bake-retarget-vrm.mjs
		# and assets/player/animations/npc_idles_vrm.glb.
		# Idle: Blender-authored breathing motion (item_shop_anims.glb).
		# Geometric, looks natural; doesn't rely on PSO retargeting.
		"vrm_idle",
		"",                          # no hat
		# Interact response: Blender-authored 3s bow (vrm_bow). Was
		# vrma_greeting before but that's a 7.27s bend+stand+wave —
		# too long for a quick interaction beat; the player walks into
		# the shop UI a couple seconds in and never sees the wave.
		"vrm_bow",
	)
	_add_npc(
		"WeaponShopNPC", Vector3(-6.78, 0, 21.81), 0.7835,
		"res://assets/npcs/np_002_00_0/np_002_00_0.glb",
		"Weapon Shop",
		"res://scenes/2d/shops/weapon_shop.tscn",
		# Reverse-retarget test: this clip was authored as a VRMA (pixiv
		# VRoid Project "Show Full Body" pose) then run through
		# bake-vrma-to-psz.mjs to produce PSZ-targeted bone tracks.
		# Proves the VRM source → PSZ target pipeline works on a PSZ-
		# rigged NPC. If it looks right in-game, switch back to
		# "pso_ro_stand" and this stays as a working sample for the
		# player-character pipeline.
		"vrma_show_full_body_psz"
	)
	_add_npc(
		"GrindShopNPC", Vector3(6.25, 0, 23.45), -0.7533,
		"res://assets/npcs/np_004_00_0/np_004_00_0.glb",
		"Grind Shop",
		"res://scenes/2d/shops/tekker.tscn"
	)

	# Area triggers
	_add_area_trigger(
		Vector3(0.38, 1, 14.43), Vector3(7.42, 3, 1),
		"res://scenes/3d/city/city_counter.tscn", "market-exit"
	)
	# Interactive trigger — Enter Underground
	_add_interactive_trigger(
		Vector3(-13.44, 1, 57.44), Vector3(3, 3, 3),
		"res://scenes/3d/city/city_underground.tscn", "market-exit",
		"Enter Underground"
	)

	# Wire up player references
	_connect_player_to_interactables()


func _get_area_name() -> String:
	return "market"


func _add_weapon_shop_cart() -> void:
	var cart: Node3D = WEAPON_SHOP_CART_SCENE.instantiate()
	cart.transform = Transform3D(
		Vector3(2.0545, 0.0, -2.0467),
		Vector3(0.0, 2.9, 0.0),
		Vector3(2.0467, 0.0, 2.0545),
		Vector3(-9.0751, 0.0, 20.1794)
	)
	add_child(cart)


func _add_item_shop_cart() -> void:
	var cart: Node3D = ITEM_SHOP_CART_SCENE.instantiate()
	cart.transform = Transform3D(
		Vector3(-0.0798, 0.0, -2.2987),
		Vector3(0.0, 2.3, 0.0),
		Vector3(2.2987, 0.0, -0.0798),
		Vector3(-14.5643, 0.0, 27.5287)
	)
	add_child(cart)
