extends GameElement
class_name MessagePack
## Interactable message pack — press E to read a text message.
## States: available, read

signal message_read(text: String)

## The message text displayed when interacted with
@export var message_text: String = ""

## Scrolling texture
const SCROLL_TEXTURE_NAME := "o0c_1_mspack"
const SCROLL_SPEED: float = 0.45
var _prompt_label: Label3D
var _player_nearby: bool = false
var _popup: CanvasLayer
var _scroll_material: StandardMaterial3D = null


func _init() -> void:
	model_path = "valley/o0c_mspack.glb"
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 2.0, 2.0)
	element_state = "available"


func _ready() -> void:
	super._ready()
	_setup_scroll_material()
	_setup_prompt()


func _setup_scroll_material() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and SCROLL_TEXTURE_NAME in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_scroll_material = dup
	)


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Read"
	_prompt_label.font_size = 28
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 2.0, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(0.8, 0.4, 1.0)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _update_animation(delta: float) -> void:
	if _scroll_material:
		_scroll_material.uv1_offset.y += SCROLL_SPEED * delta


func _apply_state() -> void:
	match element_state:
		"available":
			set_element_visible(true)
			set_process(true)
		"read":
			# Still visible but stopped spinning
			set_element_visible(true)
			set_process(true)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = true
		if _prompt_label:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = false
		if _prompt_label:
			_prompt_label.visible = false


func _on_interact(_player: Node3D) -> void:
	if _popup:
		return  # Already showing
	_show_popup()
	set_state("read")
	message_read.emit(message_text)
	# Consume the input so the same E key doesn't immediately close the popup
	get_viewport().set_input_as_handled()


func _show_popup() -> void:
	_popup = CanvasLayer.new()
	_popup.layer = 120
	_popup.name = "MessagePopup"

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(bg)

	# Center panel
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.3, 0.9, 0.8)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 24.0
	style.content_margin_top = 20.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.25
	panel.anchor_bottom = 0.75
	_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Message"
	var title_settings := LabelSettings.new()
	title_settings.font_color = Color(0.8, 0.5, 1.0)
	title_settings.font_size = 20
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Message body
	var body := Label.new()
	body.text = message_text if not message_text.is_empty() else "(empty message)"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body_settings := LabelSettings.new()
	body_settings.font_color = Color(1.0, 1.0, 1.0)
	body_settings.font_size = 16
	body.label_settings = body_settings
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# Close hint
	var close_hint := Label.new()
	close_hint.text = "[E] or [ESC] Close"
	var hint_settings := LabelSettings.new()
	hint_settings.font_color = Color(0.5, 0.5, 0.5)
	hint_settings.font_size = 13
	close_hint.label_settings = hint_settings
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(close_hint)

	get_tree().root.add_child(_popup)


func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null


func _unhandled_input(event: InputEvent) -> void:
	if _popup:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
				_close_popup()
				get_viewport().set_input_as_handled()
	elif _player_nearby and event.is_action_pressed("interact"):
		_on_interact(null)
		get_viewport().set_input_as_handled()
