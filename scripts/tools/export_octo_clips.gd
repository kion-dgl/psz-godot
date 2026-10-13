extends SceneTree
## Reproduce with -- <asset-viewer/public/enemies/boss_octopus>.
## Meshes stay in the existing pack; corrected small clip libraries ship in app.
func _initialize() -> void:
	quit(preload("res://scripts/tools/boss_clip_export.gd").run(OS.get_cmdline_user_args(),["z_002_tt","z_002_st"],"parts",""))
