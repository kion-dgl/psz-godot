extends Node3D
## Player shadow probe (#648): the minimal dynamic-shadow setup — a clean
## receiving ground, the REAL player spawn path (FieldLab's SmoothNormals →
## make_lit), a steep sun with shadows on, and a control box that definitely
## casts. Which of the two casters shadows tells us where the player's
## dynamic shadow is lost.
##
## Env: PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit

const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

var _shot := FieldLabScript.ShotRun.new()


func _ready() -> void:
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	var hide_player := OS.get_environment("PROBE_HIDE_PLAYER") == "1"
	var built := FieldLabScript.build_environment(self)
	var env: Environment = built["env"]
	var sky_mat: ProceduralSkyMaterial = built["sky_mat"]
	var dir_light: DirectionalLight3D = built["dir_light"]
	var moonlight: DirectionalLight3D = built["moonlight"]
	FieldLabScript.apply_slot({"hour": 10.0, "sun_energy": 1.0, "sun_shadows": true},
		env, sky_mat, dir_light, moonlight)
	dir_light.rotation_degrees.x = -50.0
	var light_pos := OS.get_environment("PROBE_LIGHT_POS")
	if not light_pos.is_empty():
		var parts := light_pos.split(",")
		dir_light.position = Vector3(
			float(parts[0]), float(parts[1]), float(parts[2]))
		print("[ShadowProbe] light node at %s" % [dir_light.position])

	# Clean receiving ground — never casts
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.72, 0.66)
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# Control caster: a 3m pillar 2m beside the player
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 3, 1)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.6, 0.3, 0.2)
	box.mesh = bm
	box.material_override = bmat
	box.position = Vector3(2.5, 1.5, 0)
	add_child(box)

	FieldLabScript.spawn_player(self, Vector3(0, 1.2, 0))
	if hide_player:
		(player_node().get_node("PlayerModel") as Node3D).visible = false
	_dump(player_node())
	print("[ShadowProbe] player at origin, control pillar at +2.5x, sun −50° steep")


func player_node() -> Node:
	return get_tree().get_first_node_in_group("player")


func _dump(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var meshes := mi.mesh.get_surface_count() if mi.mesh else 0
		var flags := "cast=%s visible=%s" % [
			"OFF" if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "on",
			mi.visible]
		var extra := ""
		if mi.mesh:
			var b := mi.global_transform * mi.get_aabb()
			extra = " aabb=%s size=(%.2f,%.2f,%.2f)" % [b.position, b.size.x, b.size.y, b.size.z]
		print("  %s: %d surf  %s%s" % [mi.name, meshes, flags, extra])
	for c in node.get_children():
		_dump(c)


func _process(_delta: float) -> void:
	_shot.step(self, "ShadowProbe")
