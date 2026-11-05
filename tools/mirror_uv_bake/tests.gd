extends SceneTree
const Fixture = preload("fixture.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func sample_linear(image: Image, uv: Vector2) -> Color:
	var x := uv.x * image.get_width() - 0.5
	var y := uv.y * image.get_height() - 0.5
	var ix := int(floor(x))
	var iy := int(floor(y))
	var a := image.get_pixel(posmod(ix, image.get_width()), posmod(iy, image.get_height()))
	var b := image.get_pixel(posmod(ix+1, image.get_width()), posmod(iy, image.get_height()))
	var c := image.get_pixel(posmod(ix, image.get_width()), posmod(iy+1, image.get_height()))
	var d := image.get_pixel(posmod(ix+1, image.get_width()), posmod(iy+1, image.get_height()))
	return a.lerp(b, x-floor(x)).lerp(c.lerp(d, x-floor(x)), y-floor(y))

func folded(value: float) -> float:
	return 1.0 - abs(fposmod(value, 2.0)-1.0)

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 381
	for id in ["stage", "synthetic"]:
		var fixture: Dictionary = Fixture.read_fixture(id)
		var image: Image = Fixture.source_image(fixture)
		var atlas: Image = Fixture.reflected_atlas(image, fixture.settings.mirror)
		check(atlas.get_width() == image.get_width() * (2 if fixture.settings.mirror[0] else 1), id + " atlas width")
		check(atlas.get_height() == image.get_height() * (2 if fixture.settings.mirror[1] else 1), id + " atlas height")
		for i in range(2000):
			var uv := Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			# Include exact folds and half-texel neighborhoods, not just random UVs.
			if i < 10:
				uv = Vector2(float(i-5), float(5-i))
			var original := uv
			var baked := uv
			for axis in range(2):
				if fixture.settings.mirror[axis]:
					var half_texel := 0.5 / (image.get_width() if axis == 0 else image.get_height())
					original[axis] = clampf(folded(uv[axis]), half_texel, 1.0-half_texel)
					baked[axis] = folded(uv[axis]) / 2.0
			var a := sample_linear(image, original)
			var b := sample_linear(atlas, baked)
			check(maxf(abs(a.r-b.r), maxf(abs(a.g-b.g), abs(a.b-b.b))) < 0.0001, id + " bilinear sampling mismatch at " + str(uv))
		var mesh: ArrayMesh = Fixture.build_candidate(fixture)
		var material := mesh.surface_get_material(0)
		check(material is StandardMaterial3D and not material is ShaderMaterial, id + " must use native material")
		check(material.next_pass == null, id + " must have no shader next pass")
		check(material.texture_repeat, id + " ordinary repeat must be enabled")
		check(mesh.surface_get_array_len(0) == fixture.baked.position.size()/3, id + " vertex count")
		check(mesh.get_aabb().is_equal_approx(Fixture.mesh_from_data(fixture.original).get_aabb()), id + " silhouette bounds")
		var resource_path := "user://test_%s.res" % id
		check(ResourceSaver.save(mesh, resource_path) == OK, id + " resource save")
		var restored := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		check(restored != null and restored.surface_get_material(0) is StandardMaterial3D, id + " resource roundtrip")
		print("[mirror-test] %s %dx%d -> %dx%d; %d triangles; native material OK" % [id, image.get_width(), image.get_height(), atlas.get_width(), atlas.get_height(), mesh.surface_get_array_len(0)/3])
	print("[mirror-test] failures=%d; 4000 seeded texture samples" % failures)
	quit(1 if failures else 0)
