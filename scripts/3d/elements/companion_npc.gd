extends CharacterBody3D
## Companion NPC that follows the player through field exploration.
## Renders as a colored capsule with a name label and PSO-style speech bubble.
## Uses direct movement (no NavigationAgent — stages have no navmesh).

signal speech_started
signal speech_finished

const FOLLOW_SPEED: float = 6.0
const CATCHUP_SPEED: float = 9.0
const STOP_DISTANCE: float = 2.5
const CATCHUP_DISTANCE: float = 6.0
const TELEPORT_DISTANCE: float = 20.0

## Companion colors by ID
const COMPANION_COLORS: Dictionary = {
	"kai": Color(1.0, 0.9, 0.1),       # Yellow
	"dorn": Color(1.0, 0.6, 0.0),      # Orange
	"ren": Color(0.0, 0.9, 0.9),       # Cyan
	"elio": Color(0.2, 0.9, 0.2),      # Green
	"mira": Color(0.7, 0.3, 0.9),      # Purple
	"sarisa": Color(1.0, 0.5, 0.7),    # Pink
}
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0)  # White

## Viewport size for speech bubble
const BUBBLE_WIDTH := 400
const BUBBLE_HEIGHT := 180

@export var companion_id: String = ""

var _bubble_viewport: SubViewport
var _bubble_sprite: Sprite3D
var _bubble_text: Label
var _name_label: Label3D
var _player_ref: Node3D = null
var _speaking: bool = false


func _ready() -> void:
	_build_capsule()
	_build_name_label()
	_build_speech_bubble()

	# Don't block the player — collide with environment only
	collision_layer = 0
	collision_mask = 1

	# Physics collision shape
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	col_shape.shape = capsule
	col_shape.position.y = 0.7
	add_child(col_shape)


func _build_capsule() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "CapsuleMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COMPANION_COLORS.get(companion_id, DEFAULT_COLOR)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat

	add_child(mesh_inst)


func _build_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = companion_id.capitalize()
	_name_label.position.y = 1.6
	_name_label.pixel_size = 0.01
	_name_label.font_size = 20
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_name_label)


func _build_speech_bubble() -> void:
	# SubViewport renders 2D speech bubble → Sprite3D displays in 3D
	_bubble_viewport = SubViewport.new()
	_bubble_viewport.name = "BubbleViewport"
	_bubble_viewport.size = Vector2i(BUBBLE_WIDTH, BUBBLE_HEIGHT)
	_bubble_viewport.transparent_bg = true
	_bubble_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bubble_viewport)

	# Root control
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_viewport.add_child(root)

	var cx: float = BUBBLE_WIDTH * 0.5
	var top_y: float = BUBBLE_HEIGHT * 0.78  # Panel bottom edge

	# Tail border (behind everything — added first so it draws first)
	var tail_border := Polygon2D.new()
	tail_border.polygon = PackedVector2Array([
		Vector2(cx - 13, top_y - 1),
		Vector2(cx + 13, top_y - 1),
		Vector2(cx, top_y + 30),
	])
	tail_border.color = Color(0.3, 0.3, 0.3, 0.6)
	root.add_child(tail_border)

	# White rounded rectangle (the bubble body)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.05
	panel.anchor_right = 0.95
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.78
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 4
	panel.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.border_color = Color(0.3, 0.3, 0.3, 0.6)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	# Text label inside panel
	_bubble_text = Label.new()
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bubble_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_bubble_text.add_theme_font_size_override("font_size", 18)
	_bubble_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_bubble_text)

	# White tail triangle — pointing down from center-bottom of bubble
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(cx - 12, top_y),
		Vector2(cx + 12, top_y),
		Vector2(cx, top_y + 28),
	])
	tail.color = Color.WHITE
	root.add_child(tail)

	# Sprite3D billboard above the NPC
	_bubble_sprite = Sprite3D.new()
	_bubble_sprite.name = "BubbleSprite"
	_bubble_sprite.pixel_size = 0.006
	_bubble_sprite.position.y = 2.8
	_bubble_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble_sprite.no_depth_test = true
	_bubble_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_bubble_sprite.render_priority = 10
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

	# Assign viewport texture after one frame
	call_deferred("_assign_bubble_texture")


func _assign_bubble_texture() -> void:
	if _bubble_viewport and _bubble_sprite:
		_bubble_sprite.texture = _bubble_viewport.get_texture()


func _physics_process(delta: float) -> void:
	_process_follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _speaking:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_ENTER, KEY_SPACE, KEY_ESCAPE:
				_dismiss_speech()
				get_viewport().set_input_as_handled()


func _process_follow(delta: float) -> void:
	# Don't move while speaking
	if _speaking:
		return

	# Cache player reference
	if not is_instance_valid(_player_ref):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player_ref = players[0]

	var player_pos := _player_ref.global_position
	var to_player := player_pos - global_position
	to_player.y = 0
	var dist := to_player.length()

	# Teleport if too far away
	if dist > TELEPORT_DISTANCE:
		_teleport_behind_player()
		return

	# Match player Y directly (stages are flat)
	global_position.y = player_pos.y

	if dist > STOP_DISTANCE:
		var direction := to_player.normalized()
		var speed := CATCHUP_SPEED if dist > CATCHUP_DISTANCE else FOLLOW_SPEED
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		velocity.y = 0

		var target_angle := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 5.0 * delta)
	else:
		velocity.x = 0
		velocity.z = 0
		velocity.y = 0

	move_and_slide()


func _teleport_behind_player() -> void:
	if not is_instance_valid(_player_ref):
		return
	var player_rot: float = _player_ref.rotation.y
	if "player_rotation" in _player_ref:
		player_rot = _player_ref.player_rotation
	var behind := -Vector3(sin(player_rot), 0, cos(player_rot)) * 3.0
	global_position = _player_ref.global_position + behind
	global_position.y = _player_ref.global_position.y


func _dismiss_speech() -> void:
	_bubble_sprite.visible = false
	_name_label.visible = true
	_speaking = false
	speech_finished.emit()


## Show a PSO-style speech bubble above the companion's head.
func show_speech(text: String, _speaker: String = "", _duration: float = 4.0) -> void:
	print("[Companion] show_speech: text='%s'" % text.left(50))
	_bubble_text.text = text
	_bubble_sprite.visible = true
	_bubble_sprite.modulate.a = 1.0
	_speaking = true
	# Hide name label while speech is showing (bubble replaces it)
	_name_label.visible = false
	speech_started.emit()
