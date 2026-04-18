extends DropBase
class_name QuestItemPickup
## Quest item pickup — collectible quest objective item.
## Walk over to auto-collect. Appears as a spinning gold star.
## States: available, collected (inherited from DropBase)

@export var quest_item_id: String = ""
@export var quest_item_label: String = ""
var pickup_dialog: Array = []  # [{speaker, text}, ...] shown after "Picked up X"
var pickup_actions: Array = []  # ["complete_quest", "telepipe"] run after dialog
var remaining_dialog: Array = []  # [{condition:{collected:N}, dialog:[...], actions:[...]}]
var companion_node: Node = null  # CompanionNpc for speech bubble routing


func _init() -> void:
	super._init()
	collision_size = Vector3(2.0, 2.0, 2.0)


func _apply_state() -> void:
	match element_state:
		"collected":
			visible = false
			set_process(false)
			interactable = false
			if interaction_area:
				interaction_area.set_deferred("monitoring", false)
				interaction_area.set_deferred("monitorable", false)
			if _prompt_label:
				_prompt_label.visible = false
			# Don't queue_free() here — dialog callbacks need this node alive.
			# Cleanup happens after the pickup dialog sequence completes.
		_:
			super._apply_state()


func _load_model() -> void:
	# Build a flat 6-pointed star (two overlapping triangles) — gold material
	var mesh_instance := MeshInstance3D.new()
	var arr_mesh := ArrayMesh.new()

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var radius := 0.5
	var inner := 0.2
	var thickness := 0.08

	# Build star points: 6 outer, 6 inner alternating
	var points: Array[Vector2] = []
	for i in range(12):
		var angle: float = (PI / 6.0) * i - PI / 2.0
		var r: float = radius if i % 2 == 0 else inner
		points.append(Vector2(cos(angle) * r, sin(angle) * r))

	# Top face
	var center_top := Vector3(0.0, thickness, 0.0)
	for i in range(12):
		var next: int = (i + 1) % 12
		verts.append(center_top)
		verts.append(Vector3(points[i].x, thickness, points[i].y))
		verts.append(Vector3(points[next].x, thickness, points[next].y))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		var base: int = i * 3
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)

	# Bottom face
	var offset: int = verts.size()
	var center_bot := Vector3(0.0, -thickness, 0.0)
	for i in range(12):
		var next: int = (i + 1) % 12
		verts.append(center_bot)
		verts.append(Vector3(points[next].x, -thickness, points[next].y))
		verts.append(Vector3(points[i].x, -thickness, points[i].y))
		normals.append(Vector3.DOWN)
		normals.append(Vector3.DOWN)
		normals.append(Vector3.DOWN)
		var base: int = offset + i * 3
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Gold material with emission
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy_multiplier = 0.5
	arr_mesh.surface_set_material(0, mat)

	mesh_instance.mesh = arr_mesh
	mesh_instance.position.y = 0.3
	model = Node3D.new()
	model.add_child(mesh_instance)
	add_child(model)


func _give_reward() -> bool:
	print("[QuestItem] Collected '%s' (%s)" % [quest_item_id, quest_item_label])
	_show_pickup_dialog()
	# Signal emitted AFTER pickup dialog so item_pickup triggers don't get overwritten
	return true


func _show_pickup_dialog() -> void:
	var label := quest_item_label if not quest_item_label.is_empty() else quest_item_id
	var hud: CanvasLayer = null
	for node in get_tree().get_nodes_in_group("hud"):
		hud = node as CanvasLayer
		break
	if not hud:
		# Find FieldHud by name
		hud = get_tree().root.find_child("FieldHud", true, false) as CanvasLayer
	if not hud:
		SessionManager.collect_quest_item(quest_item_id)
		queue_free()
		return

	var dialog_box := hud.get_node_or_null("DialogBox")
	if not dialog_box:
		var DialogBoxScript := preload("res://scripts/3d/ui/dialog_box.gd")
		dialog_box = DialogBoxScript.new()
		dialog_box.name = "DialogBox"
		hud.add_child(dialog_box)

	var item_id := quest_item_id
	var actions := pickup_actions
	var dlg := pickup_dialog
	var comp := companion_node
	var rem_dlg := remaining_dialog
	dialog_box.dialog_complete.connect(func() -> void:
		SessionManager.collect_quest_item(item_id)
		if not dlg.is_empty() and comp and is_instance_valid(comp) and comp.has_method("show_speech"):
			_show_companion_pages(comp, dlg, 0, func() -> void:
				_show_remaining_dialog(comp, rem_dlg, actions)
			)
		elif not rem_dlg.is_empty():
			_show_remaining_dialog(comp, rem_dlg, actions)
		else:
			_execute_pickup_actions(actions)
	, CONNECT_ONE_SHOT)
	dialog_box.show_dialog([{"speaker": "", "text": "Picked up %s." % label}])


func _show_companion_pages(comp: Node, pages: Array, index: int, on_complete: Variant = null) -> void:
	if index >= pages.size() or not is_instance_valid(comp):
		if on_complete is Callable:
			(on_complete as Callable).call()
		elif on_complete is Array:
			_execute_pickup_actions(on_complete as Array)
		else:
			queue_free()
		return
	var page: Dictionary = pages[index]
	var text: String = str(page.get("text", ""))
	var speaker: String = str(page.get("speaker", ""))
	var next_idx := index + 1
	# Empty speaker = narration — show in HUD dialog box instead of speech bubble
	if speaker.is_empty():
		var dialog_box := _find_dialog_box()
		if dialog_box:
			dialog_box.dialog_complete.connect(func() -> void:
				_show_companion_pages(comp, pages, next_idx, on_complete)
			, CONNECT_ONE_SHOT)
			dialog_box.show_dialog([{"speaker": "", "text": text}])
			return
	var duration: float = maxf(3.0, text.length() / 20.0)
	comp.show_speech(text, speaker, duration)
	comp.speech_finished.connect(func() -> void:
		_show_companion_pages(comp, pages, next_idx, on_complete)
	, CONNECT_ONE_SHOT)


func _show_remaining_dialog(comp: Node, rem_entries: Array, fallback_actions: Array) -> void:
	if rem_entries.is_empty():
		_execute_pickup_actions(fallback_actions)
		return

	# Count total collected quest items
	var total_collected: int = 0
	var objectives: Array = SessionManager.get_quest_objectives()
	var remaining_names: Array = []
	for obj in objectives:
		var oid: String = str(obj.get("item_id", ""))
		var target: int = int(obj.get("target", 1))
		var count: int = SessionManager.get_quest_item_count(oid)
		if count >= target:
			total_collected += 1
		else:
			remaining_names.append(str(obj.get("label", oid)))

	# Find matching entry
	var matched: Dictionary = {}
	for entry in rem_entries:
		var condition: Dictionary = entry.get("condition", {})
		var required: int = int(condition.get("collected", -1))
		if required == total_collected:
			matched = entry
			break

	if matched.is_empty():
		_execute_pickup_actions(fallback_actions)
		return

	# Resolve {remaining_items} token in dialog text
	var remaining_str: String = ""
	if remaining_names.size() == 1:
		remaining_str = remaining_names[0]
	elif remaining_names.size() == 2:
		remaining_str = "%s and %s" % [remaining_names[0], remaining_names[1]]
	elif remaining_names.size() > 2:
		remaining_str = ", ".join(remaining_names.slice(0, -1)) + ", and " + remaining_names[-1]

	var dlg: Array = matched.get("dialog", [])
	var resolved_dlg: Array = []
	for page in dlg:
		var text: String = str(page.get("text", "")).replace("{remaining_items}", remaining_str)
		resolved_dlg.append({"speaker": page.get("speaker", ""), "text": text})

	var entry_actions: Array = matched.get("actions", [])
	var final_actions: Array = entry_actions if not entry_actions.is_empty() else fallback_actions

	if not resolved_dlg.is_empty() and comp and is_instance_valid(comp) and comp.has_method("show_speech"):
		_show_companion_pages(comp, resolved_dlg, 0, final_actions)
	else:
		_execute_pickup_actions(final_actions)


func _execute_pickup_actions(actions: Array) -> void:
	if actions.is_empty():
		queue_free()
		return
	var objectives_met := SessionManager.are_objectives_complete()
	for action in actions:
		match str(action):
			"complete_quest":
				if not objectives_met:
					continue
				print("[QuestItem] Action: complete_quest")
				SfxManager.play("res://assets/sfx/ui/quest_complete.wav")
				SessionManager.complete_quest()
			"dismiss_companion":
				if companion_node and is_instance_valid(companion_node) and companion_node.has_method("dismiss"):
					print("[QuestItem] Action: dismiss_companion")
					companion_node.dismiss()
			"telepipe":
				if not objectives_met:
					continue
				print("[QuestItem] Action: spawning telepipe")
				var TelepipeScript := preload("res://scripts/3d/elements/telepipe.gd")
				var telepipe := TelepipeScript.new()
				telepipe.name = "Telepipe"
				get_parent().add_child(telepipe)
				telepipe.position = position
				var fc := _find_field_controller()
				if fc and fc.has_method("_on_end_reached"):
					telepipe.activated.connect(Callable(fc, "_on_end_reached"))
				else:
					telepipe.activated.connect(Callable(SceneManager, "goto_scene").bind("res://scenes/3d/city/city_warp.tscn"))
	queue_free()


func _find_dialog_box() -> Node:
	var hud: CanvasLayer = null
	for node in get_tree().get_nodes_in_group("hud"):
		hud = node as CanvasLayer
		break
	if not hud:
		hud = get_tree().root.find_child("FieldHud", true, false) as CanvasLayer
	if not hud:
		return null
	return hud.get_node_or_null("DialogBox")


func _find_field_controller() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("_on_end_reached"):
			return node
		node = node.get_parent()
	return null
