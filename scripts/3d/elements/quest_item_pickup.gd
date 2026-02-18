extends DropBase
class_name QuestItemPickup
## Quest item pickup — collectible quest objective item.
## Walk over to auto-collect. Appears as a spinning gold star.
## States: available, collected (inherited from DropBase)

@export var quest_item_id: String = ""
@export var quest_item_label: String = ""


func _init() -> void:
	super._init()
	collision_size = Vector3(2.0, 2.0, 2.0)


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


func _give_reward() -> void:
	SessionManager.collect_quest_item(quest_item_id)
	print("[QuestItem] Collected '%s' (%s)" % [quest_item_id, quest_item_label])
	_show_pickup_dialog()


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
		return

	var dialog_box := hud.get_node_or_null("DialogBox")
	if not dialog_box:
		var DialogBoxScript := preload("res://scripts/3d/ui/dialog_box.gd")
		dialog_box = DialogBoxScript.new()
		dialog_box.name = "DialogBox"
		hud.add_child(dialog_box)

	dialog_box.show_dialog([{"speaker": "", "text": "Picked up %s." % label}])
