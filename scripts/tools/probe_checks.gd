extends Node
## Shared assertion reporting for live probes that survive scene changes.
var _ok := true
var probe_label := "probe"

func _check(condition: bool, message: String) -> void:
	_ok = condition and _ok
	print("[%s] %s: %s" % [probe_label, "PASS" if condition else "FAIL", message])

func _ready() -> void:
	var pack := OS.get_environment("PSZ_PROBE_PACK")
	if not pack.is_empty() and not ProjectSettings.load_resource_pack(pack, false):
		get_tree().quit(1)
		return
	call_deferred("_run")

func _snapshot_boss(label: String, boss: DescriptorBoss) -> void:
	var folder := OS.get_environment("PSZ_BOSS_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	var camera := Camera3D.new()
	get_tree().root.add_child(camera)
	camera.global_position = boss.global_position + Vector3(24,18,32)
	camera.look_at(boss.global_position+Vector3.UP*3,Vector3.UP)
	camera.current = true
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"))
	camera.queue_free()

func _snapshot(label: String) -> void:
	var folder := OS.get_environment("PSZ_BOSS_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))
