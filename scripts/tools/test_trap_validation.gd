extends RefCounted
## Seeded contracts for /states/trap-validation.
static func run(t: Node) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/room_objects.json"))
	for room in data.rooms:
		var entry: Dictionary = data.rooms[room]
		t.assert_true(entry.groups != null, "%s retains authored group table" % room)
		for obj in entry.objects:
			t.assert_true(obj.g != null and int(obj.g) < entry.groups.size(), "%s record belongs to an authored group" % room)
	var material_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/trap_material_reference.json"))
	for profiles in [BearTrap.MATERIAL_PROFILES, NeedleTrap.MATERIAL_PROFILES]:
		for name in profiles:
			if name == "o0c_1_needle2": continue # Remake strip mapping intentionally differs from the source reference.
			for key in ["uv_scale", "uv_offset", "mirror_x", "mirror_y"]:
				var expected = material_data.floor_materials[name][key]
				if expected is Array: expected = Vector2(expected[0], expected[1])
				t.assert_eq(profiles[name][key], expected, name + " " + key + " matches original material")
	for uv in material_data.exported_quad_uv:
		var mapped := Vector2(uv[0], uv[1]) * TrapBall.BALL_UV_SCALE + TrapBall.BALL_UV_OFFSET
		var index: int = material_data.exported_quad_uv.find(uv)
		var original: Array = material_data.original_gpu[0].uv_s12_4[index]
		t.assert_true(mapped.is_equal_approx(Vector2(original[0], original[1]) / 256.0), "burst UV matches original GPU vertex %d" % index)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(64):
		rng.seed = seed_value
		var objects := FieldPopulation.authored_objects("s02a_nc2", 5, rng)
		var guns := objects.filter(func(obj): return obj.type == "gun_trap")
		t.assert_eq(guns.size(), 2, "nc2 seed %d selects two guns, never four" % seed_value)
	var timing_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/trap_timing_reference.json"))
	t.assert_eq(TrapBall.FUSE_FPS, float(timing_data.nominal_updates_per_second), "fuse clock matches retained original traces")
	t.assert_eq(TrapBall.FIELD_RISE_Q12, timing_data.rise_y_raw_q12.map(func(value): return int(value)), "rise curve retains original Q12 samples")
	for sample in timing_data.field_normal_traces:
		t.assert_eq(int(sample.counting_updates), 46, "original normal counting interval")
	var trap := TrapBall.build_field("ice_trap", 0)
	trap.set_process(false)
	trap._arm()
	var fuse := trap._fuse_left
	t.assert_true(is_equal_approx(trap._rise_height(), TrapBall.FIELD_REST_HEIGHT), "field trap starts at suspended armed height")
	trap._process(TrapBall.FIELD_RISE_SECONDS * 0.5)
	t.assert_true(is_equal_approx(trap._fuse_left, fuse), "rise does not consume fuse")
	trap._process(TrapBall.FIELD_RISE_SECONDS * 0.5)
	t.assert_true(is_equal_approx(trap._fuse_left, fuse) and is_equal_approx(trap._rise, 1.0), "full rise precedes countdown")
	t.assert_true(is_equal_approx(trap._rise_height(), TrapBall.FIELD_REST_HEIGHT - TrapBall.FIELD_ARM_DROP), "arming lowers ball by a quarter unit")
	trap._process(0.1)
	t.assert_true(is_equal_approx(trap._fuse_left, fuse - 0.1), "countdown starts after rise")
	trap.free()
