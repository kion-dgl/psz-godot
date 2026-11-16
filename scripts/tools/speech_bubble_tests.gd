extends RefCounted
## Two-layer regression suite for #557 PSO-styled shared speech bubbles (spec /states/speech-bubbles):
##   1. Deterministic unit tests for PSO slanted/shout/thought tone shapes, solid black
##      offset backdrop, per-character pastel palette, AABB head-height resolution
##      (including 0.09x Principal scale and weapon exclusion), viewport clamping,
##      stretching pointer tail, off-screen/behind-camera directional arrow, HUD corner
##      clearance, and multi-bubble de-overlap.
##   2. Live 3D SubViewport + Camera3D + CompanionNpc + CityCounter + CityOffice probe.


static func run(runner: Node) -> void:
	print("── Speech Bubbles (#557) ──")
	_test_chrome_palette_and_tones(runner)
	_test_aabb_head_offset(runner)
	_test_projection_and_clamping(runner)
	_test_hud_avoidance_and_overlap(runner)


static func _test_chrome_palette_and_tones(runner: Node) -> void:
	runner.assert_eq(SpeechBubble.color_for_speaker("Kai"), Color("#FFF1BE"), "Kai resolves warm hunter gold-cream")
	runner.assert_eq(SpeechBubble.color_for_speaker("Sarisa"), Color("#FFDDF0"), "Sarisa resolves blossom pink")
	runner.assert_eq(SpeechBubble.color_for_speaker("Ogi"), Color("#C6F3FF"), "Ogi resolves PSO CAST ice cyan")
	runner.assert_eq(SpeechBubble.color_for_speaker("Dr. Carlo"), Color("#DAE7FF"), "Dr. Carlo normalizes punctuation to periwinkle")
	runner.assert_eq(SpeechBubble.color_for_speaker("Guild Counter"), Color("#FFFFFF"), "unnamed town NPC resolves PSO crisp white")

	var bubble := SpeechBubble.new()
	runner.add_child(bubble)
	var marker := Node3D.new()
	runner.add_child(marker)
	bubble.present(marker, "Short line.", 3.0, "Ogi", false)

	runner.assert_eq(bubble.layer, SpeechBubble.LAYER, "speech bubble renders on layer 40")
	runner.assert_true(bubble.is_active(), "present() activates speech bubble")
	runner.assert_eq(bubble.find_children("*", "SubViewport", true, false).size(), 0, "allocates zero SubViewports")
	runner.assert_eq(bubble.find_children("*", "Sprite3D", true, false).size(), 0, "allocates zero 3D billboard sprites")

	var card := bubble.get_card_control()
	var body_lbl := card.get_node("BodyLabel") as Label
	runner.assert_eq(body_lbl.get_theme_font("font"), SpeechBubble.FONT_BOLD, "body label uses bold JetBrainsMono")
	runner.assert_eq(card.get("fill_color"), Color("#C6F3FF"), "card stores Ogi pastel fill")
	runner.assert_true(card.size.x >= SpeechBubble.MIN_WIDTH - 0.5 and card.size.x < 240.0, "short line shrink-wraps cleanly")

	bubble.present(
		Vector3(0.0, 2.0, 0.0),
		"Please head to the Principal's office for your briefing right away before departing to Gurhacia Valley.",
		4.0,
		"Kai",
		false
	)
	runner.assert_eq(card.get("fill_color"), Color("#FFF1BE"), "card updates to Kai pastel fill")
	runner.assert_true(card.size.x <= SpeechBubble.MAX_WIDTH + 0.5 and card.size.y > 70.0, "long prose wraps into compact squared block within MAX_WIDTH")

	bubble.dismiss()
	runner.assert_true(not bubble.is_active(), "dismiss() deactivates bubble")
	marker.free()
	bubble.free()


static func _test_aabb_head_offset(runner: Node) -> void:
	var bare := Node3D.new()
	runner.add_child(bare)
	runner.assert_almost_eq(
		SpeechBubble.compute_head_offset_y(bare),
		SpeechBubble.DEFAULT_HEAD_HEIGHT + SpeechBubble.HEAD_CLEARANCE,
		0.01,
		"unmeshed actor falls back to DEFAULT_HEAD_HEIGHT + clearance"
	)
	bare.free()

	var principal := Node3D.new()
	principal.scale = Vector3(0.09, 0.09, 0.09)
	var p_mesh := MeshInstance3D.new()
	var p_box := BoxMesh.new()
	p_box.size = Vector3(6.0, 20.824, 6.0)
	p_mesh.mesh = p_box
	p_mesh.position = Vector3(0.0, 10.412, 0.0)
	principal.add_child(p_mesh)
	runner.add_child(principal)
	runner.assert_almost_eq(
		SpeechBubble.compute_head_offset_y(principal),
		1.874 + SpeechBubble.HEAD_CLEARANCE,
		0.02,
		"scaled 0.09x Principal resolves world head height ~2.09m"
	)
	principal.free()

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

	runner.assert_almost_eq(
		SpeechBubble.compute_head_offset_y(companion),
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

	# On-screen speaker: PSO bubble floats ~FLOAT_GAP above head and stretches tail down to speaker
	var center := SpeechBubble.compute_placement(vp_16_9, box_sz, Vector2(640.0, 420.0), false, no_hud, no_occ)
	var c_box: Rect2 = center["box_rect"]
	var c_tip: Vector2 = center["tail_tip"]
	runner.assert_true(not bool(center["clamped_edge"]), "centered speaker is not edge-clamped")
	runner.assert_true(not bool(center["offscreen"]), "centered speaker is on-screen")
	runner.assert_almost_eq(c_tip.x, 640.0, 1.0, "stretching tail tip X hits speaker head X")
	runner.assert_true(c_tip.y - c_box.end.y >= 60.0, "PSO bubble floats comfortably above head with long pointer tail")

	# Off-right speaker: box clamps inside safe margin, directional arrow points right toward off-screen speaker
	var right_edge := SpeechBubble.compute_placement(vp_16_9, box_sz, Vector2(1380.0, 380.0), false, no_hud, no_occ)
	var r_tot: Rect2 = right_edge["total_rect"]
	var r_base: Vector2 = right_edge["tail_base"]
	var r_tip: Vector2 = right_edge["tail_tip"]
	runner.assert_true(bool(right_edge["offscreen"]), "off-right speaker marks offscreen=true")
	runner.assert_true(r_tot.end.x <= 1280.0 - SpeechBubble.SAFE_MARGIN_X + 1.0, "slanted footprint + backdrop stay inside right safe margin")
	runner.assert_true(r_tip.x > r_base.x + 15.0, "directional arrow aims right toward off-screen speaker")

	# Behind-camera projection guard
	var cam := Camera3D.new()
	runner.add_child(cam)
	cam.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 5.0))
	var behind_proj := SpeechBubble.project_world_anchor(cam, Vector3(2.5, 2.0, 8.0), vp_16_9)
	runner.assert_true(bool(behind_proj["behind"]), "point behind camera near plane marks behind=true")
	var behind_placed := SpeechBubble.compute_placement(vp_16_9, box_sz, behind_proj["anchor_px"], true, no_hud, no_occ)
	var b_tip: Vector2 = behind_placed["tail_tip"]
	var b_base: Vector2 = behind_placed["tail_base"]
	runner.assert_true(b_tip.y > b_base.y + 12.0 and b_tip.y <= 710.0, "behind-camera directional arrow points down into bottom frame")
	cam.free()

	# 4:3 and 21:9 aspect presets
	for vp in [Rect2(0.0, 0.0, 1280.0, 960.0), Rect2(0.0, 0.0, 1680.0, 720.0)]:
		var edge := SpeechBubble.compute_placement(vp, box_sz, Vector2(vp.end.x + 90.0, -20.0), false, no_hud, no_occ)
		var tot: Rect2 = edge["total_rect"]
		runner.assert_true(
			tot.position.x >= vp.position.x + SpeechBubble.SAFE_MARGIN_X - 1.0
			and tot.end.x <= vp.end.x - SpeechBubble.SAFE_MARGIN_X + 1.0
			and tot.position.y >= vp.position.y + SpeechBubble.SAFE_MARGIN_TOP - 1.0,
			"aspect %dx%d clamps slanted footprint inside safe rect" % [int(vp.size.x), int(vp.size.y)]
		)


static func _test_hud_avoidance_and_overlap(runner: Node) -> void:
	var vp := Rect2(0.0, 0.0, 1280.0, 720.0)
	var box_sz := Vector2(260.0, 62.0)
	var field_huds := SpeechBubble.hud_exclusion_rects(vp, false)
	var no_occ: Array[Rect2] = []

	var corner_anchors := [
		Vector2(90.0, 140.0),
		Vector2(1200.0, 160.0),
		Vector2(1150.0, 715.0),
		Vector2(110.0, 715.0),
	]
	for anchor in corner_anchors:
		var res := SpeechBubble.compute_placement(vp, box_sz, anchor, false, field_huds, no_occ)
		var box: Rect2 = res["box_rect"]
		runner.assert_true(bool(res["nudged_hud"]), "HUD corner %s triggers HUD nudge" % str(anchor))
		var hits_hud := false
		for hz in field_huds:
			if box.intersects(hz):
				hits_hud = true
				break
		runner.assert_true(not hits_hud, "nudged bubble box at %s clears all field HUD rects" % str(anchor))

	var lower := SpeechBubble.compute_placement(vp, box_sz, Vector2(640.0, 460.0), false, field_huds, no_occ)
	var occ: Array[Rect2] = [lower["total_rect"]]
	var upper := SpeechBubble.compute_placement(vp, box_sz, Vector2(650.0, 445.0), false, field_huds, occ)
	var lower_box: Rect2 = lower["box_rect"]
	var upper_box: Rect2 = upper["box_rect"]
	runner.assert_true(bool(upper["nudged_overlap"]), "second nearby bubble flags nudged_overlap")
	runner.assert_true(not upper_box.intersects(lower_box), "de-overlapped bubbles do not intersect")


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
	var card := comp_bubble.get_card_control()
	runner.assert_eq(card.get("fill_color"), Color("#FFF1BE"), "live probe: Kai companion bubble uses Kai gold-cream tint")

	companion.global_position = Vector3(9.0, 0.0, 0.0)
	comp_bubble._process(0.05)
	var right_rect := comp_bubble.get_placed_rect()
	runner.assert_true(
		right_rect.end.x <= 1280.0 - SpeechBubble.SAFE_MARGIN_X + 1.5,
		"live probe: moving companion off-right clamps slanted footprint to safe margin"
	)

	companion.global_position = Vector3(-1.5, 0.0, 9.0)
	comp_bubble._process(0.05)
	var behind_rect := comp_bubble.get_placed_rect()
	runner.assert_true(
		behind_rect.end.y <= 720.0 - SpeechBubble.SAFE_MARGIN_BOTTOM + 1.5,
		"live probe: companion behind camera pins bubble inside bottom safe region"
	)

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
		not comp_bubble.get_card_control().get_rect().intersects(second_bubble.get_card_control().get_rect()),
		"live probe: two simultaneous speakers do not overlap on screen"
	)

	comp_bubble._process(0.30)
	var card := comp_bubble.get_card_control()
	runner.assert_true(card.modulate.a > 0.05 and card.modulate.a < 0.95, "live probe: bubble fades alpha during final 0.5s")

	comp_bubble._process(0.35)
	runner.assert_true(not comp_bubble.is_active(), "live probe: bubble deactivates on timer expiry")
	runner.assert_true(not bool(companion._speaking), "live probe: CompanionNpc clears _speaking on expiry")
	runner.assert_true(companion._name_label.visible, "live probe: CompanionNpc restores NameLabel on expiry")
	runner.assert_eq(finished_count[0], 1, "live probe: CompanionNpc emits speech_finished")
	second_bubble.dismiss()


static func _verify_office_and_counter_callers(runner: Node) -> void:
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
	runner.assert_eq(counter.find_children("*", "SubViewport", true, false).size(), 0, "counter creates zero SubViewports")
	if not counter_bubbles.is_empty():
		(counter_bubbles[0] as SpeechBubble).dismiss()
	clerk.free()
	counter.free()
	SceneManager._transition_data = {}

	SessionManager.accept_quest("search_and_rescue", "normal")
	CityState.clear()
	var office: Node3D = (load("res://scenes/3d/city/city_office.tscn") as PackedScene).instantiate()
	runner.add_child(office)
	await runner.get_tree().process_frame
	if not office._briefing_active and not office._briefing_pages.is_empty():
		office._play_briefing_dialog()
	runner.assert_true(office._briefing_bubble != null and office._briefing_bubble.is_active(), "office briefing activates shared SpeechBubble")
	runner.assert_eq(office.find_children("*", "SubViewport", true, false).size(), 0, "office creates zero SubViewports")
	var guard := 0
	while office._briefing_active and guard < 20:
		office._advance_briefing()
		guard += 1
	runner.assert_true(not office._briefing_active, "office briefing advances cleanly to completion")
	runner.assert_true(bool(SessionManager.get_accepted_quest().get("briefing_shown", false)), "office briefing marks briefing_shown=true")
	runner.assert_true(not office._briefing_bubble.is_active(), "office briefing dismisses SpeechBubble on completion")
	office.free()
	SessionManager.reset_all_state()
