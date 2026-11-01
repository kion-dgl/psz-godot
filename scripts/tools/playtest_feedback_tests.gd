extends RefCounted
static func run(runner: Node) -> void:
	var rules = load("res://scripts/3d/field/section_entry.gd")
	var section := {"start_pos": "6,3", "entry_direction": "south"}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1101
	for i in range(16):
		var direction: String = ["north", "south", "east", "west"][rng.randi_range(0, 3)]
		runner.assert_eq(rules.resolve(direction, "6,3", section), direction, "explicit entry survives section fallback")
	runner.assert_eq(rules.resolve("", "6,3", section), "south", "section-selector entry uses south")
	runner.assert_eq(rules.resolve("", "5,3", section), "", "interior cells do not inherit section entry")
	runner.assert_eq(rules.resolve("", "6,3", {"start_pos": "6,3"}), "", "legacy section without entry stays compatible")

	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stage_configs/unified-stage-configs.json"))
	var portals: Array = config.s01b_sa1.portals
	for portal in portals:
		var expected: String = "south" if str(portal.id).ends_with("bppcx8w1") else "north"
		runner.assert_eq(portal.direction, expected, "Valley B gate labels follow thematic transition")
	var generator := preload("res://scripts/3d/field/grid_generator.gd").new()
	for rotation in [0, 90, 180, 270]:
		var baked: Dictionary = generator._baked_portals("s01b_sa1", rotation)
		runner.assert_eq(baked[StageRotation.rotate_dir("south", rotation)], "portal_1769178737883_7bppcx8w1", "thematic entrance survives rotation")
