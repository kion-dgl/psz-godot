extends SceneTree
## Reproduce with -- <repo>/assets/enemies/boss_robot_paru.
## Preserve the original Paru rig, including the animated put02 drill joint.
func _initialize() -> void:
	quit(preload("res://scripts/tools/boss_clip_export.gd").run(OS.get_cmdline_user_args(),["z_003u","z_003n"],"","paru_"))
