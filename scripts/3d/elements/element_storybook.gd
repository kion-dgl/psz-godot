extends Node3D
## Element Storybook — Interactive browser for all game elements.
## Browse by category, preview in 3D, cycle through states.

const FONT_PATH := "res://assets/fonts/JetBrainsMono-Regular.ttf"
const BOLD_FONT_PATH := "res://assets/fonts/JetBrainsMono-Bold.ttf"
const FONT_SIZE := 16

# BBCode color constants
const C_HEADER := "#66bfd9"
const C_SELECTED := "#f0a020"
const C_TEXT := "#e0e6f0"
const C_MUTED := "#808ca6"

# Camera (static 3/4 view)
const CAMERA_ANGLE := 0.8
const ORBIT_RADIUS := 5.0
const ORBIT_HEIGHT := 2.5
const ORBIT_LOOK_Y := 0.8

# Laser/animated texture identification (by texture path substring)
const LASER_TEXTURE_IDS := ["o0c_1_gate", "o0c_1_fence2", "fwarp2", "swarp3", "o0c_1_mspack"]

# Per-element laser scroll config: axis ("x" or "y") + speed
const LASER_SCROLL_CONFIG := {
	"gate": {"axis": "x", "speed": -0.40},
	"key_gate": {"axis": "x", "speed": -0.40},
	"area_warp": {"axis": "x", "speed": -1.35},
	"start_warp": {"axis": "y", "speed": -1.35},
	"fence": {"axis": "x", "speed": -0.70},
	"fence4": {"axis": "x", "speed": -0.70},
	"message_pack": {"axis": "y", "speed": 0.45},
}

# Per-element texture fixups matching psz-sketch TEXTURE_CONFIG.
const TEXTURE_FIXUPS := {
	"gate": [{"match": "o0c_0_gatet", "scale": Vector3(1, 2, 1), "offset": Vector3(0.56, 0.8, 0)}],
	"key_gate": [{"match": "o0c_0_gatet", "scale": Vector3(1, 2, 1), "offset": Vector3(0.56, 0.8, 0)}],
}

const CATEGORIES := [
	{
		"name": "Gates",
		"elements": [
			{"id": "gate", "title": "Gate", "desc": "Blocks passage. Opens when enemies defeated.",
			 "script": "res://scripts/3d/elements/gate.gd",
			 "states": ["locked", "open"], "default": "locked"},
			{"id": "key_gate", "title": "Key Gate", "desc": "Requires key item to unlock.",
			 "script": "res://scripts/3d/elements/key_gate.gd",
			 "states": ["locked", "open"], "default": "locked"},
		]
	},
	{
		"name": "Fences",
		"elements": [
			{"id": "fence", "title": "Fence", "desc": "Laser barrier disabled by switches.",
			 "script": "res://scripts/3d/elements/fence.gd",
			 "states": ["active", "disabled"], "default": "active"},
			{"id": "fence4", "title": "Fence (4-Sided)", "desc": "Four-sided fence variant.",
			 "script": "res://scripts/3d/elements/fence.gd",
			 "states": ["active", "disabled"], "default": "active",
			 "props": {"variant": 1}},
		]
	},
	{
		"name": "Switches",
		"elements": [
			{"id": "interact_switch", "title": "Interact Switch", "desc": "E-key toggle. Disables fences.",
			 "script": "res://scripts/3d/elements/interact_switch.gd",
			 "states": ["off", "on"], "default": "off"},
			{"id": "step_switch", "title": "Step Switch", "desc": "Floor plate. Activates on step.",
			 "script": "res://scripts/3d/elements/step_switch.gd",
			 "states": ["off", "on"], "default": "off"},
		]
	},
	{
		"name": "Containers",
		"elements": [
			{"id": "box", "title": "Box", "desc": "Breakable container. Drops items.",
			 "script": "res://scripts/3d/elements/box.gd",
			 "states": ["intact", "destroyed"], "default": "intact"},
			{"id": "rare_box", "title": "Rare Box", "desc": "Drops valuable items.",
			 "script": "res://scripts/3d/elements/box.gd",
			 "states": ["intact", "destroyed"], "default": "intact",
			 "props": {"is_rare": true}},
			{"id": "wall", "title": "Wall", "desc": "Breakable wall obstacle.",
			 "script": "res://scripts/3d/elements/wall.gd",
			 "states": ["intact", "destroyed"], "default": "intact"},
		]
	},
	{
		"name": "Pickups",
		"elements": [
			{"id": "key", "title": "Key", "desc": "Unlocks key-gates. Floats and spins.",
			 "script": "res://scripts/3d/elements/key_pickup.gd",
			 "states": ["available", "collected"], "default": "available"},
			{"id": "drop_meseta", "title": "Drop (Meseta)", "desc": "Currency pickup.",
			 "script": "res://scripts/3d/elements/drop_meseta.gd",
			 "states": ["available", "collected"], "default": "available"},
			{"id": "drop_item", "title": "Drop (Item)", "desc": "Generic item pickup.",
			 "script": "res://scripts/3d/elements/drop_base.gd",
			 "states": ["available", "collected"], "default": "available",
			 "props": {"model_path": "valley/o0c_dropit.glb"}},
			{"id": "drop_weapon", "title": "Drop (Weapon)", "desc": "Weapon drop. Floats and rotates.",
			 "script": "res://scripts/3d/elements/drop_base.gd",
			 "states": ["available", "collected"], "default": "available",
			 "props": {"model_path": "valley/o0c_dropwe.glb"}},
			{"id": "drop_armor", "title": "Drop (Armor)", "desc": "Armor/protector drop. Floats and rotates.",
			 "script": "res://scripts/3d/elements/drop_base.gd",
			 "states": ["available", "collected"], "default": "available",
			 "props": {"model_path": "valley/o0c_droppr.glb"}},
			{"id": "drop_rare", "title": "Drop (Rare)", "desc": "Rare item drop. Floats and rotates.",
			 "script": "res://scripts/3d/elements/drop_base.gd",
			 "states": ["available", "collected"], "default": "available",
			 "props": {"model_path": "valley/o0c_dropra.glb"}},
		]
	},
	{
		"name": "Interactables",
		"elements": [
			{"id": "message_pack", "title": "Message Pack", "desc": "Press E to read a text message.",
			 "script": "res://scripts/3d/elements/message_pack.gd",
			 "states": ["available", "read"], "default": "available",
			 "props": {"message_text": "The ancient runes speak of a great calamity..."}},
		]
	},
	{
		"name": "Navigation",
		"elements": [
			{"id": "waypoint", "title": "Waypoint", "desc": "New area / origin area / previously visited.",
			 "script": "res://scripts/3d/elements/waypoint.gd",
			 "states": ["new", "unvisited", "visited"], "default": "new"},
			{"id": "start_warp", "title": "Start Warp", "desc": "Small stage entry/exit portal.",
			 "script": "res://scripts/3d/elements/start_warp.gd",
			 "states": ["active", "inactive"], "default": "active"},
			{"id": "area_warp", "title": "Area Warp", "desc": "Medium area transition portal.",
			 "script": "res://scripts/3d/elements/area_warp.gd",
			 "states": ["locked", "open"], "default": "locked"},
		]
	},
]

# Flattened item list
var _items: Array = []
var _cursor: int = 0
var _state_cursor: int = 0
var _current_element: GameElement = null
var _element_container: Node3D
var _camera: Camera3D
var _preview_viewport: SubViewport
var _left_label: RichTextLabel
var _right_top_label: RichTextLabel
var _right_bottom_label: RichTextLabel
var _font: Font
var _bold_font: Font
var _laser_materials: Array[StandardMaterial3D] = []
var _laser_scroll_axis: String = "y"
var _laser_scroll_speed: float = 0.5


func _ready() -> void:
	_font = load(FONT_PATH)
	_bold_font = load(BOLD_FONT_PATH)
	_build_item_list()
	_setup_ui()
	for i in range(_items.size()):
		if _items[i].type == "element":
			_cursor = i
			break
	_spawn_element()
	_refresh_ui()


func _build_item_list() -> void:
	for cat in CATEGORIES:
		_items.append({"type": "category", "name": cat.name})
		for el in cat.elements:
			_items.append({"type": "element", "data": el})


# ── 3D Preview (inside SubViewport) ──────────────────────────────────────────

func _setup_3d_viewport() -> SubViewportContainer:
	# SubViewportContainer holds the 3D preview, renders above UI panels
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(512, 512)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.own_world_3d = true
	_preview_viewport.transparent_bg = false
	svc.add_child(_preview_viewport)

	# Environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_preview_viewport.add_child(world_env)

	# Light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 0.8
	light.light_color = Color(1, 0.98, 0.95)
	light.shadow_enabled = true
	_preview_viewport.add_child(light)

	# Ground
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.18)
	ground.material_override = mat
	_preview_viewport.add_child(ground)

	# Camera (transform computed manually — look_at requires being in tree)
	_camera = Camera3D.new()
	_camera.current = true
	var cam_pos := Vector3(
		cos(CAMERA_ANGLE) * ORBIT_RADIUS,
		ORBIT_HEIGHT,
		sin(CAMERA_ANGLE) * ORBIT_RADIUS
	)
	var z_axis := (cam_pos - Vector3(0, ORBIT_LOOK_Y, 0)).normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	_camera.transform = Transform3D(Basis(x_axis, y_axis, z_axis), cam_pos)
	_preview_viewport.add_child(_camera)

	# Element container
	_element_container = Node3D.new()
	_element_container.name = "Elements"
	_preview_viewport.add_child(_element_container)

	return svc


# ── UI Setup ──────────────────────────────────────────────────────────────────

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 20)
	root.add_theme_constant_override("margin_right", 20)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	canvas.add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	root.add_child(vbox)

	# Title bar
	var title_panel := _make_panel(ThemeColors.HEADER_BAR)
	vbox.add_child(title_panel)
	var title := Label.new()
	title.text = "ELEMENT STORYBOOK"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ThemeColors.HEADER_TEXT)
	title_panel.add_child(title)

	# Two-column content area
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	# Left panel — element list
	var left_panel := _make_panel(Color(0.04, 0.06, 0.12, 0.92))
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(left_panel)
	_left_label = _make_rich_label()
	_left_label.scroll_active = true
	left_panel.add_child(_left_label)

	# Right panel — details + 3D preview
	var right_panel := _make_panel(Color(0.04, 0.06, 0.12, 0.92))
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 4)
	right_panel.add_child(right_vbox)

	# Top: title, description, state list
	_right_top_label = _make_rich_label()
	_right_top_label.fit_content = true
	right_vbox.add_child(_right_top_label)

	# Middle: 3D preview in SubViewport (renders above panel bg)
	var preview_frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.01, 0.02, 0.04)
	frame_style.border_color = ThemeColors.BORDER
	frame_style.set_border_width_all(1)
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(preview_frame)
	preview_frame.add_child(_setup_3d_viewport())

	# Bottom: model/script info + texture debug (scrollable)
	_right_bottom_label = _make_rich_label()
	_right_bottom_label.scroll_active = true
	_right_bottom_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_right_bottom_label)

	# Hint bar
	var hint_panel := _make_panel(ThemeColors.HINT_BAR)
	vbox.add_child(hint_panel)
	var hint := Label.new()
	hint.text = "[Up/Down] Select   [Left/Right] State   [Esc] Back"
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", ThemeColors.HINT_TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(hint)


func _make_panel(bg_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.add_theme_font_override("normal_font", _font)
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	label.add_theme_font_override("bold_font", _bold_font)
	label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	return label


# ── Frame Update ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	for mat in _laser_materials:
		if _laser_scroll_axis == "x":
			mat.uv1_offset.x += delta * _laser_scroll_speed
		else:
			mat.uv1_offset.y += delta * _laser_scroll_speed


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_UP:
			_move_cursor(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_move_cursor(1)
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_cycle_state(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_ENTER:
			_cycle_state(1)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			SceneManager.pop_scene()
			get_viewport().set_input_as_handled()


# ── Navigation ────────────────────────────────────────────────────────────────

func _move_cursor(dir: int) -> void:
	var count := _items.size()
	var next := _cursor
	for _i in range(count):
		next = (next + dir + count) % count
		if _items[next].type == "element":
			break

	if next != _cursor:
		_cursor = next
		_spawn_element()
		_refresh_ui()


func _cycle_state(dir: int) -> void:
	var item: Dictionary = _items[_cursor]
	if item.type != "element":
		return

	var states: Array = item.data.states
	if states.is_empty():
		return

	_state_cursor = (_state_cursor + dir + states.size()) % states.size()
	if _current_element:
		_current_element.set_state(states[_state_cursor])
	_refresh_ui()


# ── Element Spawning ──────────────────────────────────────────────────────────

func _spawn_element() -> void:
	if _current_element:
		_current_element.queue_free()
		_current_element = null
	_laser_materials.clear()

	var item: Dictionary = _items[_cursor]
	if item.type != "element":
		return

	var data: Dictionary = item.data
	var script_res = load(data.script)
	if not script_res:
		push_warning("ElementStorybook: Failed to load " + data.script)
		return

	var element = script_res.new()

	if data.has("props"):
		for key in data.props:
			element.set(key, data.props[key])

	if data.id in ["key", "drop_meseta", "drop_item", "drop_weapon", "drop_armor", "drop_rare"]:
		element.position.y = 0.5

	_element_container.add_child(element)
	_current_element = element

	# Load per-element laser scroll config
	if LASER_SCROLL_CONFIG.has(data.id):
		var cfg: Dictionary = LASER_SCROLL_CONFIG[data.id]
		_laser_scroll_axis = cfg.get("axis", "y")
		_laser_scroll_speed = cfg.get("speed", 0.5)
	else:
		_laser_scroll_axis = "y"
		_laser_scroll_speed = 0.5

	_fixup_materials(element, data.id)

	# Re-run element's material setup after storybook fixup replaced materials
	if element.has_method("_setup_laser_material"):
		element._setup_laser_material()
	if element.has_method("_setup_laser_materials"):
		element._setup_laser_materials()
	if element.has_method("_setup_warp_material"):
		element._setup_warp_material()
	if element.has_method("_setup_textures"):
		element._setup_textures()

	var default_state: String = data.default
	_state_cursor = 0
	var idx: int = data.states.find(default_state)
	if idx >= 0:
		_state_cursor = idx
	if element.element_state != default_state:
		element.set_state(default_state)


# ── Texture Fixup ─────────────────────────────────────────────────────────────

func _fixup_materials(element: GameElement, element_id: String) -> void:
	if not element.model:
		return

	var fixups: Array = []
	if TEXTURE_FIXUPS.has(element_id):
		fixups = TEXTURE_FIXUPS[element_id]

	_fixup_recursive(element.model, fixups)


func _fixup_recursive(node: Node, fixups: Array) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std_mat := mat as StandardMaterial3D

			var is_laser := false
			if std_mat.albedo_texture:
				for tex_id in LASER_TEXTURE_IDS:
					if tex_id in std_mat.albedo_texture.resource_path:
						is_laser = true
						break

			var dup := std_mat.duplicate() as StandardMaterial3D
			mesh_inst.set_surface_override_material(i, dup)

			if is_laser:
				_laser_materials.append(dup)
			else:
				_apply_fixups(dup, fixups)

	for child in node.get_children():
		_fixup_recursive(child, fixups)


func _apply_fixups(mat: StandardMaterial3D, fixups: Array) -> void:
	for fixup in fixups:
		if fixup.has("match"):
			if not mat.albedo_texture:
				continue
			if fixup["match"] not in mat.albedo_texture.resource_path:
				continue

		if fixup.has("scale"):
			mat.uv1_scale = fixup["scale"]
		if fixup.has("offset"):
			mat.uv1_offset = fixup["offset"]



# ── Texture Debug ─────────────────────────────────────────────────────────────

func _collect_texture_info(node: Node, depth: int = 0) -> String:
	var result := ""
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var surf_count := mesh_inst.get_surface_override_material_count()
		result += "[color=%s]%s[/color] (%d surfaces)\n" % [C_TEXT, node.name, surf_count]
		for i in range(surf_count):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				var tex_name := "(none)"
				if std.albedo_texture:
					tex_name = std.albedo_texture.resource_path.get_file()
				var scale_str := "%.1f,%.1f" % [std.uv1_scale.x, std.uv1_scale.y]
				var offset_str := "%.2f,%.2f" % [std.uv1_offset.x, std.uv1_offset.y]
				result += "  [%d] [color=%s]%s[/color]\n" % [i, C_SELECTED, tex_name]
				result += "      scale(%s) offset(%s)\n" % [scale_str, offset_str]
			else:
				var type_name := mat.get_class() if mat else "null"
				result += "  [%d] [color=%s]%s[/color]\n" % [i, C_MUTED, type_name]

	for child in node.get_children():
		result += _collect_texture_info(child, depth + 1)
	return result


# ── UI Refresh ────────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	_refresh_left()
	_refresh_right()


func _refresh_left() -> void:
	var bbcode := ""
	var cursor_line := 0
	var current_line := 0
	for i in range(_items.size()):
		var item: Dictionary = _items[i]
		if item.type == "category":
			if i > 0:
				bbcode += "\n"
				current_line += 1
			bbcode += "[b][color=%s]%s[/color][/b]\n" % [C_HEADER, item.name.to_upper()]
			current_line += 1
		else:
			if i == _cursor:
				cursor_line = current_line
			var title_text: String = item.data.title
			if i == _cursor:
				bbcode += "[color=%s]> %s[/color]\n" % [C_SELECTED, title_text]
			else:
				bbcode += "  [color=%s]%s[/color]\n" % [C_TEXT, title_text]
			current_line += 1

	_left_label.clear()
	_left_label.append_text(bbcode)
	_left_label.scroll_to_line(max(0, cursor_line - 3))


func _refresh_right() -> void:
	var item: Dictionary = _items[_cursor]
	if item.type != "element":
		_right_top_label.clear()
		_right_bottom_label.clear()
		return

	var data: Dictionary = item.data

	# Top: title, description, state list
	var top := ""
	top += "[b]%s[/b]\n" % data.title
	top += "[color=%s]\"%s\"[/color]\n\n" % [C_MUTED, data.desc]
	top += "[b]State:[/b]\n"
	for i in range(data.states.size()):
		var state_name: String = data.states[i]
		if i == _state_cursor:
			top += "[color=%s]> %s[/color]\n" % [C_SELECTED, state_name]
		else:
			top += "  [color=%s]%s[/color]\n" % [C_TEXT, state_name]

	_right_top_label.clear()
	_right_top_label.append_text(top)

	# Bottom: model/script info + texture debug
	var bottom := ""
	bottom += "[color=%s]Script: %s[/color]\n" % [C_MUTED, data.script.get_file()]
	if _current_element and not _current_element.model_path.is_empty():
		bottom += "[color=%s]Model: %s[/color]\n" % [C_MUTED, _current_element.model_path]

	# Texture debug: list all meshes and their materials/textures
	if _current_element and _current_element.model:
		bottom += "\n[b][color=%s]Textures:[/color][/b]\n" % C_HEADER
		bottom += _collect_texture_info(_current_element.model)

	_right_bottom_label.clear()
	_right_bottom_label.append_text(bottom)
