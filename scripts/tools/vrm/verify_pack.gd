extends SceneTree
## Run from an EMPTY --path so local assets cannot mask missing pack entries.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0], false):
		printerr("Pass the exported asset pack as the sole user argument")
		quit(1)
		return
	var failures := 0
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/player/vrm_conversion_report.json"))
	if not report is Dictionary or report.get("models", []).size() != 56:
		printerr("Missing complete conversion report in pack")
		quit(1)
		return
	for entry in report.models:
		var path := "res://" + str(entry.output)
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != entry.sha256:
			printerr("Missing or stale VRM in pack: " + path)
			failures += 1
	print("[vrm-pack] 56 raw VRMs checked against conversion hashes; failures=", failures)
	quit(1 if failures else 0)
