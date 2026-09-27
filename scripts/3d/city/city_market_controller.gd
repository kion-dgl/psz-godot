extends "res://scripts/3d/city/city_area_base.gd"
## Market area controller — first city area with 3 shop NPCs.

const DEFAULT_SPAWN := Vector3(0.98, 2, 62.79)
const DEFAULT_ROT := PI

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
	# s00e_sa1 uses baked textures from psz-asset-viewer — no runtime fixes
	# needed, so this area deliberately skips _fix_city_materials(). The two
	# wave surfaces are the exception: they are meant to be moving water, and
	# a still texture reads as a painted-on puddle. _apply_scroll_fixes() is
	# the narrow pass that animates those and touches nothing else.
	_apply_scroll_fixes()
	# The authored sidecar (wetlands envelope, kion's locked tuning from the
	# counter) with the legacy row only as fallback.
	if not _add_authored_lights("s00e_sa1"):
		_add_interior_lights([Vector3(0, 5, 0), Vector3(0, 5, -15), Vector3(0, 5, 15)])

	# Heal on city entry
	_heal_character()

	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on walkable area (Z range ~14 to ~67)
	_add_floor_collision(Vector3(0, 0, 40), Vector3(50, 0.2, 70))
	_apply_market_rig()

	# The market IS s00e_sa1 — its two authored butterflies (#644), from the
	# set-`c` table, standing mid-room (≈ (4.6, 45.2) and (−9.7, 34.8)).
	_add_ambience("s00e_sa1")

	# OUR near-spawn flair (#644 playtest): two butterflies right beside the
	# city spawn — invented positions (kion's call; the authored pair keeps
	# its mid-room spots), hovering ~1m at the south entrance.
	_add_flair_critters([Vector3(6.6, 0.0, 57.9), Vector3(-4.5, 0.0, 58.5)])

	_add_market_npcs()

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


## The market floor rig (#670): the valley-A contract — the stage keeps its
## PURE BAKE (unlit — the market's visual floor mesh shows its own painted
## ground, no light can touch it), and the authored y:0 catcher plane carries
## ONLY the sun's shadow. The catcher's light budget is the measured (#670)
## hard part: the compat renderer blends the transparent pass in FLOAT — no
## clamp — so a catcher lit past ×1 BRIGHTENS the floor into the white sheet
## (e6 did exactly that), while well under it reads a gray veil. The catcher
## therefore rides CATCHER_LAYER with every point light culled off it,
## leaving ambient 0.5 + one uniform sun at 0.8·cos55° ≈ ×0.96 — just UNDER
## 1, invisible — and inside the shadow maps it falls to the ambient share
## (×0.5, the valley's shadow depth). PSZ_MARKET_CATCHER=floor_lit keeps the
## guild-counter rig as the A/B; "none" boots the raw stage (rig isolation
## for #670 measurement).
func _apply_market_rig() -> void:
	var rig := OS.get_environment("PSZ_MARKET_CATCHER")
	if rig == "floor_lit":
		_apply_ds_floor_lit("Market")
	elif rig != "none":
		_apply_ds_bake_look("Market", false, Vector2(50, 70), Vector3(0, 0, 40))
		for child in get_children():
			if child is OmniLight3D:
				(child as OmniLight3D).light_cull_mask &= ~CATCHER_LAYER
	var market_sun := DirectionalLight3D.new()
	market_sun.name = "MarketSun"
	market_sun.light_energy = float(OS.get_environment("PSZ_MSUN_E")) if not OS.get_environment("PSZ_MSUN_E").is_empty() else 0.8
	market_sun.rotation_degrees = Vector3(-55, 25, 0)
	market_sun.shadow_enabled = true
	market_sun.shadow_blur = 1.0
	add_child(market_sun)
	# #670 (the #648 valley lesson): the compat renderer anchors the
	# directional shadow pass at the LIGHT NODE — at the origin the eye sits
	# at floor level OUTSIDE the plaza (the room spans z 5..75) and no shadow
	# map covers it, the "sun on, shadows nowhere" read. Position is
	# meaningless to a directional's shading, so only the eye moves: into
	# the room's interior air. The unmasked sun lights the actors and the
	# catcher; the stage itself is unlit either way.
	MeshUtils.place_light_inside_room(market_sun, get_node("Market"), 0.0)


## The three shop NPCs (extracted from _ready).
func _add_market_npcs() -> void:
	# Low-poly PSZ shopkeeper. Reverted from the VRM-derived item_shop.glb
	# (#535): the VRM model stuck out as the lone high-poly figure next to the
	# low-poly cast — better to keep the roster consistent until every NPC can
	# be upgraded together. The high-poly asset + VRM anims (assets/npcs/
	# item_shop/, npc_idles_vrm.glb) stay in the repo for that future pass.
	# pso_f_sh_stand is the original PSZ shopkeeper idle; the VRM-only vrm_idle/
	# vrm_bow clips don't retarget onto the PSZ skeleton, so they're dropped.
	_add_npc(
		"ShopNPC", Vector3(-10.34, 0, 27.67), 1.4207,
		"res://assets/npcs/np_003_00_0/np_003_00_0.glb",
		"Item Shop",
		"res://scenes/2d/shops/item_shop.tscn",
		"pso_f_sh_stand",
	)
	_add_npc(
		"WeaponShopNPC", Vector3(-6.78, 0, 21.81), 0.7835,
		"res://assets/npcs/np_002_00_0/np_002_00_0.glb",
		"Weapon Shop",
		"res://scenes/2d/shops/weapon_shop.tscn",
		# Standard PSZ ranger idle. (Previously held a VRMA→PSZ reverse-
		# retarget test clip, `vrma_show_full_body_psz` from
		# assets/animations/vrma_psz.glb — see
		# web/scripts/bake-vrma-to-psz.mjs. That clip didn't play cleanly
		# on the np_002_00_0 PSZ skeleton in-game, so reverted per the
		# original comment's escape-hatch instruction.)
		"pso_ro_stand"
	)
	_add_npc(
		"GrindShopNPC", Vector3(6.25, 0, 23.45), -0.7533,
		"res://assets/npcs/np_004_00_0/np_004_00_0.glb",
		"Grind Shop",
		"res://scenes/2d/shops/tekker.tscn"
	)



func _get_area_name() -> String:
	return "market"
