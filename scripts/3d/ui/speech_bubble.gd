extends CanvasLayer
class_name SpeechBubble
## Shared native-resolution 2D speech bubble anchored to a 3D actor or world point
## (issue #557; spec /states/speech-bubbles).
##
## Replaces the three private SubViewport -> Sprite3D copies in companion_npc,
## city_office_controller, and city_counter_controller:
##   - Renders in 2D canvas space at layer 40 (below shops/menus/HUD/fade/CRT,
##     crisp across all 3D render scales, zero SubViewport render targets).
##   - Resolves head height from static MeshInstance3D bounds * world Y scale.
##   - Projects via Camera3D.unproject_position with behind-camera bottom pinning,
##     viewport margin clamping, HUD corner avoidance, multi-bubble de-overlap,
##     and a dynamic bottom tail tracking the speaker's horizontal position.

signal finished

const LAYER := 40

const FONT_REGULAR: FontFile = preload("res://assets/fonts/JetBrainsMono-Regular.ttf")
const FONT_BOLD: FontFile = preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const OPEN_SFX_PATH := "res://assets/sfx/ui/dialog_open.wav"

const FONT_SIZE := 15
const SPEAKER_FONT_SIZE := 12
const LINE_SPACING := 3

const MIN_WIDTH := 140.0
const MAX_WIDTH := 360.0
const PAD_X := 15.0
const PAD_Y := 10.0
const SPEAKER_GAP := 3.0
const CORNER_RADIUS := 10.0
const BORDER_WIDTH := 2.0
const TAIL_HALF_W := 8.0
const TAIL_H := 11.0

const SAFE_MARGIN_X := 24.0
const SAFE_MARGIN_TOP := 20.0
const SAFE_MARGIN_BOTTOM := 28.0
const HUD_GAP := 8.0
const OVERLAP_GAP := 8.0

const DEFAULT_HEAD_HEIGHT := 1.80
const MIN_HEAD_HEIGHT := 1.10
const MAX_HEAD_HEIGHT := 2.40
const HEAD_CLEARANCE := 0.22
const FADE_DURATION := 0.50

const BG_COLOR := Color(0.98, 0.99, 1.0, 0.96)
const BORDER_COLOR := Color(0.22, 0.32, 0.46, 0.95)
const SHADOW_COLOR := Color(0.0, 0.04, 0.10, 0.38)
const SHADOW_OFFSET := Vector2(0.0, 3.0)
const TEXT_COLOR := Color(0.10, 0.10, 0.17)
const SPEAKER_COLOR := Color(0.20, 0.36, 0.62)

static var _active_bubbles: Array[SpeechBubble] = []
static var _autopilot_logged_ok := false

var _card: _BubbleCard
var _anchor_node: Node3D = null
var _anchor_world: Vector3 = Vector3.ZERO
var _has_node_anchor := false
var _head_offset_y := DEFAULT_HEAD_HEIGHT + HEAD_CLEARANCE
var _active := false
var _remaining := 0.0
var _last_raw_anchor_y := 0.0
var _last_placed_total := Rect2()


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_card()


func _exit_tree() -> void:
	_unregister_active()


static func spawn(
	host: Node,
	anchor_target: Variant,
	text_str: String,
	dur_sec: float = 4.0,
	speaker_name: String = "",
	play_sfx: bool = true
) -> SpeechBubble:
	var bubble := SpeechBubble.new()
	host.add_child(bubble)
	bubble.finished.connect(bubble.queue_free)
	bubble.present(anchor_target, text_str, dur_sec, speaker_name, play_sfx)
	return bubble


func present(
	anchor_target: Variant,
	text_str: String,
	dur_sec: float = 4.0,
	speaker_name: String = "",
	play_sfx: bool = true
) -> void:
	_ensure_card()
	if anchor_target is Node3D:
		_anchor_node = anchor_target as Node3D
		_has_node_anchor = true
		_head_offset_y = compute_head_offset_y(_anchor_node)
	elif anchor_target is Vector3:
		_anchor_node = null
		_has_node_anchor = false
		_anchor_world = anchor_target as Vector3
		_head_offset_y = 0.0
	else:
		push_warning("[SpeechBubble] Unsupported anchor type; expected Node3D or Vector3")
		return

	_card.set_content(speaker_name, text_str)
	_card.modulate.a = 1.0
	_remaining = maxf(0.1, dur_sec)
	_active = true
	_register_active()

	if play_sfx and SfxManager != null:
		SfxManager.play(OPEN_SFX_PATH)

	_sync_placement()


func dismiss() -> void:
	if not _active:
		if _card:
			_card.visible = false
		return
	_active = false
	_remaining = 0.0
	_last_placed_total = Rect2()
	_unregister_active()
	if _card:
		_card.visible = false
	finished.emit()


func is_active() -> bool:
	return _active


func get_placed_rect() -> Rect2:
	return _last_placed_total


func get_card_control() -> Control:
	_ensure_card()
	return _card


func _process(delta: float) -> void:
	if not _active:
		return
	if _has_node_anchor and not is_instance_valid(_anchor_node):
		dismiss()
		return
	_remaining -= delta
	if _remaining <= 0.0:
		dismiss()
		return
	if _card:
		_card.modulate.a = clampf(_remaining / FADE_DURATION, 0.0, 1.0) if _remaining < FADE_DURATION else 1.0
	_sync_placement()


func _ensure_card() -> void:
	if _card != null:
		return
	_card = _BubbleCard.new()
	_card.name = "SpeechBubbleCard"
	_card.visible = false
	add_child(_card)


func _register_active() -> void:
	if not _active_bubbles.has(self):
		_active_bubbles.append(self)


func _unregister_active() -> void:
	_active_bubbles.erase(self)


func _is_suppressed_by_overlay() -> bool:
	if SceneManager != null and not SceneManager._overlay_stack.is_empty():
		return true
	if PsoStartMenu != null and PsoStartMenu.is_open():
		return true
	return false


func _resolve_world_pos() -> Vector3:
	if _has_node_anchor and is_instance_valid(_anchor_node):
		return _anchor_node.global_position + Vector3(0.0, _head_offset_y, 0.0)
	return _anchor_world


func _resolve_viewport() -> Viewport:
	if custom_viewport != null:
		return custom_viewport
	if _has_node_anchor and is_instance_valid(_anchor_node) and _anchor_node.is_inside_tree():
		return _anchor_node.get_viewport()
	if is_inside_tree():
		return get_viewport()
	return null


func _sync_placement() -> void:
	if _card == null:
		return
	if _is_suppressed_by_overlay():
		_card.visible = false
		return
	var vp := _resolve_viewport()
	if vp == null:
		return
	if custom_viewport != vp and vp is SubViewport:
		custom_viewport = vp
	var vp_rect := vp.get_visible_rect()
	if vp_rect.size.x <= 1.0 or vp_rect.size.y <= 1.0:
		vp_rect = Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))

	var cam := vp.get_camera_3d()
	var world_pos := _resolve_world_pos()
	var proj := project_world_anchor(cam, world_pos, vp_rect)
	var raw_anchor: Vector2 = proj["anchor_px"]
	var behind: bool = proj["behind"]
	_last_raw_anchor_y = raw_anchor.y

	var in_city := SessionManager != null and SessionManager.get_location() == "city"
	var hud_rects := hud_exclusion_rects(vp_rect, in_city)
	var occupied := _collect_lower_bubble_rects(vp)
	var placed := compute_placement(vp_rect, _card.card_box_size, raw_anchor, behind, hud_rects, occupied)

	var box_rect: Rect2 = placed["box_rect"]
	_last_placed_total = placed["total_rect"]
	_card.position = box_rect.position
	_card.set_tail(float(placed["tail_local_x"]), float(placed["tail_tip_local_x"]))
	_card.visible = true
	_check_autopilot_invariant(vp_rect, _last_placed_total)


func _collect_lower_bubble_rects(vp: Viewport) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for other in _active_bubbles:
		if other == self or not is_instance_valid(other) or not other._active:
			continue
		if other._resolve_viewport() != vp:
			continue
		if other._last_placed_total.size == Vector2.ZERO:
			continue
		var other_lower := other._last_raw_anchor_y > _last_raw_anchor_y + 0.5
		var tie_break := absf(other._last_raw_anchor_y - _last_raw_anchor_y) <= 0.5 \
			and other.get_instance_id() < get_instance_id()
		if other_lower or tie_break:
			out.append(other._last_placed_total)
	return out


func _check_autopilot_invariant(vp_rect: Rect2, total_rect: Rect2) -> void:
	if not OS.has_environment("PSZ_AUTOPILOT"):
		return
	var eps := 1.5
	var inside := total_rect.position.x >= vp_rect.position.x - eps \
		and total_rect.position.y >= vp_rect.position.y - eps \
		and total_rect.end.x <= vp_rect.end.x + eps \
		and total_rect.end.y <= vp_rect.end.y + eps
	if not inside:
		push_error("[sanity] FAIL: speech bubble rect %s escaped viewport %s" % [str(total_rect), str(vp_rect)])
		return
	if not _autopilot_logged_ok:
		_autopilot_logged_ok = true
		print("[sanity] speech-bubble: clamped ok rect=%s" % str(total_rect))


## Derive head anchor height above `actor.global_position` from static visual meshes,
## excluding held weapon BoneAttachment3D subtrees so raised blades do not push bubbles up.
static func compute_head_offset_y(actor: Node3D) -> float:
	if actor == null:
		return DEFAULT_HEAD_HEIGHT + HEAD_CLEARANCE
	var raw_top := _max_actor_mesh_y(actor, Transform3D.IDENTITY, true)
	if raw_top <= 0.05:
		return DEFAULT_HEAD_HEIGHT + HEAD_CLEARANCE
	var scale_y := absf(actor.global_transform.basis.get_scale().y)
	if scale_y <= 0.0001:
		scale_y = 1.0
	var world_top := clampf(raw_top * scale_y, MIN_HEAD_HEIGHT, MAX_HEAD_HEIGHT)
	return world_top + HEAD_CLEARANCE


static func _max_actor_mesh_y(node: Node, local_xform: Transform3D, is_root: bool) -> float:
	if node is BoneAttachment3D and String(node.name).begins_with("Weapon"):
		return -INF
	var next_xform := local_xform
	if not is_root and node is Node3D:
		next_xform = local_xform * (node as Node3D).transform
	var best := -INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var ab: AABB = next_xform * (node as MeshInstance3D).mesh.get_aabb()
		best = ab.end.y
	for child in node.get_children():
		var child_top := _max_actor_mesh_y(child, next_xform, false)
		if child_top > best:
			best = child_top
	return best


## Project `world_pos` through `cam` into `vp_rect`, guarding behind-camera coordinates
## so trailing companions pin to the bottom edge instead of inverting across w < 0.
static func project_world_anchor(cam: Camera3D, world_pos: Vector3, vp_rect: Rect2) -> Dictionary:
	if cam == null:
		var center := vp_rect.position + Vector2(vp_rect.size.x * 0.5, vp_rect.size.y * 0.5)
		return {"anchor_px": center, "behind": false}
	var cam_local: Vector3 = cam.global_transform.affine_inverse() * world_pos
	if cam_local.z >= -0.2:
		var denom := maxf(absf(cam_local.z) + absf(cam_local.x), 0.001)
		var bearing := clampf(0.5 + (cam_local.x / denom) * 0.42, 0.12, 0.88)
		var pinned := Vector2(
			vp_rect.position.x + vp_rect.size.x * bearing,
			vp_rect.end.y - SAFE_MARGIN_BOTTOM
		)
		return {"anchor_px": pinned, "behind": true}
	return {"anchor_px": cam.unproject_position(world_pos), "behind": false}


static func hud_exclusion_rects(vp_rect: Rect2, in_city: bool) -> Array[Rect2]:
	var origin := vp_rect.position
	var end_pt := vp_rect.end
	var zones: Array[Rect2] = [
		Rect2(origin.x, origin.y, 224.0, 128.0),  # HudStats (HP / PP / EXP)
	]
	if in_city:
		zones.append(Rect2(end_pt.x - 96.0, origin.y, 96.0, 34.0))
	else:
		zones.append(Rect2(end_pt.x - 172.0, origin.y, 172.0, 164.0))          # RoomMinimap + FPS
		zones.append(Rect2(end_pt.x - 276.0, end_pt.y - 152.0, 276.0, 152.0))  # ActionPalette
		zones.append(Rect2(origin.x, end_pt.y - 116.0, 280.0, 116.0))          # TargetInfo / QuickWeapon
	return zones


## Pure screen-space placement solver (spec /states/speech-bubbles).
static func compute_placement(
	vp_rect: Rect2,
	card_box_size: Vector2,
	raw_anchor_px: Vector2,
	behind_camera: bool,
	hud_rects: Array[Rect2],
	occupied_rects: Array[Rect2]
) -> Dictionary:
	var w := card_box_size.x
	var h := card_box_size.y
	var total_h := h + TAIL_H
	var left_b := vp_rect.position.x + SAFE_MARGIN_X
	var right_b := maxf(left_b, vp_rect.end.x - SAFE_MARGIN_X - w)
	var top_b := vp_rect.position.y + SAFE_MARGIN_TOP
	var bottom_b := maxf(top_b, vp_rect.end.y - SAFE_MARGIN_BOTTOM - total_h)

	var anchor_px := raw_anchor_px
	if behind_camera:
		anchor_px = Vector2(
			clampf(raw_anchor_px.x, vp_rect.position.x + vp_rect.size.x * 0.12, vp_rect.position.x + vp_rect.size.x * 0.88),
			vp_rect.end.y - SAFE_MARGIN_BOTTOM
		)

	var ideal := Vector2(anchor_px.x - w * 0.5, anchor_px.y - total_h)
	var bx := clampf(ideal.x, left_b, right_b)
	var by := clampf(ideal.y, top_b, bottom_b)
	var clamped_edge := absf(bx - ideal.x) > 0.5 or absf(by - ideal.y) > 0.5

	var shifted := _nudge_from_hud(Vector2(bx, by), Vector2(w, total_h), Rect2(left_b, top_b, right_b - left_b, bottom_b - top_b), hud_rects)
	var nudged_hud: bool = shifted["nudged"]
	bx = shifted["pos"].x
	by = shifted["pos"].y

	var nudged_overlap := false
	for occ in occupied_rects:
		if not Rect2(bx, by, w, total_h).intersects(occ):
			continue
		var up_y := occ.position.y - total_h - OVERLAP_GAP
		var down_y := occ.end.y + OVERLAP_GAP
		if up_y >= top_b:
			by = up_y
		elif down_y <= bottom_b:
			by = down_y
		nudged_overlap = true

	var min_tail := CORNER_RADIUS + TAIL_HALF_W + 4.0
	var max_tail := maxf(min_tail, w - CORNER_RADIUS - TAIL_HALF_W - 4.0)
	var tail_local_x := clampf(anchor_px.x - bx, min_tail, max_tail)
	var tail_tip_local_x := clampf(anchor_px.x - bx, CORNER_RADIUS + 2.0, maxf(CORNER_RADIUS + 2.0, w - CORNER_RADIUS - 2.0))

	return {
		"box_rect": Rect2(bx, by, w, h),
		"total_rect": Rect2(bx, by, w, total_h),
		"anchor_px": anchor_px,
		"tail_local_x": tail_local_x,
		"tail_tip_local_x": tail_tip_local_x,
		"clamped_edge": clamped_edge,
		"nudged_hud": nudged_hud,
		"nudged_overlap": nudged_overlap,
	}


static func _nudge_from_hud(
	cur_pos: Vector2,
	total_size: Vector2,
	bounds: Rect2,
	hud_rects: Array[Rect2]
) -> Dictionary:
	var pos := cur_pos
	var nudged := false
	for hud in hud_rects:
		if not Rect2(pos, total_size).intersects(hud):
			continue
		var candidates: Array[Vector2] = [
			Vector2(pos.x, hud.end.y + HUD_GAP),
			Vector2(pos.x, hud.position.y - total_size.y - HUD_GAP),
			Vector2(hud.end.x + HUD_GAP, pos.y),
			Vector2(hud.position.x - total_size.x - HUD_GAP, pos.y),
		]
		var best := pos
		var best_dist := INF
		for cand in candidates:
			if cand.x < bounds.position.x - 0.5 or cand.x > bounds.end.x + 0.5:
				continue
			if cand.y < bounds.position.y - 0.5 or cand.y > bounds.end.y + 0.5:
				continue
			if _intersects_any(Rect2(cand, total_size), hud_rects):
				continue
			var d := pos.distance_to(cand)
			if d < best_dist:
				best_dist = d
				best = Vector2(clampf(cand.x, bounds.position.x, bounds.end.x), clampf(cand.y, bounds.position.y, bounds.end.y))
		if best_dist < INF:
			pos = best
			nudged = true
	return {"pos": pos, "nudged": nudged}


static func _intersects_any(rect: Rect2, zones: Array[Rect2]) -> bool:
	for z in zones:
		if rect.intersects(z):
			return true
	return false


class _BubbleCard extends Control:
	var card_box_size := Vector2(MIN_WIDTH, 44.0)
	var _speaker_label: Label
	var _body_label: Label
	var _tail_local_x := MIN_WIDTH * 0.5
	var _tail_tip_local_x := MIN_WIDTH * 0.5

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_speaker_label = Label.new()
		_speaker_label.name = "SpeakerLabel"
		_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_speaker_label.add_theme_font_override("font", FONT_BOLD)
		_speaker_label.add_theme_font_size_override("font_size", SPEAKER_FONT_SIZE)
		_speaker_label.add_theme_color_override("font_color", SPEAKER_COLOR)
		add_child(_speaker_label)

		_body_label = Label.new()
		_body_label.name = "BodyLabel"
		_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body_label.add_theme_font_override("font", FONT_REGULAR)
		_body_label.add_theme_font_size_override("font_size", FONT_SIZE)
		_body_label.add_theme_color_override("font_color", TEXT_COLOR)
		_body_label.add_theme_constant_override("line_spacing", LINE_SPACING)
		add_child(_body_label)

	func set_content(speaker_name: String, text_str: String) -> void:
		var clean_speaker := speaker_name.strip_edges()
		var max_inner_w := MAX_WIDTH - PAD_X * 2.0
		var single_w := FONT_REGULAR.get_multiline_string_size(
			text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE
		).x
		var speaker_w := 0.0
		if not clean_speaker.is_empty():
			speaker_w = FONT_BOLD.get_string_size(clean_speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, SPEAKER_FONT_SIZE).x
		var inner_w := clampf(ceilf(maxf(minf(single_w, max_inner_w), speaker_w)) + 4.0, MIN_WIDTH - PAD_X * 2.0, max_inner_w)
		var body_metrics := FONT_REGULAR.get_multiline_string_size(
			text_str,
			HORIZONTAL_ALIGNMENT_LEFT,
			inner_w,
			FONT_SIZE,
			-1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		)
		var speaker_h := 0.0
		if not clean_speaker.is_empty():
			speaker_h = FONT_BOLD.get_height(SPEAKER_FONT_SIZE) + SPEAKER_GAP
			_speaker_label.text = clean_speaker
			_speaker_label.position = Vector2(PAD_X, PAD_Y)
			_speaker_label.size = Vector2(inner_w, speaker_h)
			_speaker_label.visible = true
		else:
			_speaker_label.text = ""
			_speaker_label.visible = false

		var body_h := maxf(FONT_REGULAR.get_height(FONT_SIZE), ceilf(body_metrics.y))
		_body_label.text = text_str
		_body_label.position = Vector2(PAD_X, PAD_Y + speaker_h)
		_body_label.size = Vector2(inner_w, body_h)

		card_box_size = Vector2(inner_w + PAD_X * 2.0, PAD_Y * 2.0 + speaker_h + body_h)
		size = Vector2(card_box_size.x, card_box_size.y + TAIL_H)
		queue_redraw()

	func set_tail(local_x: float, tip_local_x: float) -> void:
		if absf(local_x - _tail_local_x) <= 0.25 and absf(tip_local_x - _tail_tip_local_x) <= 0.25:
			return
		_tail_local_x = local_x
		_tail_tip_local_x = tip_local_x
		queue_redraw()

	func _draw() -> void:
		var poly := _build_outline(card_box_size, _tail_local_x, _tail_tip_local_x, Vector2.ZERO)
		var shadow_poly := _build_outline(card_box_size, _tail_local_x, _tail_tip_local_x, SHADOW_OFFSET)
		draw_colored_polygon(shadow_poly, SHADOW_COLOR)
		draw_colored_polygon(poly, BG_COLOR)
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, BORDER_COLOR, BORDER_WIDTH, true)

	static func _build_outline(box_sz: Vector2, tail_x: float, tip_x: float, shift: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var r := CORNER_RADIUS
		var w := box_sz.x
		var h := box_sz.y
		_append_arc(pts, Vector2(r, r) + shift, r, PI, PI * 1.5)
		_append_arc(pts, Vector2(w - r, r) + shift, r, -PI * 0.5, 0.0)
		_append_arc(pts, Vector2(w - r, h - r) + shift, r, 0.0, PI * 0.5)
		var tail_r := clampf(tail_x + TAIL_HALF_W, r + 2.0, w - r - 2.0)
		var tail_l := clampf(tail_x - TAIL_HALF_W, r + 2.0, tail_r - 2.0)
		pts.append(Vector2(tail_r, h) + shift)
		pts.append(Vector2(tip_x, h + TAIL_H) + shift)
		pts.append(Vector2(tail_l, h) + shift)
		_append_arc(pts, Vector2(r, h - r) + shift, r, PI * 0.5, PI)
		return pts

	static func _append_arc(pts: PackedVector2Array, center: Vector2, radius: float, a0: float, a1: float) -> void:
		const STEPS := 5
		for i in range(STEPS + 1):
			var ang := lerpf(a0, a1, float(i) / float(STEPS))
			pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
