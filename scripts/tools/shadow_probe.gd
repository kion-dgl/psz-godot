extends SceneTree
## One-shot renderer probe (#656): does shadow_to_opacity actually render an
## omni's shadow on the compatibility renderer? Deterministic geometry only —
## a white unlit floor, a shadow_to_opacity plane 0.02 above it, a box caster,
## one shadow-casting omni, ambient 0.5 to match the counter sidecar. The
## saved frame answers it: dark quad under the box = yes; uniform grey floor
## = the flag no-ops into a plain overlay; clean white floor = nothing.
## Run: godot --path . -s scripts/tools/shadow_probe.gd  (writes /tmp/probe.png)

func _initialize() -> void:
	_run()

func _run() -> void:
	# The tree isn't live during _initialize — build only once a frame has
	# passed (look_at and friends need a real tree).
	await process_frame
	var root3d := Node3D.new()
	root3d.name = "Probe"
	get_root().add_child(root3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.88, 0.82)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)

	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(0.85, 0.85, 0.85)
	pm.material = fmat
	floor_mi.mesh = pm
	root3d.add_child(floor_mi)

	var cat := MeshInstance3D.new()
	cat.name = "Catcher"
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(8, 8)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0, 0, 0, 0.55)
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shadow_to_opacity = true
	pm2.material = cmat
	cat.mesh = pm2
	cat.position = Vector3(0, 0.02, 0)
	root3d.add_child(cat)

	var box := MeshInstance3D.new()
	box.name = "Box"
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	box.mesh = bm
	box.position = Vector3(0, 0.5, 0)
	root3d.add_child(box)

	var omni := OmniLight3D.new()
	omni.position = Vector3(0.6, 3.0, 0.4)
	omni.light_energy = 2.0
	omni.omni_range = 12.0
	omni.shadow_enabled = true
	root3d.add_child(omni)

	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.position = Vector3(3.2, 2.8, 3.2)
	cam.look_at(Vector3(0, 0.2, 0))

	for i in 30:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/probe.png")
	print("[probe] wrote /tmp/probe.png")
	quit()
