extends RefCounted
## Two-layer regression suite for #557 shared speech bubbles (spec /states/speech-bubbles):
##   1. Deterministic unit tests for typography, zero-SubViewport chrome, AABB head-height
##      resolution (including 0.09x Principal scale and weapon exclusion), viewport clamping,
##      behind-camera pinning, HUD corner clearance, and multi-bubble de-overlap.
##   2. Live 3D SubViewport + Camera3D + CompanionNpc frame probe exercising real-time
##      projection tracking, simultaneous speaker de-overlap, 0.5s fade-out, and signals.


static func run(runner: Node) -> void:
	print("── Speech Bubbles (#557) ──")
	_test_chrome_and_typography(runner)
	_test_aabb_head_offset(runner)
	_test_projection_and_clamping(runner)
	_test_hud_avoidance_and_overlap(runner)


static func _test_chrome_and_typography(runner: Node) -> void:
	var bubble := SpeechBubble.new()
	runner.add_child(bubble)
	var marker := Node3D.new()
	runner.add_child(marker)
	bubble.present(marker, "Short line.", 3.0, "Principal", false)

	runner.assert_eq(bubble.layer, SpeechBubble.LAYER, "speech bubble renders on layer 40")
	runner.assert_true(bubble.is_active(), "present() activates speech bubble")
	runner.assert_eq(
		bubble.find_children("*", "SubViewport", true, false).size(),
		0,
		"shared SpeechBubble allocates zero SubViewports"
	)
	runner.assert_eq(
		bubble.find_children("*", "Sprite3D", true, false).size(),
		0,
		"shared SpeechBubble allocates zero 3D billboard sprites"
	)

	var card := bubble.get_card_control()
	var speaker_lbl := card.get_node("SpeakerLabel") as Label
	var body_lbl := card.get_node("BodyLabel") as Label
	runner.assert_true(speaker_lbl.visible and speaker_lbl.text == "Principal", "speaker header visible when provided")
	runner.assert_eq(
		speaker_lbl.get_theme_font("font"),
		SpeechBubble.FONT_BOLD,
		"speaker header uses JetBrainsMono-Bold"
	)
	runner.assert_eq(
		body_lbl.get_theme_font("font"),
		SpeechBubble.FONT_REGULAR,
		"body label uses JetBrainsMono-Regular"
	)
	var short_w := card.size.x
	runner.assert_true(
		short_w >= SpeechBubble.MIN_WIDTH - 0.5 and short_w < 240.0,
		"short callout shrink-wraps instead of filling a 400px box"
	)

	bubble.present(
		Vector3(0.0, 2.0, 0.0),
		"Please head to the Principal's office for your briefing right away before departing to Gurhacia Valley.",
		4.0,
		"",
		false
	)
	runner.assert_true(not speaker_lbl.visible, "speaker header hides when speaker is empty")
	runner.assert_true(
		card.size.x <= SpeechBubble.MAX_WIDTH + 0.5 and card.size.y > 55.0,
		"long prose wraps within MAX_WIDTH"
	)

	bubble.dismiss()
	runner.assert_true(not bubble.is_active(), "dismiss() deactivates bubble")
	marker.free()
	bubble.free()


static func _test_aabb_head_offset(runner: Node) -> void:
	# 1. Unmeshed actor (repo-only CI fallback)
	var bare := Node3D.new()
	runner.add_child(bare)
	runner.assert_almost_eq(
		SpeechBubble.compute_head_offset_y(bare),
		SpeechBubble.DEFAULT_HEAD_HEIGHT + SpeechBubble.HEAD_CLEARANCE,
		0.01,
		"unmeshed actor falls back to DEFAULT_HEAD_HEIGHT + clearance"
	)
	bare.free()

	# 2. Scaled Principal actor (raw mesh 20.824 units tall * 0.09 scale = 1.874m)
	var principal := Node3D.new()
	principal.scale = Vector3(0.09, 0.09, 0.09)
	var p_mesh := MeshInstance3D.new()
	var p_box := BoxMesh.new()
	p_box.size = Vector3(6.0, 20.824, 6.0)
	p_mesh.mesh = p_box
	p_mesh.position = Vector3(0.0, 10.412, 0.0)
	principal.add_child(p_mesh)
	runner.add_child(principal)
	var p_offset := SpeechBubble.compute_head_offset_y(principal)
	runner.assert_almost_eq(p_offset, 1.874 + SpeechBubble.HEAD_CLEARANCE, 0.02, "scaled 0.09x Principal resolves world head height ~2.09m")
	principal.free()

	# 3. Capsule 1.4m actor + tall held weapon attachment (weapon must be ignored)
	var companion := Node3D.new()
	var cap_mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.4
	cap_mi.mesh = cap
	cap_mi.position = Vector3(0.0, 0.7, 0.0)
	companion.add_child(cap_mi)

	var weapon_attach := BoneAttachment3D.new()
	weapon_attach.name = "WeaponAttachment_R"
	var tall_blade := MeshInstance3D.new()
	var blade_box := BoxMesh.new()
	blade_box.size = Vector3(0.2, 4.0, 0.2)
	tall_blade.mesh = blade_box
	tall_blade.position = Vector3(0.0, 3.0, 0.0)
	weapon_attach.add_child(tall_blade)
	companion.add_child(weapon_attach)
	runner.add_child(companion)

	var c_offset := SpeechBubble.compute_head_offset_y(companion)
	runner.assert_almost_eq(
		c_offset,
		1.4 + SpeechBubble.HEAD_CLEARANCE,
		0.02,
		"WeaponAttachment_R subtree does not inflate head anchor height"
	)
	companion.free()


static func _test_projection_and_clamping(runner: Node) -> void:
	var vp_16_9 := Rect2(0.0, 0.0, 1280.0, 720.0)
	var box_sz := Vector2(280.0, 64.0)
	var no_hud: Array[Rect2] = []
	var no_occ: Array[Rect2] = []

	# Centered anchor
	var center := SpeechBubble.compute_placement(vp_16_9, box_sz, Vector2(640.0, 400.0), false, no_hud, no_occ)
	var c_box: Rect2 = center["box_rect"]
	runner.assert_true(not bool(center["clamped_edge"]), "centered speaker is not edge-clamped")
	runner.assert_almost_eq(c_box.position.x, 500.0, 0.5, "centered box horizontally straddles anchor")
	runner.assert_almost_eq(float(center["tail_local_x"]), 140.0, 0.5, "centered tail sits at midpoint")

	# Off-left and off-right anchors clamp box while sliding tail
	var left_edge := SpeechBubble.compute_placement(vp_16_9, box_sz, Vector2(-35.0, 360.0), false, no_hud, no_occ)
	var l_box: Rect2 = left_edge["box_rect"]
	runner.assert_true(bool(left_edge["clamped_edge"]), "off-left speaker flags clamped_edge")
	runner.assert_almost_eq(l_box.position.x, SpeechBubble.SAFE_MARGIN_X, 0.5, "off-left box clamps to SAFE_MARGIN_X")
	runner.assert_true(float(left_edge["tail_tip_local_x"]) < 40.0, "off-left tail slides to left side of card")

	var right_edge := SpeechBubble.compute_placement(vp_16_9, box_sz, Vector2(1340.0, 360.0), false, no_hud, no_occ)
	var r_box: Rect2 = right_edge["box_rect"]
	runner.assert_almost_eq(r_box.end.x, 1280.0 - SpeechBubble.SAFE_MARGIN_X, 0.5, "off-right box clamps to right safe margin")
	runner.assert_true(float(right_edge["tail_tip_local_x"]) > box_sz.x - 40.0, "off-right tail slides to right side of card")

	# Behind-camera projection guard
	var cam := Camera3D.new()
	runner.add_child(cam)
	cam.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 5.0))
	var behind_proj := SpeechBubble.project_world_anchor(cam, Vector3(2.5, 2.0, 8.0), vp_16_9)
	runner.assert_true(bool(behind_proj["behind"]), "point behind camera near plane marks behind=true")
	var behind_px: Vector2 = behind_proj["anchor_px"]
	runner.assert_almost_eq(behind_px.y, 720.0 - SpeechBubble.SAFE_MARGIN_BOTTOM, 0.5, "behind-camera anchor pins to bottom safe edge")
	runner.assert_true(behind_px.x > 640.0, "behind-camera anchor preserves speaker's right-hand bearing")
	cam.free()

	# 4:3 and 21:9 aspect presets
	for vp in [Rect2(0.0, 0.0, 1280.0, 960.0), Rect2(0.0, 0.0, 1680.0, 720.0)]:
		var edge := SpeechBubble.compute_placement(vp, box_sz, Vector2(vp.end.x + 80.0, -20.0), false, no_hud, no_occ)
		var tot: Rect2 = edge["total_rect"]
		runner.assert_true(
			tot.position.x >= vp.position.x + SpeechBubble.SAFE_MARGIN_X - 0.5
			and tot.end.x <= vp.end.x - SpeechBubble.SAFE_MARGIN_X + 0.5
			and tot.position.y >= vp.position.y + SpeechBubble.SAFE_MARGIN_TOP - 0.5,
			"aspect %dx%d clamps extreme corner inside safe rect" % [int(vp.size.x), int(vp.size.y)]
		)


static func _test_hud_avoidance_and_overlap(runner: Node) -> void:
	var vp := Rect2(0.0, 0.0, 1280.0, 720.0)
	var box_sz := Vector2(260.0, 62.0)
	var field_huds := SpeechBubble.hud_exclusion_rects(vp, false)
	var no_occ: Array[Rect2] = []

	# Test all 4 field HUD corners: HudStats, RoomMinimap, ActionPalette, TargetInfo
	var corner_anchors := [
		Vector2(90.0, 110.0),
		Vector2(1200.0, 130.0),
		Vector2(1160.0, 690.0),
		Vector2(110.0, 690.0),
	]
	for anchor in corner_anchors:
		var res := SpeechBubble.compute_placement(vp, box_sz, anchor, false, field_huds, no_occ)
		var tot: Rect2 = res["total_rect"]
		runner.assert_true(bool(res["nudged_hud"]), "HUD corner %s triggers HUD nudge" % str(anchor))
		var hits_hud := false
		for hz in field_huds:
			if tot.intersects(hz):
				hits_hud = true
				break
		runner.assert_true(not hits_hud, "nudged bubble at %s clears all field HUD rects" % str(anchor))

	# Two simultaneous overlapping speakers
	var lower := SpeechBubble.compute_placement(vp, box_sz, Vector2(640.0, 430.0), false, field_huds, no_occ)
	var occ: Array[Rect2] = [lower["total_rect"]]
	var upper := SpeechBubble.compute_placement(vp, box_sz, Vector2(650.0, 415.0), false, field_huds, occ)
	var lower_tot: Rect2 = lower["total_rect"]
	var upper_tot: Rect2 = upper["total_rect"]
	runner.assert_true(bool(upper["nudged_overlap"]), "second nearby bubble flags nudged_overlap")
	runner.assert_true(not upper_tot.intersects(lower_tot), "de-overlapped bubbles do not intersect")
	runner.assert_true(lower_tot.position.y - upper_tot.end.y >= SpeechBubble.OVERLAP_GAP - 0.5, "de-overlapped bubbles keep >= 8px gap")


static func run_live_probe(runner: Node) -> void:
	print("── Speech Bubbles Live 3D Projection Probe (#557) ──")
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	runner.add_child(vp)

	var cam := Camera3D.new()
	cam.fov = 44.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.2, 6.0), Vector3(0.0, 1.4, 0.0), Vector3.UP)
	cam.current = true

	var CompanionScript := preload("res://scripts/3d/elements/companion_npc.gd")
	var companion: CharacterBody3D = CompanionScript.new()
	companion.companion_id = "kai"
	vp.add_child(companion)
	companion.global_position = Vector3(0.0, 0.0, 0.0)

	var started_count := [0]
	var finished_count := [0]
	companion.speech_started.connect(func() -> void: started_count[0] += 1)
	companion.speech_finished.connect(func() -> void: finished_count[0] += 1)

	await runner.get_tree().process_frame
	companion.show_speech("Stay sharp — hostiles ahead!", "Kai", 0.65)
	await runner.get_tree().process_frame

	runner.assert_eq(started_count[0], 1, "live probe: CompanionNpc emits speech_started")
	runner.assert_true(bool(companion._speaking), "live probe: CompanionNpc sets _speaking")
	runner.assert_true(not companion._name_label.visible, "live probe: CompanionNpc hides NameLabel while speaking")

	var comp_bubble: SpeechBubble = companion._speech_bubble
	var center_rect := comp_bubble.get_placed_rect()
	runner.assert_true(center_rect.size.x >= SpeechBubble.MIN_WIDTH, "live probe: placed rect populated")
	runner.assert_almost_eq(center_rect.get_center().x, 640.0, 24.0, "live probe: centered companion projects to viewport center")

	# Move companion far right off-frame and verify live clamping
	companion.global_position = Vector3(9.0, 0.0, 0.0)
	comp_bubble._process(0.05)
	var right_rect := comp_bubble.get_placed_rect()
	runner.assert_almost_eq(
		right_rect.end.x,
		1280.0 - SpeechBubble.SAFE_MARGIN_X,
		1.0,
		"live probe: moving companion off-right clamps bubble to right safe margin"
	)

	# Move companion behind camera and verify bottom safe-edge pin
	companion.global_position = Vector3(-1.5, 0.0, 9.0)
	comp_bubble._process(0.05)
	var behind_rect := comp_bubble.get_placed_rect()
	runner.assert_almost_eq(
		behind_rect.end.y,
		720.0 - SpeechBubble.SAFE_MARGIN_BOTTOM,
		1.0,
		"live probe: companion behind camera pins bubble to bottom safe edge"
	)

	# Spawn simultaneous second speaker near center and verify live de-overlap
	_verify_live_overlap_and_expiry(runner, vp, companion, comp_bubble, finished_count)
	vp.free()
	await _verify_office_and_counter_callers(runner)


static func _verify_live_overlap_and_expiry(
	runner: Node,
	vp: SubViewport,
	companion: CharacterBody3D,
	comp_bubble: SpeechBubble,
	finished_count: Array
) -> void:
	companion.global_position = Vector3(0.0, 0.0, 0.0)
	var second_actor := Node3D.new()
	vp.add_child(second_actor)
	second_actor.global_position = Vector3(0.15, 0.1, 0.0)
	var second_bubble := SpeechBubble.spawn(vp, second_actor, "Right behind you!", 2.0, "Sarisa", false)
	comp_bubble._process(0.01)
	second_bubble._process(0.01)
	runner.assert_true(
		not comp_bubble.get_placed_rect().intersects(second_bubble.get_placed_rect()),
		"live probe: two simultaneous speakers do not overlap on screen"
	)

	comp_bubble._process(0.30)  # remaining ~0.23s (< 0.5s fade window)
	var card := comp_bubble.get_card_control()
	runner.assert_true(card.modulate.a > 0.05 and card.modulate.a < 0.95, "live probe: bubble fades alpha during final 0.5s")

	comp_bubble._process(0.35)  # expires
	runner.assert_true(not comp_bubble.is_active(), "live probe: bubble deactivates on timer expiry")
	runner.assert_true(not bool(companion._speaking), "live probe: CompanionNpc clears _speaking on expiry")
	runner.assert_true(companion._name_label.visible, "live probe: CompanionNpc restores NameLabel on expiry")
	runner.assert_eq(finished_count[0], 1, "live probe: CompanionNpc emits speech_finished")
	second_bubble.dismiss()


static func _verify_office_and_counter_callers(runner: Node) -> void:
	# 1. Counter quest-accept reaction spawns shared SpeechBubble
	var CounterScript := preload("res://scripts/3d/city/city_counter_controller.gd")
	var counter := Node3D.new()
	counter.set_script(CounterScript)
	var clerk := CityNPC.new()
	clerk.name = "QuestCounterNPC"
	clerk.position = Vector3(-7.86, -10.67, 111.39)
	runner.add_child(clerk)
	counter._npcs.append(clerk)
	SceneManager._transition_data = {"quest_accepted": true}
	counter._check_quest_accepted()
	var counter_bubbles := counter.find_children("*", "SpeechBubble", false, false)
	runner.assert_eq(counter_bubbles.size(), 1, "counter quest-accept spawns shared SpeechBubble")
	runner.assert_eq(
		counter.find_children("*", "SubViewport", true, false).size(),
		0,
		"counter quest-accept creates zero SubViewports"
	)
	if not counter_bubbles.is_empty():
		(counter_bubbles[0] as SpeechBubble).dismiss()
	clerk.free()
	counter.free()
	SceneManager._transition_data = {}

	# 2. Principal's Office multi-page briefing uses shared SpeechBubble
	SessionManager.accept_quest("search_and_rescue", "normal")
	CityState.clear()
	var office: Node3D = (load("res://scenes/3d/city/city_office.tscn") as PackedScene).instantiate()
	runner.add_child(office)
	await runner.get_tree().process_frame
	if not office._briefing_active and not office._briefing_pages.is_empty():
		office._play_briefing_dialog()
	runner.assert_true(office._briefing_bubble != null and office._briefing_bubble.is_active(), "office briefing activates shared SpeechBubble")
	runner.assert_eq(
		office.find_children("*", "SubViewport", true, false).size(),
		0,
		"office briefing creates zero SubViewports"
	)
	var guard := 0
	while office._briefing_active and guard < 20:
		office._advance_briefing()
		guard += 1
	runner.assert_true(not office._briefing_active, "office briefing advances cleanly to completion")
	runner.assert_true(bool(SessionManager.get_accepted_quest().get("briefing_shown", false)), "office briefing marks briefing_shown=true")
	runner.assert_true(not office._briefing_bubble.is_active(), "office briefing dismisses SpeechBubble on completion")
	office.free()
	SessionManager.reset_all_state()
