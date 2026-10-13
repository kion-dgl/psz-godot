extends SceneTree
## Independent oracle: original melonDS path tables, not Godot-generated fixtures.
const PathKernel = preload("res://scripts/3d/enemies/reyburn_path.gd")
var failures := 0

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/reyburn_parity.json"))
	var samples := 0
	for fixture: Dictionary in data.spline_fixtures:
		var control: Array[Vector3i] = []
		for point: Array in fixture.control_points_raw: control.append(Vector3i(point[0],point[1],point[2]))
		var path := PathKernel.new()
		path.begin(control,2048,20,true)
		check(path.samples.size() == fixture.points_raw.size(),"original sample count at tick %s" % fixture.tick)
		for i in mini(path.samples.size(),fixture.points_raw.size()):
			var p: Array = fixture.points_raw[i]
			check(path.samples[i] == Vector3i(p[0],p[1],p[2]),"exact Q12 original spline sample %s/%d" % [fixture.tick,i])
			check(path.distances[i] == int(fixture.distances_raw[i]),"exact original spline distance")
			samples += 1
	var motions := 0
	for fixture: Dictionary in data.motion_fixtures:
		var curve: Dictionary = {}
		for candidate: Dictionary in data.spline_fixtures:
			if candidate.tick == fixture.curve_tick and candidate.run == "flight_closeup": curve = candidate; break
		check(not curve.is_empty(), "motion has original curve")
		if curve.is_empty(): continue
		var path := PathKernel.new()
		for point: Array in curve.points_raw: path.samples.append(raw(point))
		for length in curve.distances_raw: path.distances.append(int(length))
		path.position = raw(fixture.position)
		path.motion = raw(fixture.motion)
		path.distance = int(fixture.distance)
		path.speed = int(fixture.speed)
		path.wanted_speed = path.speed
		path.gain = int(fixture.gain)
		path.active = true
		var error := path.tick()-raw(fixture.expected_position)
		check(maxi(absi(error.x),maxi(absi(error.y),absi(error.z))) <= 1,"original follower within one Q12 unit at %s" % fixture.tick)
		motions += 1
	print("Reyburn motion: %d original one-update fixtures" % motions)
	print("Reyburn parity: %d original spline samples, %d failures" % [samples,failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func raw(value: Array) -> Vector3i:
	return Vector3i(value[0],value[1],value[2])
