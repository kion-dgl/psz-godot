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

## Weapon-type → animation pack + name prefix, keyed by WeaponData.WeaponType,
## the same packs the player uses (player.gd WEAPON_ANIM_DATA). The companion's
## type comes from CompanionCombat.weapon_type_for(). wait + atk1 load from the
## equipped type's pack; walk + run always load from the SABER entry (index 0),
## the shared PSO-retargeted locomotion — see _setup_companion_anims. Only the
## types companions carry are listed; anything else falls back to SABER.
const WEAPON_ANIM: Dictionary = {
	0: {"glb_m": "res://assets/player/animations/saber_m.glb", "glb_w": "res://assets/player/animations/saver_w.glb", "prefix_m": "pmsa", "prefix_w": "pwsa"},    # SABER
	1: {"glb_m": "res://assets/player/animations/sword_m.glb", "glb_w": "res://assets/player/animations/sword_w.glb", "prefix_m": "pmsw", "prefix_w": "pwsw"},    # SWORD
	2: {"glb_m": "res://assets/player/animations/dagger_m.glb", "glb_w": "res://assets/player/animations/dagger_w.glb", "prefix_m": "pmda", "prefix_w": "pwda"},  # DAGGERS
	7: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_m": "pmgb", "prefix_w": "pwgbs"},  # GUN_BLADE
}

## Per-companion held weapon model, attached to the right-hand bone (mirrors the
## player's _attach_weapon_to_bone). psz-native models render at scale 1.0 (no
## PSO down-scale). Kai carries the Axeon gunblade (wgbr02_1_o).
const COMPANION_WEAPONS: Dictionary = {
	"kai": {
		"glb": "res://assets/weapons/wgbr02/wgbr02/wgbr02_1_o/wgbr02_1_o.glb",
		"texture": "res://assets/weapons/wgbr02/wgbr02/wgbr02_1_o/wgbr02_1_o.png",
		"scale": 1.0,
	},
}

## Right-hand weapon bone + idle hold pose (player.gd WEAPON_BONE_NAME /
## WEAPON_HOLD_DEFAULT — gunblade has no per-type override, so default holds).
const WEAPON_BONE_NAME: String = "070_RArm02"
const WEAPON_HOLD_POS: Vector3 = Vector3(0.31, 0, 0)
const WEAPON_HOLD_ROT: Vector3 = Vector3(0, 90, 0)

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

## Locomotion clip = f(movement INTENT, own measured planar speed). The FSM sets
## _move_intent each frame (steering states true, frozen/rooted false); the clip
## is resolved centrally in _physics_process (spec /states/companion). Thresholds
## live on CompanionCombat (IDLE_EPS / RUN_EPS) so there is a single source. The
## measured-speed veto keeps a stationary companion out of a locomotion clip
## (the #420 run-in-place invariant), and the intent layer keeps a moving one
## out of "wait" (the combat-transition slide).
var _move_intent: bool = false  # Set true by whichever state is steering this frame

var _was_moving: bool = false  # Track delayed state transitions
var _stationary_anim_time: float = 0.0  # autopilot tripwire accumulator (#420)
var _resume_blend: float = 0.0  # Blend from frozen pos to trail pos on resume
var _frozen_pos: Vector3 = Vector3.ZERO  # Position when companion froze
const RESUME_BLEND_SPEED: float = 3.0  # Seconds to fully blend back to trail
var _dismissed: bool = false  # When true, stop following and idle in place

## Trail replay — record every physics frame, interpolate on playback
var _trail: Array = []  # [{pos: Vector3, rot: float, state: int, time: float}]
const TRAIL_DELAY: float = 0.5  # Seconds behind the player
const TRAIL_MAX_ENTRIES: int = 150  # ~2.5s at 60fps

## Combat FSM (spec /states/companion-combat). FOLLOW is the trail-replay
## behavior above; the combat states move the companion under its own steering.
enum CombatState { FOLLOW, ENGAGE, ATTACK, REGROUP }
var _combat_state: int = CombatState.FOLLOW
var _combat_target: Node3D = null
var _weapon_config: Dictionary = {}
var _scan_timer: float = 0.0
var _swing_elapsed: float = -1.0  # -1 = not mid-swing
var _swing_length: float = 0.0
var _swing_hit_done: bool = false
var _attack_cooldown: float = 0.0
var _engage_last_dist: float = INF
var _engage_no_progress: float = 0.0
var _combat_stuck_time: float = 0.0  # autopilot tripwire accumulator
var _combat_hits_landed: int = 0


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
						MeshUtils.apply_texture(npc_model, texture)
				_setup_companion_anims(npc_model)
				_attach_companion_weapon(npc_model)
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


func _setup_companion_anims(npc_model: Node) -> void:
	## Build the companion's clip set the same way the player does
	## (player.gd _load_weapon_animations):
	##   • wait + atk1 come from the equipped WEAPON pack (gunblade → shotgun_*),
	##     so the idle stance and swing match the weapon.
	##   • walk + run ALWAYS come from the shared PSO-retargeted locomotion set
	##     (the saber pack's pmsa/pwsa _walk / _run_pso) — never the weapon pack's
	##     psz "dash" (_run). Gunblade/sword/dagger packs have no _run_pso, so
	##     using them for locomotion is what made Kai dash instead of PSO-run.
	var class_id: String = COMPANION_CLASSES.get(companion_id, "humar")
	_is_female = class_id in FEMALE_CLASSES
	var wtype: int = CompanionCombat.weapon_type_for(companion_id)
	var wa: Dictionary = WEAPON_ANIM.get(wtype, WEAPON_ANIM[0])
	var loco: Dictionary = WEAPON_ANIM[0]  # shared PSO locomotion (saber retarget)

	var skel: Skeleton3D = _find_typed(npc_model, "Skeleton3D") as Skeleton3D
	if not skel:
		return

	var wpref: String = wa["prefix_w"] if _is_female else wa["prefix_m"]
	var wglb: String = wa["glb_w"] if _is_female else wa["glb_m"]
	var lpref: String = loco["prefix_w"] if _is_female else loco["prefix_m"]
	var lglb: String = loco["glb_w"] if _is_female else loco["glb_m"]

	# Weapon pack (wait + swing) and locomotion pack (walk + run). For a saber
	# companion these are the same GLB — load it once.
	var wscene: Node = _load_anim_scene(wglb)
	if wscene == null:
		return
	var wsrc: AnimationPlayer = _find_typed(wscene, "AnimationPlayer") as AnimationPlayer
	var lscene: Node = wscene if lglb == wglb else _load_anim_scene(lglb)
	var lsrc: AnimationPlayer = wsrc if lglb == wglb else \
		(_find_typed(lscene, "AnimationPlayer") as AnimationPlayer if lscene else null)
	if wsrc == null:
		wscene.queue_free()
		if lscene and lscene != wscene:
			lscene.queue_free()
		return

	var lib := AnimationLibrary.new()
	# wait/atk1 from the weapon pack; run/walk from the shared PSO locomotion.
	# The swing plays once; everything else loops (spec /states/companion-combat
	# — the swing clock, not the clip, ends the ATTACK swing).
	_add_remapped_anim(lib, skel, wsrc, "wait", [wpref + "_wait"], true)
	_add_remapped_anim(lib, skel, wsrc, "atk1", [wpref + "_atk1"], false)
	_add_remapped_anim(lib, skel, lsrc, "run", [lpref + "_run_pso", lpref + "_run"], true)
	_add_remapped_anim(lib, skel, lsrc, "walk", [lpref + "_walk", lpref + "_run"], true)

	_anim_player = AnimationPlayer.new()
	_anim_player.name = "CompanionAnimPlayer"
	skel.get_parent().add_child(_anim_player)
	_anim_player.add_animation_library("", lib)
	_play_companion_anim("wait")
	wscene.queue_free()
	if lscene and lscene != wscene:
		lscene.queue_free()
	print("[Companion] Loaded anims for %s (female=%s, weapon=%s, loco=%s)" % [companion_id, _is_female, wpref, lpref])


## Instantiate an animation-source GLB scene, or null if missing/unloadable.
func _load_anim_scene(glb_path: String) -> Node:
	if not ResourceLoader.exists(glb_path):
		return null
	var packed := load(glb_path) as PackedScene
	if not packed:
		return null
	return packed.instantiate()


## Copy the first matching candidate clip from source_player into lib under key,
## remapping its skeleton tracks onto skel and setting the loop mode.
func _add_remapped_anim(lib: AnimationLibrary, skel: Skeleton3D, source_player: AnimationPlayer, key: String, candidates: Array, loops: bool) -> void:
	if source_player == null:
		return
	for anim_name: String in candidates:
		if not source_player.has_animation(anim_name):
			continue
		var anim := source_player.get_animation(anim_name).duplicate() as Animation
		anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		for i in range(anim.get_track_count()):
			var track_path := String(anim.track_get_path(i))
			if "Skeleton3D" in track_path:
				var skel_idx := track_path.find("Skeleton3D")
				var prop_part := track_path.substr(skel_idx + 10)
				anim.track_set_path(i, NodePath(skel.name + prop_part))
		lib.add_animation(key, anim)
		return


## Attach the companion's held weapon model to the right-hand bone, mirroring
## the player's _attach_weapon_to_bone. Only companions in COMPANION_WEAPONS
## carry a visible model (Kai → Axeon gunblade); everyone else swings empty-
## handed. Degrades gracefully (warn + skip) if the skeleton, bone, or GLB is
## missing so a bad path never breaks the companion.
func _attach_companion_weapon(npc_model: Node) -> void:
	var entry: Variant = COMPANION_WEAPONS.get(companion_id, null)
	if entry == null:
		return
	var glb_path: String = entry["glb"]
	if not ResourceLoader.exists(glb_path):
		push_warning("[Companion] %s weapon GLB missing: %s" % [companion_id, glb_path])
		return
	var skel: Skeleton3D = _find_typed(npc_model, "Skeleton3D") as Skeleton3D
	if not skel:
		return
	var bone_idx: int = skel.find_bone(WEAPON_BONE_NAME)
	if bone_idx == -1:
		push_warning("[Companion] %s: bone '%s' not found for weapon" % [companion_id, WEAPON_BONE_NAME])
		return
	var packed := load(glb_path) as PackedScene
	if not packed:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "WeaponAttachment_R"
	attach.bone_name = skel.get_bone_name(bone_idx)
	skel.add_child(attach)
	var wnode := packed.instantiate() as Node3D
	attach.add_child(wnode)
	wnode.position = WEAPON_HOLD_POS
	wnode.rotation_degrees = WEAPON_HOLD_ROT
	var s: float = float(entry.get("scale", 1.0))
	wnode.scale = Vector3(s, s, s)
	var tex_path: String = String(entry.get("texture", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex := load(tex_path) as Texture2D
		if tex:
			MeshUtils.apply_texture(wnode, tex)
	print("[Companion] %s equipped weapon %s" % [companion_id, glb_path.get_file()])


func _play_companion_anim(anim_name: String) -> void:
	if not _anim_player or _current_anim == anim_name:
		return
	if not _anim_player.has_animation(anim_name):
		return
	# Debounce ONLY the walk<->run borderline, so a companion hovering near
	# RUN_EPS can't flicker frame to frame. Transitions to/from "wait" (and into
	# "atk1") apply immediately, so the clip never lags the body: a moving
	# companion is never stuck mid-"wait" (the combat-transition slide) and a
	# stopped one is never stuck mid-"run" (the #420 run-in-place). Previously
	# the hold blocked *every* switch, which is what produced the sliding.
	var both_locomotion: bool = (_current_anim == "walk" or _current_anim == "run") \
		and (anim_name == "walk" or anim_name == "run")
	if both_locomotion and _anim_hold_timer > 0.0:
		return
	_anim_player.play(anim_name)
	_current_anim = anim_name
	_anim_hold_timer = ANIM_HOLD_TIME


## Pure selector: choose wait/walk/run from the companion's OWN measured planar
## displacement between two physics frames. Vertical-only motion (gravity, the
## y-snap to the player's height) is excluded — only X/Z count. delta <= 0 and
## zero displacement both yield "wait" (no div-by-zero, no run-in-place). This
## is deliberately a pure function of the body's motion so the animation can
## never desync from where the companion actually is. See /states/companion.
func _select_locomotion_anim(prev_pos: Vector3, curr_pos: Vector3, delta: float) -> String:
	if delta <= 0.0:
		return "wait"
	var moved: Vector3 = curr_pos - prev_pos
	var planar_speed: float = Vector2(moved.x, moved.z).length() / delta
	# Measured-speed selector (intent-to-move assumed here; the intent gate is
	# applied by the caller). Shares the pure clip mapping + thresholds with the
	# unit tests via CompanionCombat.
	return CompanionCombat.locomotion_clip(true, planar_speed)


## Autopilot-only regression oracle for #420. Silent in normal play (gated on
## PSZ_AUTOPILOT). If the companion holds a locomotion clip while its measured
## planar speed stays below IDLE_EPS for longer than the anim-hold debounce, it
## is running in place — push a [sanity] FAIL any headless/Mac run can catch.
func _autopilot_anim_tripwire(prev_pos: Vector3, curr_pos: Vector3, delta: float) -> void:
	if not OS.has_environment("PSZ_AUTOPILOT"):
		return
	if delta <= 0.0:
		return
	var locomoting: bool = _current_anim == "walk" or _current_anim == "run"
	var moved: Vector3 = curr_pos - prev_pos
	var planar_speed: float = Vector2(moved.x, moved.z).length() / delta
	if locomoting and planar_speed < CompanionCombat.IDLE_EPS:
		_stationary_anim_time += delta
	else:
		_stationary_anim_time = 0.0
	# Beyond the debounce window this is a genuine run-in-place, not the brief
	# 0.3s blend when the companion stops.
	if _stationary_anim_time > ANIM_HOLD_TIME:
		push_error("[sanity] FAIL: companion '%s' holds '%s' while stationary for %.2fs (planar speed %.3f m/s < %.2f)" % [companion_id, _current_anim, _stationary_anim_time, planar_speed, CompanionCombat.IDLE_EPS])
		_stationary_anim_time = 0.0  # avoid log spam


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
	if not _ensure_player_ref():
		return
	_anim_hold_timer = maxf(_anim_hold_timer - delta, 0.0)
	_record_trail()
	# Capture position before any state moves us so the locomotion clip is a
	# pure function of THIS frame's own displacement. Each state sets
	# _move_intent (true while steering); the clip is resolved once, centrally,
	# below — like the player's single per-frame animation update.
	var prev_pos: Vector3 = global_position
	_move_intent = false
	if _combat_state == CombatState.FOLLOW:
		_process_follow(delta)
		_tick_combat_scan(delta)
	else:
		_process_combat(delta)
	_update_locomotion_anim(_move_intent, prev_pos, delta)


## Resolve and apply the locomotion clip from the FSM's intent and the frame's
## measured displacement. Suspended during an ATTACK swing (the atk1 clip owns
## the rig then — spec /states/companion-combat).
func _update_locomotion_anim(intent_moving: bool, prev_pos: Vector3, delta: float) -> void:
	if _swing_elapsed >= 0.0:
		return
	var clip: String = _select_locomotion_anim(prev_pos, global_position, delta) if intent_moving else "wait"
	_play_companion_anim(clip)
	_autopilot_anim_tripwire(prev_pos, global_position, delta)


## Cache the player reference; false while no player exists yet.
func _ensure_player_ref() -> bool:
	if is_instance_valid(_player_ref):
		return true
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	_player_ref = players[0]
	return true


## Record the player's position every physics frame — in every combat state,
## so the trail never has a combat-shaped hole when FOLLOW resumes.
func _record_trail() -> void:
	var ps: int = 0
	if "current_state" in _player_ref:
		ps = _player_ref.current_state
	var player_rot: float = _player_ref.player_rotation if "player_rotation" in _player_ref else _player_ref.rotation.y
	_trail.append({
		"pos": _player_ref.global_position,
		"rot": player_rot,
		"state": ps,
		"time": Time.get_ticks_msec() / 1000.0,
	})
	while _trail.size() > TRAIL_MAX_ENTRIES:
		_trail.remove_at(0)


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
	_combat_state = CombatState.FOLLOW
	_combat_target = null
	_swing_elapsed = -1.0
	_play_companion_anim("wait")
	print("[Companion] %s dismissed — stopped following" % companion_id)


func _process_follow(_delta: float) -> void:
	if _dismissed:
		return
	# Player ref caching, anim-hold ticking, and trail recording live in
	# _physics_process so they run in every combat state, not just FOLLOW.
	var player_rot: float = _player_ref.player_rotation if "player_rotation" in _player_ref else _player_ref.rotation.y
	var now: float = Time.get_ticks_msec() / 1000.0

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

	# Position MAY consult the delayed player state — but ONLY the true
	# locomotion states (WALKING=1, RUNNING=2) advance the trail. A rooted
	# player state (ATTACKING=3, DAMAGED, DOWN, …) is >= 1 too, so the old
	# `delayed_state >= 1` made the companion try to follow a stationary player
	# and then fall into the `run` branch — running in place (#420). Restrict
	# the follow-move to actual locomotion.
	var is_moving: bool = delayed_state == 1 or delayed_state == 2

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
		_move_intent = true
	else:
		# Player was idle (or rooted) — freeze in place, face player's direction
		global_position.y = _player_ref.global_position.y
		rotation.y = lerp_angle(rotation.y, player_rot, 5.0 * _delta)
		_was_moving = false
		_move_intent = false
	# The locomotion clip is resolved centrally in _physics_process from
	# _move_intent + this frame's measured displacement (spec /states/companion):
	# intent gates out the combat-transition slide, the measured-speed veto gates
	# out the #420 run-in-place, and the resume-from-freeze blend naturally ramps
	# walk -> run as the measured speed climbs.


func _teleport_behind_player() -> void:
	if not is_instance_valid(_player_ref):
		return
	var player_rot: float = _player_ref.rotation.y
	if "player_rotation" in _player_ref:
		player_rot = _player_ref.player_rotation
	var behind := -Vector3(sin(player_rot), 0, cos(player_rot)) * 3.0
	global_position = _player_ref.global_position + behind
	global_position.y = _player_ref.global_position.y


# ── Combat FSM (spec /states/companion-combat) ──────────────────────────
# Phase 1: offense only. FOLLOW is the trail-replay above; ENGAGE/ATTACK/
# REGROUP move the companion under its own steering. Decisions are pure
# functions on CompanionCombat; this block is the stateful driver.


## Scan for a target on a fixed cadence while following. Combat never
## starts while speaking or dismissed.
func _tick_combat_scan(delta: float) -> void:
	if _dismissed or _speaking:
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = CompanionCombat.COMBAT_SCAN_INTERVAL
	var target := _pick_combat_target()
	if target != null:
		_combat_target = target
		_enter_engage()


## Build candidate data from the "enemies" group and delegate the choice to
## the pure selector. The player's primary reticle target (read defensively —
## a rename must degrade to nearest-enemy, never crash) gets assist priority.
func _pick_combat_target() -> Node3D:
	if not is_inside_tree():
		return null
	var player_target: Node3D = _player_primary_target()
	var candidates: Array = []
	var nodes: Array = []
	var preferred_idx := -1
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e is Node3D:
			continue
		candidates.append({"pos": e.global_position, "alive": bool(e.get("is_alive"))})
		nodes.append(e)
		if e == player_target:
			preferred_idx = candidates.size() - 1
	var idx := CompanionCombat.select_target(
		candidates, _player_ref.global_position, global_position, preferred_idx)
	if idx < 0:
		return null
	return nodes[idx]


func _player_primary_target() -> Node3D:
	var tlist: Variant = _player_ref.get("_targeted_enemies")
	if tlist is Array and not (tlist as Array).is_empty():
		var t: Variant = (tlist as Array)[0]
		if t is Node3D and is_instance_valid(t):
			return t
	return null


func _enter_engage() -> void:
	_combat_state = CombatState.ENGAGE
	_engage_last_dist = INF
	_engage_no_progress = 0.0
	if _weapon_config.is_empty():
		_weapon_config = CombatManager.get_weapon_type_config(
			CompanionCombat.weapon_type_for(companion_id))


func _enter_regroup() -> void:
	_combat_state = CombatState.REGROUP
	_combat_target = null
	_swing_elapsed = -1.0


func _process_combat(delta: float) -> void:
	if _dismissed:
		_combat_state = CombatState.FOLLOW
		_combat_target = null
		_swing_elapsed = -1.0
		return
	if _speaking and _combat_state != CombatState.REGROUP:
		_enter_regroup()
	match _combat_state:
		CombatState.ENGAGE:
			_process_engage(delta)
		CombatState.ATTACK:
			_process_attack(delta)
		CombatState.REGROUP:
			_process_regroup(delta)
	_combat_tripwire(delta)


## Target still worth fighting: alive and inside the player's leash.
func _target_valid() -> bool:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return false
	if not _combat_target.get("is_alive"):
		return false
	return CompanionCombat.within_leash(
		_combat_target.global_position, _player_ref.global_position)


## Steer toward dir at speed with environment collision. Flags _move_intent so
## the central animation update plays a locomotion clip this frame; the clip
## itself still comes from measured displacement (spec /states/companion).
func _combat_step(dir: Vector3, speed: float, _delta: float) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	velocity = dir * speed
	velocity.y = 0
	move_and_slide()
	global_position.y = _player_ref.global_position.y
	rotation.y = atan2(dir.x, dir.z)
	_move_intent = true


func _process_engage(delta: float) -> void:
	if not _target_valid():
		_enter_regroup()
		return
	var to_target := _combat_target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	if dist <= CompanionCombat.ENGAGE_REACH_FRAC * float(_weapon_config.get("hit_h_dist", 2.4)):
		_start_companion_swing()
		return
	# Blocked-approach self-heal: no closing progress for too long → drop
	# the target and regroup (keeps the autopilot tripwire unreachable).
	if dist >= _engage_last_dist - 0.05:
		_engage_no_progress += delta
		if _engage_no_progress >= CompanionCombat.ENGAGE_NO_PROGRESS_TIME:
			_enter_regroup()
			return
	else:
		_engage_no_progress = 0.0
	_engage_last_dist = dist
	_combat_step(to_target, FOLLOW_SPEED, delta)


func _start_companion_swing() -> void:
	_combat_state = CombatState.ATTACK
	_swing_elapsed = 0.0
	_swing_hit_done = false
	_swing_length = CompanionCombat.FALLBACK_SWING_TIME
	velocity = Vector3.ZERO
	var dir := _combat_target.global_position - global_position
	dir.y = 0
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
	if _anim_player and _anim_player.has_animation("atk1"):
		_swing_length = _anim_player.get_animation("atk1").length
		_anim_player.play("atk1")
		_current_anim = "atk1"
		_anim_hold_timer = 0.0


func _process_attack(delta: float) -> void:
	if _swing_elapsed >= 0.0:
		var prev := _swing_elapsed
		_swing_elapsed += delta
		var frac_arr: Array = _weapon_config.get("damaging_frac", [0.4])
		if not _swing_hit_done and CompanionCombat.swing_crossed_damaging_frac(
				prev, _swing_elapsed, _swing_length, float(frac_arr[0])):
			_swing_hit_done = true
			_execute_companion_hit()
		if _swing_elapsed >= _swing_length:
			_swing_elapsed = -1.0
			_attack_cooldown = CompanionCombat.ATTACK_COOLDOWN \
				/ maxf(float(_weapon_config.get("speed_mult", 1.0)), 0.1)
			_current_anim = ""
			_play_companion_anim("wait")
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	if not _target_valid():
		_enter_regroup()
		return
	var to_target := _combat_target.global_position - global_position
	to_target.y = 0
	if to_target.length() <= CompanionCombat.ENGAGE_REACH_FRAC * float(_weapon_config.get("hit_h_dist", 2.4)):
		_start_companion_swing()
	else:
		_enter_engage()


## The damaging frame: same cone scan and hurtbox entry point as the player's
## _execute_attack_hit — receiver-side defense/evasion/crit stay in the enemy.
func _execute_companion_hit() -> void:
	if not is_inside_tree():
		return
	var stats := _companion_stats()
	var atk := CompanionCombat.compute_attack(
		int(stats.attack), int(stats.accuracy), _weapon_config)
	var origin := global_position + Vector3(0, 1.0, 0)
	var in_cone: Array = ConeTargeting.scan_enemies(
		get_tree().get_nodes_in_group("enemies"), origin, rotation.y, _weapon_config)
	for i in range(mini(int(atk.max_targets), in_cone.size())):
		var enemy: Node3D = in_cone[i]
		var hb: Variant = enemy.get("hurtbox")
		if hb == null or not is_instance_valid(hb):
			continue
		var knock_dir: Vector3 = enemy.global_position - global_position
		knock_dir.y = 0
		knock_dir = knock_dir.normalized()
		for _h in range(int(atk.hits)):
			hb.take_hit(int(atk.damage), knock_dir * float(atk.knockback), int(atk.accuracy), "", 0)
		_note_companion_hit(enemy, int(atk.damage))


## Companion attack/accuracy: its class (COMPANION_CLASSES) at the player's
## current level — no weapon/mag/material/buff terms in phase 1.
func _companion_stats() -> Dictionary:
	var level := 1
	var character: Variant = CharacterManager.get_active_character()
	if character != null:
		level = int(character.get("level", 1))
	var class_id: String = COMPANION_CLASSES.get(companion_id, "humar")
	var class_data: Variant = ClassRegistry.get_class_data(class_id)
	if class_data == null:
		return {"attack": 10, "accuracy": 100}
	var s: Dictionary = class_data.get_stats_at_level(maxi(level, 1))
	return {"attack": int(s.get("attack", 10)), "accuracy": int(s.get("accuracy", 100))}


func _process_regroup(delta: float) -> void:
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0
	if to_player.length() > TELEPORT_DISTANCE:
		_teleport_behind_player()
		_trail.clear()
	if to_player.length() <= START_DISTANCE:
		_combat_state = CombatState.FOLLOW
		_was_moving = false
		_play_companion_anim("wait")
		return
	_combat_step(to_player, CATCHUP_SPEED, delta)


func _note_companion_hit(enemy: Node, damage: int) -> void:
	_combat_hits_landed += 1
	_combat_stuck_time = 0.0
	if _combat_hits_landed == 1 and OS.has_environment("PSZ_AUTOPILOT"):
		print("[sanity] companion-combat: first hit %s dmg=%d" % [str(enemy.name), damage])


## Autopilot-only backstop (spec /states/companion-combat): too long in
## ENGAGE/ATTACK without landing a hit is a wedged companion. The 8s
## no-progress drop should make this unreachable; silent in normal play.
func _combat_tripwire(delta: float) -> void:
	if not OS.has_environment("PSZ_AUTOPILOT"):
		return
	if _combat_state == CombatState.ENGAGE or _combat_state == CombatState.ATTACK:
		_combat_stuck_time += delta
		if _combat_stuck_time > CompanionCombat.COMBAT_STUCK_TIME:
			push_error("[sanity] FAIL: companion '%s' stuck in combat state %d for %.1fs without landing a hit" % [companion_id, _combat_state, _combat_stuck_time])
			_combat_stuck_time = 0.0  # avoid log spam
	else:
		_combat_stuck_time = 0.0


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
