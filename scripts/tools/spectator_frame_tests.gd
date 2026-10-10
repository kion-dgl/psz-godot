extends RefCounted
const Spectator = preload("res://scripts/3d/field/coliseum_spectator.gd")

static func fixture() -> Texture2D:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	# Unequal transparent padding and breathing heights, but one world anchor.
	for frame in 4:
		image.fill_rect(Rect2i(frame * 8 + 2, 2 + frame % 2, 4, 10 - frame % 2), Color.WHITE)
	return ImageTexture.create_from_image(image)

static func run(r: Node) -> void:
	print("── Coliseum spectator idle frames ──")
	var frames: SpriteFrames = Spectator.make_frames(fixture(), 4)
	r.assert_eq(frames.get_frame_count("idle"), 4, "four idle poses")
	r.assert_true(frames.get_animation_loop("idle"), "idle repeats")
	r.assert_gt(frames.get_frame_duration("idle", 0), frames.get_frame_duration("idle", 2), "blink is shorter than rest")
	for index in 4:
		var frame := frames.get_frame_texture("idle", index) as AtlasTexture
		r.assert_eq(frame.get_size(), Vector2(4, 10), "frame canvas stays constant")
		r.assert_eq(frame.margin.position.y + frame.region.size.y, 10.0, "feet stay on baseline")
	var fallback: SpriteFrames = Spectator.make_frames(fixture(), 1)
	r.assert_eq(fallback.get_frame_count("idle"), 1, "legacy still-image fallback")
	var stage := Node3D.new()
	Spectator.add_to_stage(stage, "unrelated_stage")
	r.assert_eq(stage.get_child_count(), 0, "spectators only appear in coliseum")
	stage.free()

## Runtime layer, called by the isolated startup/spectator probe in CI.
static func run_live(r: Node) -> void:
	var stage := Node3D.new()
	r.add_child(stage)
	var path := "user://spectator_fixture.tres"
	ResourceSaver.save(fixture(), path)
	Spectator._add(stage, "KionProbe", path, Vector3(-12.3, 4.0, -24.6), 1.0, 0)
	Spectator._add(stage, "RosalineProbe", path, Vector3(14.35, 4.0, 22.55), 0.8, 1)
	var kion := stage.get_node("KionProbe") as AnimatedSprite3D
	var rosaline := stage.get_node("RosalineProbe") as AnimatedSprite3D
	r.assert_true(kion.frame != rosaline.frame, "spectators start out of phase")
	var changes := [0]
	kion.frame_changed.connect(func(): changes[0] += 1)
	kion.speed_scale = 8.0
	await r.get_tree().create_timer(0.7).timeout
	r.assert_true(changes[0] >= 2, "spectator animation advances through frames")
	r.assert_true(is_equal_approx(kion.position.y - 3.3 / 2, 4.0), "Kion feet stay anchored")
	r.assert_true(is_equal_approx(rosaline.position.y - 2.64 / 2, 4.0), "Rosaline feet stay anchored")
	r.assert_eq(kion.billboard, BaseMaterial3D.BILLBOARD_DISABLED, "spectator keeps inward facing")
	r.assert_eq(kion.get_child_count(), 0, "spectator has no interaction or collision children")
	stage.queue_free()
	DirAccess.remove_absolute(path)
	print("[startup-probe] spectator animation checked")
