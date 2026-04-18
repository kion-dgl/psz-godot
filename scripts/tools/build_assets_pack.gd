@tool
extends SceneTree
## Headless tool that packages `res://assets/` into a Godot .pck file and prints
## the output's sha256 and size so the publish pipeline can update the manifest.
##
## Usage:
##     godot --headless --script scripts/tools/build_assets_pack.gd -- \
##         --out dist/assets.pck
##
## Without --out, writes to res://dist/assets.pck.

const DEFAULT_OUT := "res://dist/assets.pck"


func _init() -> void:
	var args := _parse_args()
	var out_path: String = args.get("out", DEFAULT_OUT)
	var abs_out: String
	if out_path.begins_with("res://"):
		abs_out = ProjectSettings.globalize_path(out_path)
	elif out_path.is_absolute_path():
		abs_out = out_path
	else:
		# Resolve relative paths against the project directory so
		# make_dir_recursive_absolute and pck_start get a real absolute path.
		abs_out = ProjectSettings.globalize_path("res://").path_join(out_path)

	print("[pack] output: ", abs_out)

	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())

	var packer := PCKPacker.new()
	var err := packer.pck_start(abs_out)
	if err != OK:
		push_error("[pack] pck_start failed: %s" % error_string(err))
		quit(1)
		return

	var added: int = _add_tree(packer, "res://assets")
	print("[pack] files added: ", added)

	err = packer.flush(true)
	if err != OK:
		push_error("[pack] flush failed: %s" % error_string(err))
		quit(1)
		return

	# Compute sha256 + size for the manifest
	var file := FileAccess.open(abs_out, FileAccess.READ)
	if file == null:
		push_error("[pack] could not re-open pack for hashing")
		quit(1)
		return
	var size: int = file.get_length()
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_SHA256)
	const CHUNK := 1 << 20  # 1 MiB
	while file.get_position() < size:
		hash_ctx.update(file.get_buffer(CHUNK))
	file.close()
	var digest := hash_ctx.finish()
	var hex: String = ""
	for b in digest:
		hex += "%02x" % b

	print("[pack] size_bytes: ", size)
	print("[pack] sha256: ", hex)
	print("[pack] done")
	quit(0)


func _add_tree(packer: PCKPacker, dir_path: String) -> int:
	# Walk entries in sorted order so the resulting .pck — and therefore its
	# sha256 — is stable across machines/OSes regardless of readdir order.
	var d := DirAccess.open(dir_path)
	if d == null:
		push_warning("[pack] could not open dir: %s" % dir_path)
		return 0
	var dirs: Array[String] = []
	var files: Array[String] = []
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			if d.current_is_dir():
				dirs.append(name)
			else:
				files.append(name)
		name = d.get_next()
	d.list_dir_end()
	dirs.sort()
	files.sort()

	var count := 0
	for fn in files:
		var child_path := "%s/%s" % [dir_path, fn]
		var err := packer.add_file(child_path, child_path)
		if err != OK:
			push_warning("[pack] add_file failed for %s: %s" % [child_path, error_string(err)])
		else:
			count += 1
	for sub in dirs:
		count += _add_tree(packer, "%s/%s" % [dir_path, sub])
	return count


func _parse_args() -> Dictionary:
	var out := {}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var a: String = argv[i]
		if a == "--out" and i + 1 < argv.size():
			out["out"] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out
