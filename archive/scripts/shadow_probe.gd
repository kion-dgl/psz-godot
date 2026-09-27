extends SceneTree
## One-shot renderer probe (#656), numeric edition — decide the city
## catcher formula by sampled pixels, not eyeballs. Three stations on a
## white unlit floor, each with an INVISIBLE-but-casting box (transparent
## material: anything dark on the floor is the catcher, never the box):
##   1. shadow_to_opacity shader, omni energy 2
##   2. shadow_to_opacity shader, omni energy 40 (the counter's plaza light)
##   3. custom light() shader (alpha = 1 - ATTENUATION), omni energy 40
## After 30 frames the probe projects each station's SHADOW point and a
## CLEAN floor point to screen space and prints their luminance.
## Verdict rule: clean ≈ floor grey (no black floor), shadow clearly darker.
## Run: godot --path . -s scripts/tools/shadow_probe.gd

const STO_SHADER := "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, shadow_to_opacity;
void fragment() {
	ALBEDO = vec3(0.0);
}
"

const CUSTOM_SHADER := "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
void light() {
	ALPHA = clamp(ALPHA + (1.0 - ATTENUATION), 0.0, 1.0);
}
"

func _initialize() -> void:
	_run()

func _run() -> void:
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
	pm.size = Vector2(16, 8)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(0.85, 0.85, 0.85)
	pm.material = fmat
	floor_mi.mesh = pm
	root3d.add_child(floor_mi)

	var stations := [
		[-4.0, "sto", 2.0, 2],
		[0.0, "sto", 40.0, 4],
	]
	var sample_pts := []
	for st in stations:
		var x: float = st[0]
		var kind: String = st[1]
		var energy: float = st[2]
		var layer: int = st[3]

		var cat := MeshInstance3D.new()
		cat.name = "Catcher_%d" % int(x + 8)
		var pm2 := PlaneMesh.new()
		pm2.size = Vector2(3.2, 3.2)
		var cmat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = CUSTOM_SHADER if kind == "custom" else STO_SHADER
		cmat.shader = sh
		pm2.material = cmat
		cat.mesh = pm2
		cat.position = Vector3(x, 0.02, 0)
		cat.layers = layer
		root3d.add_child(cat)

		# Invisible but casting: fully transparent material, cast_shadow ON.
		var box := MeshInstance3D.new()
		box.name = "GhostBox_%d" % int(x + 8)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.9, 0.9)
		var bmat := StandardMaterial3D.new()
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(1, 1, 1, 0.0)
		bm.material = bmat
		box.mesh = bm
		box.position = Vector3(x, 0.45, 0)
		root3d.add_child(box)

		var omni := OmniLight3D.new()
		omni.position = Vector3(x + 0.5, 2.4, 0.4)
		omni.light_energy = energy
		omni.omni_range = 5.0
		omni.shadow_enabled = true
		root3d.add_child(omni)

		# The fill: a strong shadowless directional that reaches ONLY this
		# station's catcher (render layer). If shadow_to_opacity's alpha is
		# per-light, the fill zeroes the falloff veil while the omni's
		# shadow survives; if alpha is 1 - summed light, the fill kills the
		# omni shadows too — the numbers decide.
		var fill := DirectionalLight3D.new()
		fill.name = "Fill_%d" % int(x + 8)
		fill.rotation_degrees = Vector3(-70, 20, 0)
		fill.light_energy = 1.2
		fill.shadow_enabled = false
		fill.light_cull_mask = layer
		root3d.add_child(fill)

		# Light sits up-right of the box: the shadow lands down-left of it.
		# Clean sample: 1.4 right of the box, outside both box and shadow.
		sample_pts.append({
			"label": "st%d(%s,e%s,fill)" % [int(x + 8), kind, str(energy)],
			"shadow": Vector3(x - 0.5, 0.02, -0.4),
			"clean": Vector3(x + 1.4, 0.02, 0.0),
			"far": Vector3(x, 0.02, 2.6),
		})

	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.position = Vector3(0, 8.5, 7.5)
	cam.look_at(Vector3(0, 0, 0))

	for i in 30:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/probe.png")

	print("[probe] floor grey reference ≈ 217 (0.85 × 255)")
	for pt in sample_pts:
		var line := "[probe] %s —" % pt["label"]
		for key in ["shadow", "clean", "far"]:
			var world: Vector3 = pt[key]
			var screen := cam.unproject_position(world)
			if screen.x < 0 or screen.y < 0 or screen.x >= img.get_width() or screen.y >= img.get_height():
				line += " %s:offscreen" % key
				continue
			var c := img.get_pixel(int(screen.x), int(screen.y))
			line += "  %s:%d" % [key, round(255.0 * (0.3 * c.r + 0.5 * c.g + 0.2 * c.b))]
		print(line)
	quit()
