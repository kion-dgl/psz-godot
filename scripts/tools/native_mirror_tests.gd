extends RefCounted
const Bake := preload("res://scripts/utils/native_mirror_bake.gd")
const Variants := preload("res://scripts/utils/valley_mirror_variants.gd")

static func _sample(image: Image, uv: Vector2) -> Color:
	var pixel := uv * Vector2(image.get_width(), image.get_height()) - Vector2(0.5, 0.5)
	var base := Vector2i(floor(pixel.x), floor(pixel.y))
	var blend := pixel - Vector2(base)
	var colors: Array[Color] = []
	for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		colors.append(image.get_pixel(posmod(base.x+offset.x, image.get_width()), posmod(base.y+offset.y, image.get_height())))
	return colors[0].lerp(colors[1], blend.x).lerp(colors[2].lerp(colors[3], blend.x), blend.y)

static func run(runner: Node) -> void:
	print("── native mirror UV/texture conversion (#381) ──")
	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(8):
			image.set_pixel(x, y, Color(float(x)/7.0, float(y)/3.0, float((x+y)%3)/2.0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 381
	var maximum_error := 0.0
	for wrap_modes in [["mirror", "repeat"], ["repeat", "mirror"], ["mirror", "mirror"]]:
		var fix := {"wrapS": wrap_modes[0], "wrapT": wrap_modes[1], "repeatX": 2.1, "repeatY": -1.3, "offsetX": -0.27, "offsetY": 0.88}
		var atlas := Bake.atlas_image(image, fix)
		for sample in range(512):
			var uv := Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
			var effective := uv * Vector2(2.1, -1.3) + Vector2(-0.27, 0.88)
			if sample < 10:
				effective = Vector2(sample-5, 5-sample)
				uv = (effective-Vector2(-0.27, 0.88))/Vector2(2.1, -1.3)
			for axis in range(2):
				if wrap_modes[axis] == "mirror":
					var edge := 0.5 / (image.get_width() if axis == 0 else image.get_height())
					effective[axis] = clampf(1.0-absf(fposmod(effective[axis], 2.0)-1.0), edge, 1.0-edge)
			var a := _sample(image, effective)
			var b := _sample(atlas, Bake.remap_uv(uv, fix))
			maximum_error = maxf(maximum_error, maxf(abs(a.r-b.r), maxf(abs(a.g-b.g), abs(a.b-b.b))))
	runner.assert_true(maximum_error < 0.0001, "1536 seeded samples: reflected period matches folded sampling")
	_test_contracts(runner, image)

static func _test_contracts(runner: Node, image: Image) -> void:
	var fix := {"wrapS": "mirror", "repeatX": 2.0, "offsetY": 0.88}
	runner.assert_true(Bake.eligible(fix, "path.png"), "static mirror row eligible")
	for extra in [{"hidden": true}, {"scrollY": 0}, {"framesY": 2}, {"bakedBlend": true}, {"wrapT": "clamp"}]:
		var unsupported := fix.merged(extra, true)
		runner.assert_true(not Bake.eligible(unsupported, "path.png"), "unsupported row skipped: " + str(extra))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-2, 0), Vector2(3, 0), Vector2(0, 2)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(0.2, 0.3, 0.4, 0), Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
	var baked := Bake.bake_arrays(arrays, fix)
	runner.assert_eq(baked[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_VERTEX], "original positions retained")
	runner.assert_eq(baked[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_INDEX], "topology retained")
	runner.assert_eq(baked[Mesh.ARRAY_COLOR][0], Color(0.2, 0.3, 0.4, 1), "RGB retained; formerly ignored vertex alpha opaque")
	runner.assert_eq(arrays[Mesh.ARRAY_COLOR][0].a, 0.0, "source arrays not mutated")
	var source := StandardMaterial3D.new()
	source.resource_name = "1_pass1"
	source.albedo_texture = ImageTexture.create_from_image(image)
	var material := Bake.material(source, ImageTexture.create_from_image(Bake.atlas_image(image, fix)), fix)
	runner.assert_eq(material.uv1_scale, Vector3.ONE, "no second UV scale")
	runner.assert_eq(material.uv1_offset, Vector3.ZERO, "no second UV offset")
	runner.assert_true(material.next_pass == null, "no shader next-pass")
	runner.assert_eq(Variants.field_material(material, true, []).shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "Valley architecture keeps authored bake")
	runner.assert_eq(Variants.field_material(material, true, ["1_pass1"]).shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL, "lit-list selection uses native lighting")
	var entry := {"version": Bake.VERSION, "fixes": {"path.png": fix}}
	runner.assert_true(Variants.current_rows(entry, {"path.png": fix}), "current settings accepted")
	runner.assert_true(not Variants.current_rows(entry, {"path.png": {}}), "stale settings rejected")
