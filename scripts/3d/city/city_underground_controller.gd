extends "res://scripts/3d/city/city_area_base.gd"
## Underground (sewer) area controller — Photon Collector and Enemy Collector NPCs.

const DEFAULT_SPAWN := Vector3(0.04, 0, -1.0)
const DEFAULT_ROT := PI

const SPAWN_VARIANTS := {
	"market-exit": {
		"position": Vector3(0.04, 0, -1.0),
		"rotation": PI,
	},
}


func _ready() -> void:
	# Spawn player
	_spawn_player(DEFAULT_SPAWN, DEFAULT_ROT, SPAWN_VARIANTS)

	# Camera
	_setup_camera(player)

	# Floor collision — centered on underground walkable area
	_add_floor_collision(Vector3(0, 0, -5), Vector3(30, 0.2, 30))

	# NPCs
	_add_npc(
		"SynthesisNPC", Vector3(8.38, 0, -4.81), 0,
		"res://assets/npcs/np_017_00_0/np_017_00_0.glb",
		"Synthesis Shop",
		"res://scenes/2d/shops/crafting_shop.tscn",
		"pso_ro_stand"
	)
	_add_npc(
		"PhotonCollectorNPC", Vector3(-6.32, 0, -5.35), 0,
		"res://assets/npcs/np_018_00_0/np_018_00_0.glb",
		"Photon Collector",
		"res://scenes/2d/shops/photon_shop.tscn",
		"pso_f_ro_stand"
	)
	_add_npc(
		"BlackjackDealerNPC", Vector3(-10.0, 0, 0.0), PI / 2.0,
		"res://assets/npcs/cowgirl/cowgirl.fbx",
		"Blackjack",
		"res://scenes/2d/blackjack/blackjack_table.tscn"
	)

	# Interactive exit trigger — back to market. Trigger volume centred at
	# (0, 0, -3) on the walkable floor; Y=1 raises the box to player-torso
	# height so the interaction prompt fires reliably regardless of camera angle.
	_add_interactive_trigger(
		Vector3(0, 1, -3), Vector3(3, 3, 1),
		"res://scenes/3d/city/city_market.tscn", "underground-exit",
		"Exit to City"
	)

	# Strip the per-GLB +X layout offset baked into each de_roll_le piece
	# (20-unit grid: fe_obj002_mizu = +300, fe_obj006_grid2 = +200, etc.)
	# and switch their materials to the mirror-wrap shader so tiling textures
	# don't clamp at the edges. Three.js' bakeSkinnedMeshes() in the editor
	# collapses the offset; Godot's GLB import preserves it.
	_setup_de_roll_le_pieces()

	# Wire up player references
	_connect_player_to_interactables()


func _setup_de_roll_le_pieces() -> void:
	for child in get_children():
		if not (child is Node3D):
			continue
		if not String(child.name).begins_with("DeRollLe_"):
			continue
		_zero_inner_offset(child as Node3D)
		_apply_mirror_wrap_recursive(child)


func _zero_inner_offset(piece: Node3D) -> void:
	for inner in piece.get_children():
		if inner is Node3D:
			(inner as Node3D).transform = Transform3D.IDENTITY
			return


func _apply_mirror_wrap_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var sm := ShaderMaterial.new()
					sm.shader = TEXTURE_FIX_SHADER
					if std.albedo_texture:
						sm.set_shader_parameter("albedo_texture", std.albedo_texture)
					sm.set_shader_parameter("albedo_color", std.albedo_color)
					sm.set_shader_parameter("wrap_s", 1) # mirror
					sm.set_shader_parameter("wrap_t", 1) # mirror
					mi.set_surface_override_material(i, sm)
	for c in node.get_children():
		_apply_mirror_wrap_recursive(c)


func _get_area_name() -> String:
	return "underground"
