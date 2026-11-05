extends RefCounted

static func run(t: Node) -> void:
	seed(782)
	var warp := preload("res://scripts/3d/elements/boss_warp.gd").new()
	warp.model_path = ""
	warp.model = Node3D.new()
	warp.add_child(warp.model)
	var originals: Array[StandardMaterial3D] = []
	for texture_name in ["o0s_1_swarp3", "o0s_0_bwarp1"]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = QuadMesh.new()
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		var tex := ImageTexture.new()
		tex.resource_path = "res://%s.png" % texture_name
		mat.albedo_texture = tex
		mesh.set_surface_override_material(0, mat)
		originals.append(mat)
		warp.model.add_child(mesh)
	t.add_child(warp)
	var beam_mesh: MeshInstance3D = warp.model.get_child(0)
	var base_mesh: MeshInstance3D = warp.model.get_child(1)
	var beam := beam_mesh.get_active_material(0) as StandardMaterial3D
	var base := base_mesh.get_active_material(0) as StandardMaterial3D
	t.assert_true(beam != null and base != null, "both boss surfaces use standard materials")
	t.assert_true(beam != null and beam.texture_repeat, "boss beam repeats its baked mirror atlas")
	if beam and base:
		warp._update_animation(0.5)
		var want := (Vector2(0, -7.62).y + -1.35 * 0.5) / 2.0
		t.assert_true(abs(beam.uv1_offset.y - want) < 0.0001, "boss scroll follows catalog speed at half the mirror period (got %.4f want %.4f)" % [beam.uv1_offset.y, want])
		warp._update_animation(1.0)
		var want2 := (-7.62 - 1.35 * 1.5) / 2.0
		t.assert_true(abs(beam.uv1_offset.y - want2) < 0.0001, "boss scroll keeps accumulating without a seam (got %.4f want %.4f)" % [beam.uv1_offset.y, want2])
		t.assert_eq(base.uv1_offset, Vector3.ZERO, "boss base stays stationary; its page ride is in the mesh UVs")
		for state in ["locked", "open", "inactive", "active"]:
			warp.set_state(state)
			t.assert_eq(warp.model.get_child(0).get_active_material(0), beam, "state keeps boss cutout material")
		# Baked UVs: (uv * repeat + offset) / mirrored period 2.
		var beam_uvs: PackedVector2Array = beam_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var beam_half := false
		for uv in beam_uvs:
			if abs(uv.x - 0.5) < 0.001:
				beam_half = true
		t.assert_true(beam_half, "beam UVs halved into atlas space")
		var base_uvs: PackedVector2Array = base_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var base_pages := 0
		for uv in base_uvs:
			if abs(uv.y - 0.5) < 0.001 or abs(uv.y - 1.5) < 0.001:
				base_pages += 1
		t.assert_eq(base_pages, base_uvs.size(), "base UVs carry the one-page gold shift")
	for mat in originals:
		t.assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "shared imported alpha stays unchanged")
	warp.free()
