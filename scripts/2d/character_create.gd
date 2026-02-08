extends Control
## Character creation screen — class selection, appearance, name entry, confirmation.

enum Step { CLASS_SELECT, APPEARANCE, NAME_ENTRY, CONFIRM }

var _step: int = Step.CLASS_SELECT
var _slot: int = 0
var _class_list: Array = []
var _selected_class_index: int = 0
var _selected_class_id: String = ""
var _char_name: String = ""

# Appearance selection state
var _appearance_row: int = 0  # 0=head, 1=body color, 2=hair color, 3=skin tone
var _appearance := {
	"variation_index": 0,
	"body_color_index": 0,
	"hair_color_index": 0,
	"skin_tone_index": 0,
}

# 3D preview state
var _preview_model: Node3D = null
var _preview_pivot: Node3D = null
var _preview_viewport: SubViewport = null
var _preview_active := false

@onready var title_label: Label = $VBox/TitleLabel
@onready var content_panel: PanelContainer = $VBox/HBox/ContentPanel
@onready var info_panel: PanelContainer = $VBox/HBox/InfoPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	_slot = SceneManager.get_transition_data().get("slot", 0)
	title_label.text = "CREATE CHARACTER (Slot %d)" % (_slot + 1)
	_load_classes()
	_show_class_select()


func _load_classes() -> void:
	_class_list = ClassRegistry.get_all_classes()
	# Sort by type (Hunter, Ranger, Force), then gender (Male, Female), then race
	var type_order := {"Hunter": 0, "Ranger": 1, "Force": 2}
	var gender_order := {"Male": 0, "Female": 1}
	var race_order := {"Human": 0, "Newman": 1, "Cast": 2}
	_class_list.sort_custom(func(a, b):
		var ta: int = type_order.get(a.type, 9)
		var tb: int = type_order.get(b.type, 9)
		if ta != tb: return ta < tb
		var ga: int = gender_order.get(a.gender, 9)
		var gb: int = gender_order.get(b.gender, 9)
		if ga != gb: return ga < gb
		var ra: int = race_order.get(a.race, 9)
		var rb: int = race_order.get(b.race, 9)
		return ra < rb
	)


func _unhandled_input(event: InputEvent) -> void:
	match _step:
		Step.CLASS_SELECT:
			_handle_class_select_input(event)
		Step.APPEARANCE:
			_handle_appearance_input(event)
		Step.NAME_ENTRY:
			_handle_name_entry_input(event)
		Step.CONFIRM:
			_handle_confirm_input(event)


func _handle_class_select_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_class_index = wrapi(_selected_class_index - 1, 0, _class_list.size())
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_class_index = wrapi(_selected_class_index + 1, 0, _class_list.size())
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_selected_class_id = _class_list[_selected_class_index].id
		_appearance = {"variation_index": 0, "body_color_index": 0, "hair_color_index": 0, "skin_tone_index": 0}
		_appearance_row = 0
		_show_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")
		get_viewport().set_input_as_handled()


func _handle_appearance_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_appearance_row = wrapi(_appearance_row - 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_appearance_row = wrapi(_appearance_row + 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and not Input.is_action_pressed("dodge"):
		_cycle_appearance_value(-1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not Input.is_action_pressed("dodge"):
		_cycle_appearance_value(1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not Input.is_action_pressed("dodge"):
		_teardown_preview()
		_show_name_entry()
		_update_class_info()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_teardown_preview()
		_show_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge"):
		# Consume Space press so it doesn't trigger ui_accept
		get_viewport().set_input_as_handled()


func _cycle_appearance_value(direction: int) -> void:
	match _appearance_row:
		0:  # Head type
			_appearance["variation_index"] = wrapi(
				int(_appearance["variation_index"]) + direction, 0, PlayerConfig.HEAD_VARIATIONS)
		1:  # Body color
			_appearance["body_color_index"] = wrapi(
				int(_appearance["body_color_index"]) + direction, 0, PlayerConfig.BODY_COLORS.size())
		2:  # Hair color
			_appearance["hair_color_index"] = wrapi(
				int(_appearance["hair_color_index"]) + direction, 0, PlayerConfig.HAIR_COLORS.size())
		3:  # Skin tone
			_appearance["skin_tone_index"] = wrapi(
				int(_appearance["skin_tone_index"]) + direction, 0, PlayerConfig.SKIN_TONES.size())


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_create_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_show_name_entry()
		get_viewport().set_input_as_handled()


func _show_class_select() -> void:
	_step = Step.CLASS_SELECT
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Back"
	_update_class_select()


func _update_class_select() -> void:
	# Content panel: class list
	for child in content_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var last_type := ""
	for i in range(_class_list.size()):
		var cls = _class_list[i]
		# Add type header when group changes
		if cls.type != last_type:
			if not last_type.is_empty():
				var spacer := Label.new()
				spacer.text = ""
				vbox.add_child(spacer)
			var type_header := Label.new()
			type_header.text = cls.type
			type_header.add_theme_color_override("font_color", ThemeColors.HEADER)
			vbox.add_child(type_header)
			last_type = cls.type
		var label := Label.new()
		if i == _selected_class_index:
			label.text = "> %-12s %s %s" % [cls.name, cls.race, cls.gender]
			label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		else:
			label.text = "  %-12s %s %s" % [cls.name, cls.race, cls.gender]
		vbox.add_child(label)

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	# Info panel: selected class details
	_update_class_info()


func _update_class_info() -> void:
	for child in info_panel.get_children():
		child.queue_free()

	if _class_list.is_empty():
		return

	var cls = _class_list[_selected_class_index]
	var stats: Dictionary = cls.get_stats_at_level(1)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = cls.name
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = "%s %s %s" % [cls.race, cls.gender, cls.type]
	desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(desc_label)

	var sep := Label.new()
	sep.text = "────────────────────"
	sep.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(sep)

	# Stats at level 1
	for stat_name in ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]:
		var stat_label := Label.new()
		var display_name: String = stat_name.to_upper().substr(0, 3) if stat_name.length() > 3 else stat_name.to_upper()
		if stat_name == "technique":
			display_name = "TEC"
		elif stat_name == "accuracy":
			display_name = "ACC"
		elif stat_name == "evasion":
			display_name = "EVA"
		elif stat_name == "defense":
			display_name = "DEF"
		elif stat_name == "attack":
			display_name = "ATK"
		stat_label.text = "  %-4s %d" % [display_name, stats.get(stat_name, 0)]
		vbox.add_child(stat_label)

	# Bonuses
	if not cls.bonuses.is_empty():
		var bonus_sep := Label.new()
		bonus_sep.text = ""
		vbox.add_child(bonus_sep)
		var bonus_header := Label.new()
		bonus_header.text = "Bonuses:"
		bonus_header.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(bonus_header)
		for bonus in cls.bonuses:
			var b_label := Label.new()
			b_label.text = "  • " + bonus
			b_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b_label.custom_minimum_size = Vector2(300, 0)
			vbox.add_child(b_label)

	info_panel.add_child(vbox)


# ── 3D Preview ───────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _preview_active and _preview_pivot:
		# Space + Left/Right to rotate the preview model
		if Input.is_action_pressed("dodge"):  # Space bar
			if Input.is_action_pressed("ui_left"):
				_preview_pivot.rotate_y(delta * 3.0)
			elif Input.is_action_pressed("ui_right"):
				_preview_pivot.rotate_y(-delta * 3.0)


func _build_preview_viewport() -> SubViewportContainer:
	# SubViewportContainer fills the info panel
	var container := SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(400, 500)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_preview_viewport)

	# Camera looking at model
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.15, 2.2)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 30
	_preview_viewport.add_child(camera)

	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.2
	_preview_viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.4
	_preview_viewport.add_child(fill)

	# World environment for ambient
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.8
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.14)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_preview_viewport.add_child(world_env)

	# Pivot node for rotation
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "PreviewPivot"
	_preview_viewport.add_child(_preview_pivot)

	return container


func _update_preview_model() -> void:
	if not _preview_pivot:
		return

	# Remove old model
	if _preview_model:
		_preview_model.get_parent().remove_child(_preview_model)
		_preview_model.free()
		_preview_model = null

	var vi: int = int(_appearance["variation_index"])
	var model_path: String = PlayerConfig.get_model_path(_selected_class_id, vi)

	if not ResourceLoader.exists(model_path):
		return

	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		return

	_preview_model = packed.instantiate() as Node3D
	_preview_model.scale = Vector3(0.6, 0.6, 0.6)
	_preview_model.position.y = -0.45
	_preview_pivot.add_child(_preview_model)

	# Apply texture
	var hair: int = int(_appearance["hair_color_index"])
	var skin: int = int(_appearance["skin_tone_index"])
	var body: int = int(_appearance["body_color_index"])
	var tex_path: String = PlayerConfig.get_texture_path(_selected_class_id, vi, hair, skin, body)

	if ResourceLoader.exists(tex_path):
		var texture := load(tex_path) as Texture2D
		if texture:
			_apply_texture_recursive(_preview_model, texture)


func _apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface_idx in range(mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(surface_idx)
				if mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
				elif mat == null:
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
	for child in node.get_children():
		_apply_texture_recursive(child, texture)


func _teardown_preview() -> void:
	_preview_active = false
	_preview_model = null
	_preview_pivot = null
	_preview_viewport = null


# ── Appearance Step ──────────────────────────────────────────────

func _show_appearance() -> void:
	_step = Step.APPEARANCE
	hint_label.text = "[↑/↓] Row  [←/→] Change  [SPACE+←/→] Rotate  [ENTER] Next  [ESC] Back"

	# Build the 3D preview in the info panel
	for child in info_panel.get_children():
		child.queue_free()
	var viewport_container := _build_preview_viewport()
	info_panel.add_child(viewport_container)
	_preview_active = true

	_update_appearance()
	_update_preview_model()


func _update_appearance() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "\nCustomize Appearance"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var spacer := Label.new()
	spacer.text = ""
	vbox.add_child(spacer)

	# Row data: [label, current_value_text]
	var rows := [
		["Head Type", "Type %d" % (int(_appearance["variation_index"]) + 1)],
		["Body Color", PlayerConfig.BODY_COLORS[int(_appearance["body_color_index"])]],
		["Hair Color", PlayerConfig.HAIR_COLORS[int(_appearance["hair_color_index"])]],
		["Skin Tone", PlayerConfig.SKIN_TONES[int(_appearance["skin_tone_index"])]],
	]

	for i in range(rows.size()):
		var row_label := Label.new()
		var is_selected := (i == _appearance_row)
		if is_selected:
			row_label.text = "  %-14s < %s >" % [rows[i][0] + ":", rows[i][1]]
			row_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		else:
			row_label.text = "  %-14s   %s  " % [rows[i][0] + ":", rows[i][1]]
		vbox.add_child(row_label)

	# Show variation ID
	var preview_spacer := Label.new()
	preview_spacer.text = ""
	vbox.add_child(preview_spacer)
	var preview := Label.new()
	var variation: String = PlayerConfig.get_variation(_selected_class_id, int(_appearance["variation_index"]))
	preview.text = "  Model: %s" % variation
	preview.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(preview)

	content_panel.add_child(vbox)


# ── Name Entry ───────────────────────────────────────────────────

func _handle_name_entry_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_appearance()
		get_viewport().set_input_as_handled()


func _show_name_entry() -> void:
	_step = Step.NAME_ENTRY
	hint_label.text = "[ENTER] Confirm  [ESC] Back to Appearance"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var prompt := Label.new()
	prompt.text = "\nEnter character name:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)

	var line_edit := LineEdit.new()
	line_edit.max_length = 16
	line_edit.text = _char_name
	line_edit.placeholder_text = "Name..."
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_edit.custom_minimum_size = Vector2(300, 40)
	line_edit.text_submitted.connect(_on_name_submitted)
	line_edit.gui_input.connect(_on_name_gui_input)
	vbox.add_child(line_edit)

	content_panel.add_child(vbox)

	# Focus the line edit
	await get_tree().process_frame
	line_edit.grab_focus()


func _on_name_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_appearance()
		get_viewport().set_input_as_handled()


func _on_name_submitted(text: String) -> void:
	_char_name = text.strip_edges()
	if _char_name.is_empty():
		return
	_show_confirm()


func _show_confirm() -> void:
	_step = Step.CONFIRM
	var cls = _class_list[_selected_class_index]
	hint_label.text = "[ENTER] Create Character  [ESC] Back to Name"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var header := Label.new()
	header.text = "\nConfirm Character"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "\n  Name:  %s" % _char_name
	name_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(name_label)

	var class_label := Label.new()
	class_label.text = "  Class: %s" % cls.name
	vbox.add_child(class_label)

	var type_label := Label.new()
	type_label.text = "  Type:  %s %s %s" % [cls.race, cls.gender, cls.type]
	type_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(type_label)

	# Appearance summary
	var appear_label := Label.new()
	var variation: String = PlayerConfig.get_variation(_selected_class_id, int(_appearance["variation_index"]))
	appear_label.text = "  Look:  %s  %s / %s / %s" % [
		variation,
		PlayerConfig.BODY_COLORS[int(_appearance["body_color_index"])],
		PlayerConfig.HAIR_COLORS[int(_appearance["hair_color_index"])],
		PlayerConfig.SKIN_TONES[int(_appearance["skin_tone_index"])],
	]
	appear_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(appear_label)

	content_panel.add_child(vbox)


func _create_character() -> void:
	var character: Dictionary = CharacterManager.create_character(
		_slot, _selected_class_id, _char_name, _appearance)
	if character.is_empty():
		push_warning("[CharCreate] Failed to create character")
		return
	CharacterManager.set_active_slot(_slot)
	SaveManager.save_game()
	SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
