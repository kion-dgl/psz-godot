extends Control
## Valley Field — 2D terminal grid exploration with multi-section progression.
## Sections: Valley A (grid) → Valley E (transition) → Valley B (grid) → Valley Z (boss)
## Shows ASCII map, navigate with arrow keys, collect keys to unlock gates.

const SECTION_NAMES := {"a": "Valley A", "e": "Valley E (Transition)", "b": "Valley B", "z": "Valley Z (Boss)"}

var _grid: Array = []
var _cell_map: Dictionary = {}  # "row,col" → cell dict
var _current_pos: String = ""
var _keys_collected: Dictionary = {}  # gate_cell_pos → true
var _section: Dictionary = {}
var _section_type: String = "grid"
var _section_area: String = "a"

@onready var header_label: Label = $VBox/HeaderLabel
@onready var map_panel: PanelContainer = $VBox/HBox/MapPanel
@onready var info_panel: PanelContainer = $VBox/HBox/InfoPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	var data: Dictionary = SceneManager.get_transition_data()
	_current_pos = data.get("current_cell_pos", "")
	_keys_collected = data.get("keys_collected", {})

	# Load current section from session
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()

	if sections.is_empty():
		# Fallback: try legacy grid storage
		_grid = SessionManager.get_grid()
		_section_type = "grid"
		_section_area = "a"
	else:
		_section = sections[section_idx]
		_grid = _section.get("cells", [])
		_section_type = str(_section.get("type", "grid"))
		_section_area = str(_section.get("area", "a"))

	if _grid.is_empty():
		push_warning("ValleyField: No grid data")
		return

	for cell in _grid:
		_cell_map[str(cell["pos"])] = cell

	if _current_pos.is_empty():
		# Use section start_pos or find start cell
		var start_pos: String = str(_section.get("start_pos", ""))
		if not start_pos.is_empty() and _cell_map.has(start_pos):
			_current_pos = start_pos
		else:
			for cell in _grid:
				if cell.get("is_start", false):
					_current_pos = str(cell["pos"])
					break

	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	var cell: Dictionary = _cell_map.get(_current_pos, {})
	if cell.is_empty():
		return

	var connections: Dictionary = cell.get("connections", {})

	if event.is_action_pressed("ui_up"):
		_try_move(cell, connections, "north")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_try_move(cell, connections, "south")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_try_move(cell, connections, "west")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_try_move(cell, connections, "east")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if cell.get("is_end", false):
			_on_end_reached()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_return_to_city()
		get_viewport().set_input_as_handled()


func _try_move(cell: Dictionary, connections: Dictionary, direction: String) -> void:
	if not connections.has(direction):
		return
	# Check key-gate lock
	if cell.get("is_key_gate", false) \
			and str(cell.get("key_gate_direction", "")) == direction \
			and not _keys_collected.has(_current_pos):
		hint_label.text = "This gate is locked! Find the key first."
		return
	_move_to(connections[direction])


func _move_to(target_pos: String) -> void:
	_current_pos = target_pos
	# Collect key at new position
	var cell: Dictionary = _cell_map.get(_current_pos, {})
	if cell.get("has_key", false):
		var gate_pos: String = str(cell.get("key_for_cell", ""))
		if not gate_pos.is_empty() and not _keys_collected.has(gate_pos):
			_keys_collected[gate_pos] = true
	_refresh_display()


func _on_end_reached() -> void:
	if SessionManager.advance_section():
		var sections: Array = SessionManager.get_field_sections()
		var new_section: Dictionary = sections[SessionManager.get_current_section()]
		SceneManager.goto_scene("res://scenes/2d/valley_field.tscn", {
			"current_cell_pos": str(new_section.get("start_pos", "")),
			"keys_collected": {},
		})
	else:
		_return_to_city()


func _return_to_city() -> void:
	SessionManager.return_to_city()
	SceneManager.goto_scene("res://scenes/3d/city/city_warp.tscn")


func _refresh_display() -> void:
	var session: Dictionary = SessionManager.get_session()
	var sections: Array = SessionManager.get_field_sections()
	var section_idx: int = SessionManager.get_current_section()
	var section_label: String = SECTION_NAMES.get(_section_area, "Valley")
	var progress := ""
	if sections.size() > 1:
		progress = " (%d/%d)" % [section_idx + 1, sections.size()]
	header_label.text = "─── Gurhacia Valley ─── %s%s ───" % [section_label, progress]

	_refresh_map()
	_refresh_info()

	var cell: Dictionary = _cell_map.get(_current_pos, {})
	var connections: Dictionary = cell.get("connections", {})
	var dirs: Array[String] = []
	for d in ["north", "south", "west", "east"]:
		if connections.has(d):
			var arrow := {"north": "↑N", "south": "↓S", "west": "←W", "east": "→E"}
			dirs.append(arrow[d])

	var dir_str: String = "  ".join(dirs) if not dirs.is_empty() else "none"
	var extra := ""
	if cell.get("is_end", false):
		if SessionManager.get_field_sections().size() > 0:
			extra = "  [ENTER] Next Section"
		else:
			extra = "  [ENTER] Exit Field"
	hint_label.text = "[Arrow Keys] Move: %s  [ESC] Return to City%s" % [dir_str, extra]


func _refresh_map() -> void:
	for child in map_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = "── MAP ──"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	# For single-room sections, show simple display
	if _section_type in ["transition", "boss"]:
		var room_label := Label.new()
		if _section_type == "transition":
			room_label.text = "\n  [Transition Area]\n\n  Press ENTER to continue."
		else:
			room_label.text = "\n  [Boss Arena]\n\n  Press ENTER to complete field."
		room_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		vbox.add_child(room_label)
		map_panel.add_child(vbox)
		return

	# Find grid bounds
	var min_row := 999
	var max_row := -999
	var min_col := 999
	var max_col := -999
	for cell in _grid:
		var pos: Vector2i = _parse_pos(str(cell["pos"]))
		min_row = mini(min_row, pos.x)
		max_row = maxi(max_row, pos.x)
		min_col = mini(min_col, pos.y)
		max_col = maxi(max_col, pos.y)

	for row in range(min_row, max_row + 1):
		# North connectors
		var north_line := ""
		for col in range(min_col, max_col + 1):
			var key := "%d,%d" % [row, col]
			if _cell_map.has(key):
				var cell: Dictionary = _cell_map[key]
				var conns: Dictionary = cell.get("connections", {})
				if conns.has("north"):
					north_line += "  |  "
				else:
					north_line += "     "
			else:
				north_line += "     "
		if north_line.strip_edges() != "":
			var nl := Label.new()
			nl.text = north_line
			nl.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
			vbox.add_child(nl)

		# Cell row
		var cell_line := ""
		for col in range(min_col, max_col + 1):
			var key := "%d,%d" % [row, col]
			if _cell_map.has(key):
				var cell: Dictionary = _cell_map[key]
				var conns: Dictionary = cell.get("connections", {})
				# West connector
				if conns.has("west"):
					cell_line += "-"
				else:
					cell_line += " "
				# Cell symbol
				cell_line += _cell_symbol(key, cell)
				# East connector
				if conns.has("east"):
					cell_line += "-"
				else:
					cell_line += " "
			else:
				cell_line += "     "

		var cl := Label.new()
		cl.text = cell_line
		if "[@]" in cell_line:
			cl.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		vbox.add_child(cl)

		# South connectors
		var south_line := ""
		for col in range(min_col, max_col + 1):
			var key := "%d,%d" % [row, col]
			if _cell_map.has(key):
				var cell: Dictionary = _cell_map[key]
				var conns: Dictionary = cell.get("connections", {})
				if conns.has("south"):
					south_line += "  |  "
				else:
					south_line += "     "
			else:
				south_line += "     "
		if south_line.strip_edges() != "":
			var sl := Label.new()
			sl.text = south_line
			sl.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
			vbox.add_child(sl)

	# Legend
	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)
	var legend := Label.new()
	legend.text = "[@] You  [S] Start  [E] Exit  [.] Room"
	var extra_legend := ""
	# Check if any key/gate cells exist
	var has_keys := false
	var has_gates := false
	var has_branches := false
	for cell in _grid:
		if cell.get("has_key", false):
			has_keys = true
		if cell.get("is_key_gate", false):
			has_gates = true
		if cell.get("is_branch", false):
			has_branches = true
	if has_branches:
		extra_legend += "  [~] Dead End"
	if has_keys:
		extra_legend += "  [K] Key"
	if has_gates:
		extra_legend += "  [!] Locked"
	legend.text += extra_legend
	legend.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
	vbox.add_child(legend)

	map_panel.add_child(vbox)


func _cell_symbol(key: String, cell: Dictionary) -> String:
	if key == _current_pos:
		return "[@]"
	if cell.get("is_start", false):
		return "[S]"
	if cell.get("is_end", false):
		return "[E]"
	if cell.get("has_key", false):
		var gate_pos: String = str(cell.get("key_for_cell", ""))
		if _keys_collected.has(gate_pos):
			return "[.]"  # Key already collected
		return "[K]"
	if cell.get("is_key_gate", false):
		if _keys_collected.has(key):
			return "[*]"  # Gate unlocked
		return "[!]"
	if cell.get("is_branch", false):
		return "[~]"
	return "[.]"


func _refresh_info() -> void:
	for child in info_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "── INFO ──"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	var cell: Dictionary = _cell_map.get(_current_pos, {})
	var stage_id: String = cell.get("stage_id", "???")
	var stage_short: String = stage_id.replace("s01a_", "").replace("s01b_", "").replace("s01e_", "").to_upper()

	var stage_label := Label.new()
	stage_label.text = "Section: %s" % stage_short
	vbox.add_child(stage_label)

	var rotation: int = int(cell.get("rotation", 0))
	if rotation != 0:
		var rot_label := Label.new()
		rot_label.text = "Rotation: %d°" % rotation
		rot_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		vbox.add_child(rot_label)

	var pos_label := Label.new()
	pos_label.text = "Grid: %s" % _current_pos
	pos_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
	vbox.add_child(pos_label)

	if cell.get("is_start", false):
		var start_label := Label.new()
		start_label.text = "Entrance area"
		start_label.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(start_label)

	if cell.get("is_end", false):
		var end_label := Label.new()
		end_label.text = "Exit — press ENTER to continue"
		end_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		vbox.add_child(end_label)

	if cell.get("has_key", false):
		var gate_pos: String = str(cell.get("key_for_cell", ""))
		var key_label := Label.new()
		if _keys_collected.has(gate_pos):
			key_label.text = "Key collected!"
			key_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		else:
			key_label.text = "You found a key!"
			key_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		vbox.add_child(key_label)

	if cell.get("is_key_gate", false):
		var gate_label := Label.new()
		if _keys_collected.has(_current_pos):
			gate_label.text = "Gate: UNLOCKED"
			gate_label.add_theme_color_override("font_color", ThemeColors.HEADER)
		else:
			var locked_dir: String = str(cell.get("key_gate_direction", ""))
			gate_label.text = "Gate: LOCKED (%s)" % locked_dir.to_upper()
			gate_label.add_theme_color_override("font_color", ThemeColors.DANGER)
		vbox.add_child(gate_label)

	if cell.get("is_branch", false):
		var branch_label := Label.new()
		branch_label.text = "Dead end"
		branch_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		vbox.add_child(branch_label)

	# Passages
	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)

	var conn_header := Label.new()
	conn_header.text = "Passages:"
	conn_header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(conn_header)

	var connections: Dictionary = cell.get("connections", {})
	if connections.is_empty():
		var none_label := Label.new()
		none_label.text = "  (none)"
		none_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		vbox.add_child(none_label)
	else:
		for edge in connections:
			var target_cell: Dictionary = _cell_map.get(connections[edge], {})
			var target_stage: String = str(target_cell.get("stage_id", "???"))
			target_stage = target_stage.replace("s01a_", "").replace("s01b_", "").replace("s01e_", "").to_upper()
			var dir_label := Label.new()
			var locked := ""
			if cell.get("is_key_gate", false) \
					and str(cell.get("key_gate_direction", "")) == edge \
					and not _keys_collected.has(_current_pos):
				locked = " [LOCKED]"
			dir_label.text = "  %s -> %s%s" % [edge.capitalize(), target_stage, locked]
			if not locked.is_empty():
				dir_label.add_theme_color_override("font_color", ThemeColors.DANGER)
			vbox.add_child(dir_label)

	# Session info
	var sep2 := Label.new()
	sep2.text = ""
	vbox.add_child(sep2)

	var session: Dictionary = SessionManager.get_session()
	var diff_label := Label.new()
	diff_label.text = "Difficulty: %s" % str(session.get("difficulty", "normal")).capitalize()
	vbox.add_child(diff_label)

	# Keys status
	var total_keys := 0
	var collected := 0
	for c in _grid:
		if c.get("has_key", false):
			total_keys += 1
			var gp: String = str(c.get("key_for_cell", ""))
			if _keys_collected.has(gp):
				collected += 1
	if total_keys > 0:
		var keys_label := Label.new()
		keys_label.text = "Keys: %d/%d" % [collected, total_keys]
		keys_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		vbox.add_child(keys_label)

	# Room count
	var progress_label := Label.new()
	progress_label.text = "Rooms: %d total" % _grid.size()
	progress_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
	vbox.add_child(progress_label)

	info_panel.add_child(vbox)


func _parse_pos(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
