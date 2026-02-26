extends CharacterBody3D
class_name CompanionNpc
## Companion NPC that follows the player through field exploration.
## Renders as a colored capsule with a name label and speech bubble.
## Uses direct movement (no NavigationAgent — stages have no navmesh).

signal speech_started
signal speech_finished

const GRAVITY: float = 20.0
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

@export var companion_id: String = ""

var _bubble_root: Node3D          # Billboard container for bubble
var _bubble_viewport: SubViewport
var _bubble_sprite: Sprite3D
var _bubble_panel: PanelContainer
var _bubble_speaker: Label
var _bubble_text: RichTextLabel
var _name_label: Label3D
var _speech_timer: float = 0.0
var _speech_duration: float = 0.0
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
	# SubViewport renders 2D UI → Sprite3D displays it in 3D as a billboard
	_bubble_viewport = SubViewport.new()
	_bubble_viewport.name = "BubbleViewport"
	_bubble_viewport.size = Vector2i(480, 200)
	_bubble_viewport.transparent_bg = true
	_bubble_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bubble_viewport)

	# Build the 2D panel inside the viewport
	var root_control := Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_viewport.add_child(root_control)

	_bubble_panel = PanelContainer.new()
	_bubble_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_panel.offset_left = 8
	_bubble_panel.offset_right = -8
	_bubble_panel.offset_top = 8
	_bubble_panel.offset_bottom = -24  # Leave room for tail

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.12, 0.92)
	style.border_color = Color(0.3, 0.5, 0.8, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	_bubble_panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(_bubble_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_bubble_panel.add_child(vbox)

	# Speaker name
	_bubble_speaker = Label.new()
	_bubble_speaker.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	_bubble_speaker.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_bubble_speaker)

	# Dialog text
	_bubble_text = RichTextLabel.new()
	_bubble_text.bbcode_enabled = true
	_bubble_text.fit_content = true
	_bubble_text.scroll_active = false
	_bubble_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bubble_text.add_theme_color_override("default_color", Color.WHITE)
	_bubble_text.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(_bubble_text)

	# Tail triangle (drawn as a small polygon below the panel)
	var tail := _create_tail_polygon()
	root_control.add_child(tail)

	# Sprite3D that shows the viewport texture
	_bubble_sprite = Sprite3D.new()
	_bubble_sprite.name = "BubbleSprite"
	_bubble_sprite.pixel_size = 0.005
	_bubble_sprite.position.y = 2.6
	_bubble_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble_sprite.no_depth_test = true
	_bubble_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_bubble_sprite.render_priority = 10
	_bubble_sprite.transparency = 0.0
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

	# Assign viewport texture after one frame (needs to initialize)
	_bubble_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	call_deferred("_assign_bubble_texture")


func _create_tail_polygon() -> Polygon2D:
	var tail := Polygon2D.new()
	# Small downward-pointing triangle centered at bottom of panel
	var cx: float = 240.0  # Center of viewport width
	var top_y: float = 176.0  # Just at panel bottom edge
	tail.polygon = PackedVector2Array([
		Vector2(cx - 10, top_y),
		Vector2(cx + 10, top_y),
		Vector2(cx, top_y + 16),
	])
	tail.color = Color(0.05, 0.05, 0.12, 0.92)
	return tail


func _assign_bubble_texture() -> void:
	if _bubble_viewport and _bubble_sprite:
		_bubble_sprite.texture = _bubble_viewport.get_texture()


func _physics_process(delta: float) -> void:
	_process_speech(delta)
	_process_follow(delta)


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
	var my_pos := global_position
	var to_player := player_pos - my_pos
	to_player.y = 0
	var dist := to_player.length()

	# Teleport if too far away
	if dist > TELEPORT_DISTANCE:
		_teleport_behind_player()
		return

	# Match player Y directly (no navmesh, stages are mostly flat)
	global_position.y = player_pos.y

	if dist > STOP_DISTANCE:
		var direction := to_player.normalized()
		var speed := CATCHUP_SPEED if dist > CATCHUP_DISTANCE else FOLLOW_SPEED
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		velocity.y = 0

		# Smooth rotation toward movement direction
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


func _process_speech(delta: float) -> void:
	if _speech_timer <= 0:
		return

	_speech_timer -= delta

	# Fade out during last 0.5s
	if _speech_timer < 0.5:
		_bubble_sprite.opacity = _speech_timer / 0.5
	else:
		_bubble_sprite.opacity = 1.0

	if _speech_timer <= 0:
		_bubble_sprite.visible = false
		_speaking = false
		speech_finished.emit()


## Show a speech bubble above the companion's head.
func show_speech(text: String, speaker: String = "", duration: float = 4.0) -> void:
	print("[Companion] show_speech: speaker='%s' text='%s' bubble_sprite=%s" % [speaker, text.left(40), _bubble_sprite != null])
	_bubble_speaker.text = speaker if not speaker.is_empty() else companion_id.capitalize()
	_bubble_text.text = text
	_bubble_sprite.visible = true
	_bubble_sprite.opacity = 1.0
	_speech_timer = duration
	_speech_duration = duration
	_speaking = true
	speech_started.emit()
