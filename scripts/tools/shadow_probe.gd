extends SceneTree
## One-shot renderer probe (#656): shadow_to_opacity, shader path vs the
## StandardMaterial3D flag. The flag no-ops on the compatibility renderer
## (the first probe, 2026-09-26: clean floor, no shadow, no overlay) — the
## AR community claims the SHADER render_mode behaves differently. Same
## deterministic rig as before: white unlit floor, catcher plane 0.02 up,
## box caster, one shadow-casting omni, ambient 0.5 to match the counter
## sidecar (upstream #62257: opacity multiplies by ambient — if the shadow
## shows here it shows at half strength in-game, tunable).
## Run: godot --path . -s scripts/tools/shadow_probe.gd  (writes /tmp/probe.png)

const CATCHER_SHADER := "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, shadow_to_opacity;
void fragment() {
	ALBEDO = vec3(0.0);
}
"

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
	var cmat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CATCHER_SHADER
	cmat.shader = sh
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
