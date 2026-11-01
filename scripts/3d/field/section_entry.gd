extends RefCounted
## Destination-owned entry selection; /states/playtest-feedback.
static func resolve(explicit_edge: String, cell_pos: String, section: Dictionary) -> String:
	if not explicit_edge.is_empty():
		return explicit_edge
	if cell_pos == str(section.get("start_pos", "")):
		return str(section.get("entry_direction", ""))
	return ""
