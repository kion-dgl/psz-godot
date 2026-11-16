extends CanvasLayer
class_name SpeechBubble
## Shared PSO-styled native-resolution 2D speech bubble anchored to a 3D actor
## or world point (issue #557; spec /states/speech-bubbles).
##
## Visual & placement contract:
##   - Renders in 2D canvas space at layer 40 (above 3D world, below shops/menus/HUD/CRT,
##     crisp across all 3D render scales, zero SubViewport render targets).
##   - Squared-off forward-leaning PSO parallelogram (CORNER_RADIUS = 5px, SLANT_RATIO = 0.16,
##     boxier 316px max wrap) backed by a solid #000000 offset silhouette (+6, +5) and
##     bold #080A10 JetBrainsMono-Bold lettering.
##   - Consistent per-character pastel fills (Kai, Sarisa, Ogi, Principal, etc.).
##   - Floats comfortably above the actor while stretching a sharp pointer tail
##     back to the speaker's head (or a directional arrow when off-screen/behind camera).

signal finished

const LAYER := 40

const FONT_BOLD: FontFile = preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const OPEN_SFX_PATH := "res://assets/sfx/ui/dialog_open.wav"

const FONT_SIZE := 15
const LINE_SPACING := 4

const MIN_WIDTH := 164.0
const MAX_WIDTH := 316.0
const PAD_X := 22.0
const PAD_Y := 16.0
const CORNER_RADIUS := 5.0
const SLANT_RATIO := 0.16
const BORDER_WIDTH := 1.6
const FLOAT_GAP := 86.0
const TAIL_BASE_HALF_W := 11.0
const MAX_OFFSCREEN_TAIL := 56.0
const MAX_ONSCREEN_TAIL := 185.0
const BACKDROP_OFFSET := Vector2(6.0, 5.0)

const SAFE_MARGIN_X := 28.0
const SAFE_MARGIN_TOP := 22.0
const SAFE_MARGIN_BOTTOM := 30.0
const HUD_GAP := 12.0
const OVERLAP_GAP := 12.0

const DEFAULT_HEAD_HEIGHT := 1.80
const MIN_HEAD_HEIGHT := 1.10
const MAX_HEAD_HEIGHT := 2.40
const HEAD_CLEARANCE := 0.22
const FADE_DURATION := 0.50

const DEFAULT_FILL := Color(1.0, 1.0, 1.0, 1.0)
const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const BORDER_COLOR := Color(0.04, 0.055, 0.08, 0.85)
const TEXT_COLOR := Color(0.031, 0.039, 0.063, 1.0)

const SPEAKER_COLORS := {
	"default": Color("#FFFFFF"),
	"principal": Color("#F5F7FF"),
	"kai": Color("#FFF1BE"),
	"sarisa": Color("#FFDDF0"),
	"ogi": Color("#C6F3FF"),
	"elio": Color("#D6F7E2"),
	"fern": Color("#E8F7C8"),
	"dr_carlo": Color("#DAE7FF"),
	"ren": Color("#CCF6F4"),
	"dorn": Color("#FFE4C8"),
	"mira": Color("#EADBFF"),
	"ana": Color("#EEF0FF"),
	"vash": Color("#E2E8EE"),
}

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

	_card.set_content(text_str, color_for_speaker(speaker_name))
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


static func color_for_speaker(speaker_name: String) -> Color:
	var key := speaker_name.strip_edges().to_lower().replace(".", "").replace(" ", "_")
	if SPEAKER_COLORS.has(key):
		return SPEAKER_COLORS[key]
	return DEFAULT_FILL


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
	_card.set_tail_points(
		(placed["tail_base"] as Vector2) - box_rect.position,
		(placed["tail_tip"] as Vector2) - box_rect.position
	)
	_card.visible = true
	_check_autopilot_invariant(vp_rect, _last_placed_total, placed["tail_tip"] as Vector2)


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


func _check_autopilot_invariant(vp_rect: Rect2, total_rect: Rect2, tail_tip: Vector2) -> void:
	if not OS.has_environment("PSZ_AUTOPILOT"):
		return
	var eps := 2.0
	var inside := total_rect.position.x >= vp_rect.position.x - eps \
		and total_rect.position.y >= vp_rect.position.y - eps \
		and total_rect.end.x <= vp_rect.end.x + eps \
		and total_rect.end.y <= vp_rect.end.y + eps \
		and vp_rect.grow(eps).has_point(tail_tip)
	if not inside:
		push_error("[sanity] FAIL: speech bubble %s / tail %s escaped viewport %s" % [str(total_rect), str(tail_tip), str(vp_rect)])
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
## so trailing companions aim a directional bottom arrow instead of inverting across w < 0.
static func project_world_anchor(cam: Camera3D, world_pos: Vector3, vp_rect: Rect2) -> Dictionary:
	if cam == null:
		var center := vp_rect.position + Vector2(vp_rect.size.x * 0.5, vp_rect.size.y * 0.58)
		return {"anchor_px": center, "behind": false}
	var cam_local: Vector3 = cam.global_transform.affine_inverse() * world_pos
	if cam_local.z >= -0.2:
		var denom := maxf(absf(cam_local.z) + absf(cam_local.x), 0.001)
		var bearing := clampf(0.5 + (cam_local.x / denom) * 0.42, 0.14, 0.86)
		var pinned := Vector2(
			vp_rect.position.x + vp_rect.size.x * bearing,
			vp_rect.end.y + 36.0
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


## Pure squared-PSO screen-space placement + stretching/directional arrow solver.
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
	var half_slant := (h * SLANT_RATIO) * 0.5
	var left_b := vp_rect.position.x + SAFE_MARGIN_X + half_slant
	var right_b := maxf(left_b, vp_rect.end.x - SAFE_MARGIN_X - w - half_slant - BACKDROP_OFFSET.x)
	var top_b := vp_rect.position.y + SAFE_MARGIN_TOP
	var bottom_b := maxf(top_b, vp_rect.end.y - SAFE_MARGIN_BOTTOM - h - 42.0)

	var offscreen := behind_camera \
		or raw_anchor_px.x < vp_rect.position.x + 8.0 \
		or raw_anchor_px.x > vp_rect.end.x - 8.0 \
		or raw_anchor_px.y < vp_rect.position.y + 8.0 \
		or raw_anchor_px.y > vp_rect.end.y - 8.0

	var anchor_px := raw_anchor_px
	if behind_camera:
		anchor_px = Vector2(
			clampf(raw_anchor_px.x, vp_rect.position.x + vp_rect.size.x * 0.14, vp_rect.position.x + vp_rect.size.x * 0.86),
			vp_rect.end.y + 36.0
		)

	var ideal_x := anchor_px.x - w * 0.54
	var ideal_y := (vp_rect.end.y - SAFE_MARGIN_BOTTOM - h - 44.0) if behind_camera else (anchor_px.y - h - FLOAT_GAP)
	var bx := clampf(ideal_x, left_b, right_b)
	var by := clampf(ideal_y, top_b, bottom_b)
	var clamped_edge := absf(bx - ideal_x) > 0.5 or absf(by - ideal_y) > 0.5

	var shifted := _nudge_from_hud(
		Vector2(bx, by),
		Vector2(w, h),
		half_slant,
		Rect2(left_b, top_b, right_b - left_b, bottom_b - top_b),
		hud_rects
	)
	var nudged_hud: bool = shifted["nudged"]
	bx = shifted["pos"].x
	by = shifted["pos"].y

	var nudged_overlap := false
	for occ in occupied_rects:
		var footprint := Rect2(bx - half_slant, by, w + half_slant * 2.0, h + 16.0)
		if not footprint.intersects(occ):
			continue
		var up_y := occ.position.y - h - OVERLAP_GAP - 14.0
		var down_y := occ.end.y + OVERLAP_GAP
		if up_y >= top_b:
			by = up_y
		elif down_y <= bottom_b:
			by = down_y
		nudged_overlap = true

	var tail := _compute_tail_segment(vp_rect, Rect2(bx, by, w, h), half_slant, anchor_px, offscreen)
	var total_rect := Rect2(bx - half_slant, by, w + half_slant * 2.0 + BACKDROP_OFFSET.x, h + BACKDROP_OFFSET.y + 16.0)

	return {
		"box_rect": Rect2(bx, by, w, h),
		"total_rect": total_rect,
		"anchor_px": anchor_px,
		"tail_base": tail["base"],
		"tail_tip": tail["tip"],
		"offscreen": offscreen,
		"clamped_edge": clamped_edge,
		"nudged_hud": nudged_hud,
		"nudged_overlap": nudged_overlap,
	}


static func _compute_tail_segment(
	vp_rect: Rect2,
	box: Rect2,
	half_slant: float,
	anchor_px: Vector2,
	offscreen: bool
) -> Dictionary:
	var inset := maxf(6.0, CORNER_RADIUS) + TAIL_BASE_HALF_W + 4.0
	var min_bx := box.position.x - half_slant + inset
	var max_bx := maxf(min_bx, box.end.x - half_slant - inset)
	var blend_x := anchor_px.x * 0.35 + (box.position.x + box.size.x * 0.5 - half_slant) * 0.65
	var base := Vector2(clampf(blend_x, min_bx, max_bx), box.end.y)
	var tip := Vector2(anchor_px.x, maxf(box.end.y + 16.0, anchor_px.y - 8.0))
	if offscreen:
		tip = _clamp_reach(base, anchor_px, MAX_OFFSCREEN_TAIL)
		tip.x = clampf(tip.x, vp_rect.position.x + 10.0, vp_rect.end.x - 10.0)
		tip.y = clampf(tip.y, box.end.y + 14.0, vp_rect.end.y - 10.0)
	else:
		tip = _clamp_reach(base, tip, MAX_ONSCREEN_TAIL)
	return {"base": base, "tip": tip}


static func _clamp_reach(from_pt: Vector2, to_pt: Vector2, max_len: float) -> Vector2:
	var delta := to_pt - from_pt
	var dist := delta.length()
	if dist <= max_len or dist <= 0.001:
		return to_pt
	return from_pt + (delta / dist) * max_len


static func _nudge_from_hud(
	cur_pos: Vector2,
	box_size: Vector2,
	half_slant: float,
	bounds: Rect2,
	hud_rects: Array[Rect2]
) -> Dictionary:
	var pos := cur_pos
	var nudged := false
	var w := box_size.x
	var h := box_size.y
	for hud in hud_rects:
		var footprint := Rect2(pos.x - half_slant, pos.y, w + half_slant * 2.0, h + 18.0)
		if not footprint.intersects(hud):
			continue
		var candidates: Array[Vector2] = [
			Vector2(pos.x, hud.end.y + HUD_GAP),
			Vector2(pos.x, hud.position.y - h - 28.0 - HUD_GAP),
			Vector2(hud.end.x + HUD_GAP + half_slant, pos.y),
			Vector2(hud.position.x - w - HUD_GAP - half_slant, pos.y),
		]
		var best := pos
		var best_dist := INF
		for cand in candidates:
			if cand.x < bounds.position.x - 0.5 or cand.x > bounds.end.x + 0.5:
				continue
			if cand.y < bounds.position.y - 0.5 or cand.y > bounds.end.y + 0.5:
				continue
			var cand_fp := Rect2(cand.x - half_slant, cand.y, w + half_slant * 2.0, h + 18.0)
			if _intersects_any(cand_fp, hud_rects):
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
	var card_box_size := Vector2(MIN_WIDTH, 54.0)
	var fill_color := DEFAULT_FILL
	var _body_label: Label
	var _tail_base_local := Vector2(MIN_WIDTH * 0.5, 54.0)
	var _tail_tip_local := Vector2(MIN_WIDTH * 0.5, 90.0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body_label = Label.new()
		_body_label.name = "BodyLabel"
		_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body_label.add_theme_font_override("font", FONT_BOLD)
		_body_label.add_theme_font_size_override("font_size", FONT_SIZE)
		_body_label.add_theme_color_override("font_color", TEXT_COLOR)
		_body_label.add_theme_constant_override("line_spacing", LINE_SPACING)
		add_child(_body_label)

	func set_content(text_str: String, tint: Color) -> void:
		fill_color = tint
		var max_inner_w := MAX_WIDTH - PAD_X * 2.0
		var single_w := FONT_BOLD.get_multiline_string_size(
			text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE
		).x
		var inner_w := clampf(ceilf(minf(single_w, max_inner_w)) + 4.0, MIN_WIDTH - PAD_X * 2.0, max_inner_w)
		var body_metrics := FONT_BOLD.get_multiline_string_size(
			text_str,
			HORIZONTAL_ALIGNMENT_LEFT,
			inner_w,
			FONT_SIZE,
			-1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		)
		var body_h := maxf(FONT_BOLD.get_height(FONT_SIZE), ceilf(body_metrics.y))
		_body_label.text = text_str
		_body_label.position = Vector2(PAD_X, PAD_Y)
		_body_label.size = Vector2(inner_w, body_h)

		card_box_size = Vector2(inner_w + PAD_X * 2.0, PAD_Y * 2.0 + body_h)
		size = card_box_size
		queue_redraw()

	func set_tail_points(base_local: Vector2, tip_local: Vector2) -> void:
		if base_local.distance_to(_tail_base_local) <= 0.25 and tip_local.distance_to(_tail_tip_local) <= 0.25:
			return
		_tail_base_local = base_local
		_tail_tip_local = tip_local
		queue_redraw()

	func _draw() -> void:
		var poly := _build_squared_slant(Vector2.ZERO)
		var back_poly := _build_squared_slant(BACKDROP_OFFSET)
		draw_colored_polygon(back_poly, BACKDROP_COLOR)
		draw_colored_polygon(poly, fill_color)
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, BORDER_COLOR, BORDER_WIDTH, true)

	func _build_squared_slant(shift: Vector2) -> PackedVector2Array:
		var w := card_box_size.x
		var h := card_box_size.y
		var s := (h * SLANT_RATIO) * 0.5
		var c_tl := Vector2(s, 0.0) + shift
		var c_tr := Vector2(w + s, 0.0) + shift
		var c_br := Vector2(w - s, h) + shift
		var c_bl := Vector2(-s, h) + shift
		var r := minf(CORNER_RADIUS, minf(h * 0.42, w * 0.22))

		var inset := maxf(6.0, r) + TAIL_BASE_HALF_W + 3.0
		var min_tx := c_bl.x + inset
		var max_tx := maxf(min_tx, c_br.x - inset)
		var tx := clampf(_tail_base_local.x + shift.x, min_tx, max_tx)

		var pts := PackedVector2Array()
		_append_quad_corner(pts, _step_along(c_tl, c_bl, r), c_tl, _step_along(c_tl, c_tr, r))
		_append_quad_corner(pts, _step_along(c_tr, c_tl, r), c_tr, _step_along(c_tr, c_br, r))
		_append_quad_corner(pts, _step_along(c_br, c_tr, r), c_br, _step_along(c_br, c_bl, r))
		pts.append(Vector2(tx + TAIL_BASE_HALF_W, h + shift.y))
		pts.append(_tail_tip_local + shift)
		pts.append(Vector2(tx - TAIL_BASE_HALF_W, h + shift.y))
		_append_quad_corner(pts, _step_along(c_bl, c_br, r), c_bl, _step_along(c_bl, c_tl, r))
		return pts

	static func _step_along(from_pt: Vector2, to_pt: Vector2, dist: float) -> Vector2:
		var dir := to_pt - from_pt
		var seg_len := dir.length()
		if seg_len <= 0.001:
			return from_pt
		return from_pt + (dir / seg_len) * dist

	static func _append_quad_corner(pts: PackedVector2Array, p0: Vector2, ctrl: Vector2, p1: Vector2) -> void:
		const STEPS := 4
		for i in range(STEPS + 1):
			var t := float(i) / float(STEPS)
			var omt := 1.0 - t
			pts.append(p0 * (omt * omt) + ctrl * (2.0 * omt * t) + p1 * (t * t))
