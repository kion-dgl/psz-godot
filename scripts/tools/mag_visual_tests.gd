extends RefCounted
const Visuals := preload("res://scripts/3d/player/mag_visuals.gd")

static func run(r: Node) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.set_pixel(0, 0, Color.TRANSPARENT)
	r.assert_true(Visuals.binary_alpha(image), "Mag binary alpha includes cutout pixels")
	var original := StandardMaterial3D.new()
	original.albedo_texture = ImageTexture.create_from_image(image)
	original.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	original.cull_mode = BaseMaterial3D.CULL_DISABLED
	original.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var fixed := Visuals.cutout_copy(original) as StandardMaterial3D
	r.assert_true(fixed != original, "Mag material fix is instance-local")
	r.assert_eq(fixed.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Mag cutout uses depth-tested opaque rendering")
	r.assert_eq(original.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, "Mag source import remains unchanged")
	r.assert_true(fixed.albedo_texture == original.albedo_texture and fixed.cull_mode == original.cull_mode and fixed.shading_mode == original.shading_mode, "Mag UV texture, double sides and shading are preserved")
	r.assert_true(Visuals.cutout_copy(fixed) == fixed, "Mag normalization is idempotent")
	image.set_pixel(1, 1, Color(1, 1, 1, 0.5))
	r.assert_true(not Visuals.binary_alpha(image), "genuine translucent Mag textures are not cutouts")
	original.albedo_texture = ImageTexture.create_from_image(image)
	r.assert_true(Visuals.cutout_copy(original) == original, "genuine translucent materials stay unchanged")
