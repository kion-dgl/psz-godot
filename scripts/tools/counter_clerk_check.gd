extends Node3D
## Counter clerk PoC smoke — the Meshy clerks (storage_clerk/guild_clerk,
## mixamorig:* rigs) are placed un-animated for a look test. This verifies
## through the real CityCounter scene that both models load with a skeleton
## and land intentionally idle-less (no NPCAnimPlayer — idle_anim is ""),
## the Coliseum Master's PSZ idle still binds, and the storage-close /
## quest-accept reaction one-shots no-op safely (play_oneshot early-returns
## without an idle player).
##
## Run: godot --headless --path . res://scenes/tools/counter_clerk_check.tscn
##
## Env:  PSZ_CLERK_CHECK_SHOT=/tmp/prefix  windowed run: capture <prefix>_
##      storage.png / _guild.png in place behind the counter.

const CounterScene := preload("res://scenes/3d/city/city_counter.tscn")

const CLERKS := {
	"StorageNPC": "storage",
	"QuestCounterNPC": "guild",
}

var _fails: Array[String] = []
var _scene: Node


func _ready() -> void:
	var scene := CounterScene.instantiate()
	add_child(scene)
	_scene = scene
	# Let _ready chains (player spawn, NPC models, idle players) settle.
	for i in 3:
		await get_tree().process_frame

	var controller := scene as Node
	for npc_name in CLERKS:
		_check_model_placed(npc_name)
	_check_idle("ColiseumMasterNPC", "pso_ro_stand")

	# Reactions must no-op safely while the clerks ship un-animated.
	controller.call("_play_npc_reaction", "StorageNPC", "plymotiondata_421")
	var guild := _find_npc("QuestCounterNPC")
	if guild:
		guild.call("play_oneshot", "pso_f_emote_bow")
	await get_tree().process_frame
	for npc_name in CLERKS:
		var npc := _find_npc(npc_name)
		if npc and _find_typed(npc, "NPCAnimPlayer"):
			_fails.append("%s has an NPCAnimPlayer — idle_anim should be empty in the PoC" % npc_name)

	# VRM pipeline test NPC — committed example VRoid model, always present.
	var vrm_npc := _find_npc("VrmTestNPC")
	if vrm_npc:
		_check_playing("VrmTestNPC", "pso_f_sa_stand_vex")
	else:
		_fails.append("VrmTestNPC not found in counter scene")

	if _fails.is_empty():
		print("[check] counter_clerk PASS — Meshy clerks placed idle-less, reactions no-op")
	else:
		for f in _fails:
			print("[check] FAIL: " + f)

	var shot_prefix := OS.get_environment("PSZ_CLERK_CHECK_SHOT")
	if not shot_prefix.is_empty():
		await _capture_shots(shot_prefix)
		print("[check] shots written with prefix " + shot_prefix)
		get_tree().quit(1 if not _fails.is_empty() else 0)
		return
	get_tree().quit(1 if not _fails.is_empty() else 0)


## Windowed-only: frame each clerk in turn through a temporary camera and
## capture the editor-imported model standing in place (bind pose).
func _capture_shots(prefix: String) -> void:
	for npc_name in CLERKS:
		await _shot_npc(npc_name, "%s_%s.png" % [prefix, CLERKS[npc_name]])
	if _find_npc("VrmTestNPC"):
		await _shot_npc("VrmTestNPC", prefix + "_vrm.png")


func _shot_npc(npc_name: String, path: String) -> void:
	var npc := _find_npc(npc_name) as Node3D
	if not npc:
		return
	# The NPC's model child carries the facing rotation; the clerk stands at
	# the node origin. Camera sits on the facing axis, head height.
	var model := npc.get("model") as Node3D
	var facing := Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.global_position = npc.global_position + facing * 2.4 + Vector3.UP * 1.15
	cam.look_at(npc.global_position + Vector3.UP * 0.95, Vector3.UP)
	cam.make_current()
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	add_child(fill)
	fill.rotation_degrees = Vector3(-30, -35, 0)
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[check] shot " + path)
	cam.queue_free()
	fill.queue_free()


func _find_npc(npc_name: String) -> Node:
	var all: Array = []
	_collect(_scene, all)
	for n in all:
		if n.name == npc_name:
			return n
	return null


func _collect(node: Node, out: Array) -> void:
	out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _check_model_placed(npc_name: String) -> void:
	var npc := _find_npc(npc_name)
	if not npc:
		_fails.append("%s not found in counter scene" % npc_name)
		return
	var model := npc.get("model") as Node
	if not model:
		_fails.append("%s has no model loaded" % npc_name)
		return
	var skel := _find_typed(model, "Skeleton3D")
	if not skel:
		_fails.append("%s model has no Skeleton3D" % npc_name)
		return
	print("[check] %s: model placed, skeleton ok, intentionally no idle" % npc_name)


func _check_idle(npc_name: String, expected: String) -> void:
	var npc := _find_npc(npc_name)
	if not npc:
		_fails.append("%s not found in counter scene" % npc_name)
		return
	if not npc.get("model"):
		_fails.append("%s has no model loaded" % npc_name)
		return
	_check_playing(npc_name, expected)


func _check_playing(npc_name: String, expected: String) -> void:
	var npc := _find_npc(npc_name)
	# NPCAnimPlayer lives under the model's skeleton parent — find it generically.
	var player := _find_typed(npc, "NPCAnimPlayer") as AnimationPlayer
	if not player:
		_fails.append("%s has no NPCAnimPlayer (idle never bound)" % npc_name)
		return
	if player.current_animation != expected:
		_fails.append("%s playing '%s', expected '%s'" % [npc_name, player.current_animation, expected])
		return
	var anim := player.get_animation(expected)
	var skel: Skeleton3D = _find_typed(npc.get("model"), "Skeleton3D") as Skeleton3D
	var dump := OS.get_environment("PSZ_CLERK_CHECK_DUMP") == "1"
	var missing := 0
	for i in range(anim.get_track_count()):
		# Imported bone tracks are NodePaths shaped Skeleton3D:mixamorig_Hips —
		# the LAST subname selects the bone (get_subname, not string surgery).
		var np := anim.track_get_path(i)
		var bone := String(np.get_subname(np.get_subname_count() - 1)) if np.get_subname_count() > 0 else ""
		if dump:
			print("[check]   track %d: %s -> bone '%s'" % [i, np, bone])
		if skel.find_bone(bone) == -1:
			missing += 1
			_fails.append("%s track bone '%s' missing on skeleton" % [expected, bone])
	if missing == 0:
		print("[check] %s: %s ok (%d tracks, all bones resolve)" % [npc_name, expected, anim.get_track_count()])


func _find_typed(root: Node, name_or_class: String) -> Node:
	if root.name == name_or_class or root.get_class() == name_or_class:
		return root
	for child in root.get_children():
		var found := _find_typed(child, name_or_class)
		if found:
			return found
	return null
