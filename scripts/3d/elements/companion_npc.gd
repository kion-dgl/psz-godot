extends CharacterBody3D
## Companion NPC that follows the player through field exploration.
## Renders as a colored capsule with a name label and PSO-style speech bubble.
## Uses direct movement (no NavigationAgent — stages have no navmesh).

signal speech_started
signal speech_finished

const FOLLOW_SPEED: float = 7.0
const CATCHUP_SPEED: float = 10.0
const STOP_DISTANCE: float = 1.8
const START_DISTANCE: float = 3.0  # Must exceed START to begin moving (hysteresis)
const CATCHUP_DISTANCE: float = 5.0
const TELEPORT_DISTANCE: float = 20.0

## Companion models — maps companion_id to { glb, texture } paths
const COMPANION_MODELS: Dictionary = {
	"kai": {"glb": "res://assets/npcs/kai/pc_a01_000.glb", "texture": "res://assets/npcs/kai/pc_a01_000.png"},
	"sarisa": {"glb": "res://assets/npcs/sarisa/pc_a00_000.glb", "texture": "res://assets/npcs/sarisa/pc_a00_000.png"},
	"dorn": {"glb": "res://assets/npcs/dorn/dorn.glb", "texture": "res://assets/npcs/dorn/dorn.png"},
	"dr_carlo": {"glb": "res://assets/npcs/dr_carlo/dr_carlo.glb", "texture": "res://assets/npcs/dr_carlo/dr_carlo.png"},
	"elio": {"glb": "res://assets/npcs/elio/elio.glb", "texture": "res://assets/npcs/elio/elio.png"},
	"fern": {"glb": "res://assets/npcs/fern/fern.glb", "texture": "res://assets/npcs/fern/fern.png"},
	"vash": {"glb": "res://assets/npcs/vash/vash.glb", "texture": "res://assets/npcs/vash/vash.png"},
	"ren": {"glb": "res://assets/npcs/ren/ren.glb", "texture": "res://assets/npcs/ren/ren.png"},
	"mira": {"glb": "res://assets/npcs/mira/mira.glb", "texture": "res://assets/npcs/mira/mira.png"},
}

## Fallback colors for NPCs without GLB models
const COMPANION_COLORS: Dictionary = {
	"kai": Color(1.0, 0.9, 0.1),
	"dorn": Color(1.0, 0.6, 0.0),
	"ren": Color(0.0, 0.9, 0.9),
	"elio": Color(0.2, 0.9, 0.2),
	"mira": Color(0.7, 0.3, 0.9),
	"sarisa": Color(1.0, 0.5, 0.7),
}
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0)

## Gender detection for animation prefix (female classes)
const FEMALE_CLASSES := ["humarl", "ramarl", "fomarl", "hunewearl", "fonewearl", "hucaseal", "racaseal"]

## Companion class IDs for animation selection
const COMPANION_CLASSES: Dictionary = {
	"kai": "humar", "sarisa": "hunewearl", "dorn": "hucast",
	"dr_carlo": "fomar", "elio": "racaseal", "fern": "humarl",
	"vash": "ramar", "ren": "humar", "mira": "fomarl",
}

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
var _speech_timer: float = 0.0
var _anim_player: AnimationPlayer
var _current_anim: String = ""
var _is_female: bool = false
var _anim_hold_timer: float = 0.0
const ANIM_HOLD_TIME: float = 0.3
var _was_moving: bool = false  # Track delayed state transitions
var _resume_blend: float = 0.0  # Blend from frozen pos to trail pos on resume
var _frozen_pos: Vector3 = Vector3.ZERO  # Position when companion froze
const RESUME_BLEND_SPEED: float = 3.0  # Seconds to fully blend back to trail
var _dismissed: bool = false  # When true, stop following and idle in place

## Trail replay — record every physics frame, interpolate on playback
var _trail: Array = []  # [{pos: Vector3, rot: float, state: int, time: float}]
const TRAIL_DELAY: float = 0.5  # Seconds behind the player
const TRAIL_MAX_ENTRIES: int = 150  # ~2.5s at 60fps


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
	# Try to load a real model first
	var entry: Variant = COMPANION_MODELS.get(companion_id, null)
	if entry != null:
		var glb_path: String = entry["glb"]
		var tex_path: String = entry["texture"]
		if ResourceLoader.exists(glb_path):
			var packed := load(glb_path) as PackedScene
			if packed:
				var npc_model := packed.instantiate()
				npc_model.name = "CompanionModel"
				add_child(npc_model)
				if ResourceLoader.exists(tex_path):
					var texture := load(tex_path) as Texture2D
					if texture:
						_apply_texture(npc_model, texture)
				_setup_companion_anims(npc_model)
				return

	# Fallback: colored capsule
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


func _apply_texture(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_texture = texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_apply_texture(child, texture)


func _setup_companion_anims(npc_model: Node) -> void:
	## Load walk/run/idle animations (saber_m.glb for male, saver_w.glb for female)
	var class_id: String = COMPANION_CLASSES.get(companion_id, "humar")
	_is_female = class_id in FEMALE_CLASSES
	var anim_glb: String = "res://assets/player/animations/saver_w.glb" if _is_female else "res://assets/player/animations/saber_m.glb"
	if not ResourceLoader.exists(anim_glb):
		return

	var skel: Skeleton3D = _find_typed(npc_model, "Skeleton3D") as Skeleton3D
	if not skel:
		return

	var anim_packed := load(anim_glb) as PackedScene
	if not anim_packed:
		return
	var anim_scene := anim_packed.instantiate()
	var source_player: AnimationPlayer = _find_typed(anim_scene, "AnimationPlayer") as AnimationPlayer
	if not source_player:
		anim_scene.queue_free()
		return

	_anim_player = AnimationPlayer.new()
	_anim_player.name = "CompanionAnimPlayer"
	skel.get_parent().add_child(_anim_player)

	var prefix: String = "pwsa" if _is_female else "pmsa"
	# Map companion anim keys to source anim names, with fallbacks
	# Male GLB lacks _run_pso and _walk — fall back to _run for both
	var needed := {
		"wait": [prefix + "_wait"],
		"run": [prefix + "_run_pso", prefix + "_run"],
		"walk": [prefix + "_walk", prefix + "_run"],
	}

	var lib := AnimationLibrary.new()
	for key in needed:
		var candidates: Array = needed[key]
		for anim_name: String in candidates:
			if source_player.has_animation(anim_name):
				var anim := source_player.get_animation(anim_name).duplicate() as Animation
				anim.loop_mode = Animation.LOOP_LINEAR
				# Remap skeleton tracks
				for i in range(anim.get_track_count()):
					var track_path := String(anim.track_get_path(i))
					if "Skeleton3D" in track_path:
						var skel_idx := track_path.find("Skeleton3D")
						var prop_part := track_path.substr(skel_idx + 10)
						anim.track_set_path(i, NodePath(skel.name + prop_part))
				lib.add_animation(key, anim)
				break

	_anim_player.add_animation_library("", lib)
	_play_companion_anim("wait")
	anim_scene.queue_free()
	print("[Companion] Loaded anims for %s (female=%s)" % [companion_id, _is_female])


func _play_companion_anim(anim_name: String) -> void:
	if not _anim_player or _current_anim == anim_name:
		return
	# Don't switch animations until hold timer expires
	if _anim_hold_timer > 0.0:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name
		_anim_hold_timer = ANIM_HOLD_TIME


func _find_typed(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed(child, type_name)
		if found:
			return found
	return null


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
	_process_speech_timer(delta)
	_process_follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _speaking:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_dismiss_speech()


func _process_speech_timer(delta: float) -> void:
	if not _speaking or _speech_timer <= 0:
		return
	_speech_timer -= delta
	# Fade out during last 0.5s
	if _speech_timer < 0.5:
		_bubble_sprite.modulate.a = _speech_timer / 0.5
	if _speech_timer <= 0:
		_dismiss_speech()


func dismiss() -> void:
	_dismissed = true
	_play_companion_anim("wait")
	print("[Companion] %s dismissed — stopped following" % companion_id)


func _process_follow(_delta: float) -> void:
	if _dismissed:
		return
	# Cache player reference
	if not is_instance_valid(_player_ref):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player_ref = players[0]

	# Tick animation hold timer
	_anim_hold_timer = maxf(_anim_hold_timer - _delta, 0.0)

	# Record player state every physics frame
	var ps: int = 0
	if "current_state" in _player_ref:
		ps = _player_ref.current_state
	var player_rot: float = _player_ref.player_rotation if "player_rotation" in _player_ref else _player_ref.rotation.y
	var now: float = Time.get_ticks_msec() / 1000.0
	_trail.append({
		"pos": _player_ref.global_position,
		"rot": player_rot,
		"state": ps,
		"time": now,
	})

	# Prune oldest entries
	while _trail.size() > TRAIL_MAX_ENTRIES:
		_trail.remove_at(0)

	# Teleport if too far
	var dist_to_player := global_position.distance_to(_player_ref.global_position)
	if dist_to_player > TELEPORT_DISTANCE:
		_teleport_behind_player()
		_trail.clear()
		_play_companion_anim("wait")
		return

	# Find the two trail entries bracketing target_time and interpolate
	var target_time: float = now - TRAIL_DELAY
	var entry_a: Dictionary = {}
	var entry_b: Dictionary = {}
	for i in range(_trail.size() - 1, 0, -1):
		if _trail[i - 1]["time"] <= target_time and _trail[i]["time"] >= target_time:
			entry_a = _trail[i - 1]
			entry_b = _trail[i]
			break

	if entry_a.is_empty():
		# Not enough trail history yet — stay put
		_play_companion_anim("wait")
		return

	# Interpolate between the two bracketing entries
	var span: float = entry_b["time"] - entry_a["time"]
	var t: float = 0.0
	if span > 0.001:
		t = clampf((target_time - entry_a["time"]) / span, 0.0, 1.0)

	var interp_pos: Vector3 = entry_a["pos"].lerp(entry_b["pos"], t)
	var interp_rot: float = lerp_angle(entry_a["rot"], entry_b["rot"], t)
	var delayed_state: int = entry_a["state"]

	# Mirror the delayed player animation state
	# IDLE=0, WALKING=1, RUNNING=2, SPRINTING=3
	var is_moving: bool = delayed_state >= 1

	if is_moving:
		# Player was moving — follow the interpolated trail
		# But cap position so we never get closer than 1.5 units to the player
		var candidate_pos := Vector3(interp_pos.x, _player_ref.global_position.y, interp_pos.z)
		var to_player := _player_ref.global_position - candidate_pos
		to_player.y = 0
		if to_player.length() < 1.5:
			var away_dir := -to_player.normalized() if to_player.length() > 0.01 else Vector3(-sin(player_rot), 0, -cos(player_rot))
			candidate_pos = _player_ref.global_position + away_dir * 1.5
			candidate_pos.y = _player_ref.global_position.y

		# Smooth blend from frozen position when resuming movement
		if not _was_moving:
			_frozen_pos = global_position
			_resume_blend = 0.0
		if _resume_blend < 1.0:
			_resume_blend = minf(_resume_blend + RESUME_BLEND_SPEED * _delta, 1.0)
			candidate_pos = _frozen_pos.lerp(candidate_pos, _resume_blend)

		global_position = candidate_pos
		rotation.y = interp_rot
		_was_moving = true
		if delayed_state == 1:
			_play_companion_anim("walk")
		else:
			_play_companion_anim("run")
	else:
		# Player was idle — freeze in place, face player's direction
		global_position.y = _player_ref.global_position.y
		rotation.y = lerp_angle(rotation.y, player_rot, 5.0 * _delta)
		_was_moving = false
		_play_companion_anim("wait")


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
## Auto-dismisses after duration seconds.
func show_speech(text: String, _speaker: String = "", duration: float = 4.0) -> void:
	print("[Companion] show_speech: text='%s' duration=%.1f" % [text.left(50), duration])
	SfxManager.play("res://assets/sfx/ui/dialog_open.wav")
	_bubble_text.text = text
	_bubble_sprite.visible = true
	_bubble_sprite.modulate.a = 1.0
	_speaking = true
	_speech_timer = duration
	_name_label.visible = false
	speech_started.emit()
	# Log to action log
	var speaker_name: String = _speaker if not _speaker.is_empty() else companion_id.capitalize()
	_log_to_hud(speaker_name, text)


func _log_to_hud(speaker: String, text: String) -> void:
	var hud := _find_field_hud()
	if hud and hud.has_method("log_speech"):
		hud.log_speech(speaker, text)


func _find_field_hud() -> Node:
	var node := get_parent()
	while node:
		for child in node.get_children():
			if child is CanvasLayer and child.name == "FieldHud":
				return child
		node = node.get_parent()
	return null
