extends Node
## Boots a normal generated expedition with a separate playtest save directory.
const Generator := preload("res://scripts/3d/field/grid_generator.gd")
func _ready() -> void:
	CharacterManager.create_character(0, "humar", "Stage Test")
	CharacterManager.set_active_slot(0)
	var area := OS.get_environment("PSZ_STAGE_AREA")
	if area.is_empty():
		area = "ozette"
	if not Generator.AREA_CONFIG.has(area):
		push_error("Unknown field area: " + area)
		get_tree().quit(1)
		return
	SessionManager.enter_field(area, "normal")
	var generator := Generator.new()
	var sections: Array = generator.generate_tower_field("normal")["sections"] if area == "tower" else generator.generate_field("normal", area)["sections"]
	SessionManager.set_field_sections(sections)
	SessionManager.set_current_section(0)
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {"current_cell_pos": str(sections[0]["start_pos"]), "spawn_edge": "", "keys_collected": {}})
