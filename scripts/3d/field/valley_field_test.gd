extends Node
## Test launcher for field — uses GridGenerator to create a full
## multi-section field (a→e→b→z) and transitions to the 3D field scene.
## Change _area_id to test different areas (e.g. "gurhacia", "ozette").

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

## Change this to test different areas.
var _area_id: String = "gurhacia"

func _ready() -> void:
	# Set up a field session
	SessionManager.enter_field(_area_id, "normal")

	# Generate a full field with 4 sections
	var gen := GridGenerator.new()
	var field: Dictionary = gen.generate_field("normal", _area_id)
	var sections: Array = field["sections"]

	var area_name: String = GridGenerator.AREA_CONFIG.get(_area_id, {}).get("name", _area_id)
	print("[FieldTest] %s — Generated %d sections:" % [area_name, sections.size()])
	for i in range(sections.size()):
		var s: Dictionary = sections[i]
		var cell_count: int = s.get("cells", []).size()
		print("  Section %d: type=%s area=%s cells=%d start=%s" % [
			i, s.get("type", "?"), s.get("area", "?"), cell_count, s.get("start_pos", "?")])

	SessionManager.set_field_sections(sections)

	# Start at the first section's start cell
	var first_section: Dictionary = sections[0]
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": str(first_section["start_pos"]),
		"spawn_edge": "",
		"keys_collected": {},
	})
