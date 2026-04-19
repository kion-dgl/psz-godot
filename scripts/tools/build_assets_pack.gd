@tool
extends SceneTree
## Headless tool that builds ONE asset pack scoped to specific includes and
## targeted at one platform's texture variants.
##
## Usage:
##     godot --headless --script scripts/tools/build_assets_pack.gd -- \
##         --pack <name> \
##         --platform <linux-x86_64|linux-arm64|windows-x86_64|macos|android> \
##         --include "<prefix1>" "<prefix2>" ... \
##         --out <path>
##
## What it does, vs the old "bundle everything" approach: walks only the
## given prefixes under res:// (e.g. "assets/music/"), and for every .import
## sidecar with multi-variant texture paths (path.s3tc=…, path.etc2=…) it
## emits a single-`path=` sidecar pointing at the variant the target platform
## supports. Bundles only the matching .ctex variant. Platforms with multiple
## supported variants (e.g. linux-arm64) keep all of them.
##
## Why this exists: PCKPacker ships raw editor sidecars unchanged, which on
## Android causes the runtime resolver to fail on chained scene→texture refs
## (issue #146). Godot's `--export-pack` does this transform internally but
## fights with our preset-filter scoping. This tool re-implements the transform
## explicitly so we keep PCKPacker's speed AND ship platform-correct sidecars.

const HASH_CHUNK := 1 << 20  # 1 MiB

# Variant lists per target platform — must match the texture_format/* settings
# in the corresponding [preset.N.options] block of export_presets.cfg. If you
# change a binary preset's texture format, mirror it here.
const PLATFORM_VARIANTS := {
	"linux-x86_64": ["s3tc"],
	"linux-arm64": ["s3tc", "etc2"],
	"windows-x86_64": ["s3tc"],
	"macos": ["s3tc"],
	"android": ["etc2"],
}


func _init() -> void:
	var args := _parse_args()
	var pack_name: String = args.get("pack", "")
	var platform: String = args.get("platform", "")
	var includes: Array = args.get("include", [])
	var out_path: String = args.get("out", "")

	if pack_name.is_empty() or platform.is_empty() or includes.is_empty() or out_path.is_empty():
		push_error("[pack] usage: --pack <name> --platform <p> --include <prefix>... --out <path>")
		quit(2)
		return
	if not PLATFORM_VARIANTS.has(platform):
		push_error("[pack] unknown platform '%s' — must be one of %s" % [platform, PLATFORM_VARIANTS.keys()])
		quit(2)
		return

	var variants: Array = PLATFORM_VARIANTS[platform]
	var abs_out: String = _resolve_out_path(out_path)
	print("[pack] name=%s platform=%s variants=%s out=%s" % [pack_name, platform, variants, abs_out])
	print("[pack] includes: %s" % [includes])

	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())

	var packer := PCKPacker.new()
	var err := packer.pck_start(abs_out)
	if err != OK:
		push_error("[pack] pck_start failed: %s" % error_string(err))
		quit(1)
		return

	var added := 0
	var transformed := 0
	for prefix_raw in includes:
		var prefix: String = str(prefix_raw).rstrip("/")
		var dir_path: String = "res://%s" % prefix
		var pair: Array = _add_tree(packer, dir_path, variants)
		added += int(pair[0])
		transformed += int(pair[1])

	print("[pack] files added: %d (%d sidecars transformed)" % [added, transformed])

	err = packer.flush(true)
	if err != OK:
		push_error("[pack] flush failed: %s" % error_string(err))
		quit(1)
		return

	var info := _hash_file(abs_out)
	print("[pack] size_bytes: ", info.size)
	print("[pack] sha256: ", info.sha256)
	print("[pack] done")
	quit(0)


## Recursively add files under `dir_path` to the pack. For each .import
## sidecar with multi-variant texture paths, emits a transformed sidecar +
## just the matching .ctex variants. Source files that have a sibling .import
## are skipped (the imported variant in res://.godot/imported/ is what the
## runtime loads — shipping the original .png/.ogg/.glb too would double the
## pack size). Returns [files_added, sidecars_transformed].
func _add_tree(packer: PCKPacker, dir_path: String, variants: Array) -> Array:
	var d := DirAccess.open(dir_path)
	if d == null:
		push_warning("[pack] could not open dir: %s" % dir_path)
		return [0, 0]
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

	# Build a set of source-file basenames that have a sibling .import so we
	# can skip them. e.g. if "moon.png" and "moon.png.import" both exist,
	# skip "moon.png" — the imported .ctex carries the actual texture data.
	var imported_sources: Dictionary = {}
	for fn in files:
		if fn.ends_with(".import"):
			imported_sources[fn.trim_suffix(".import")] = true

	var added := 0
	var transformed := 0
	for fn in files:
		var child_path := "%s/%s" % [dir_path, fn]
		if fn.ends_with(".import"):
			var pair: Array = _add_import_sidecar(packer, child_path, variants)
			added += int(pair[0])
			transformed += int(pair[1])
			continue
		if imported_sources.has(fn):
			# Source file has a sibling .import — skip; imported variant ships instead.
			continue
		# .uid and other Godot bookkeeping files: skip — runtime regenerates from project.binary.
		if fn.ends_with(".uid"):
			continue
		var err := packer.add_file(child_path, child_path)
		if err == OK:
			added += 1
		else:
			push_warning("[pack] add_file failed for %s: %s" % [child_path, error_string(err)])
	for sub in dirs:
		var pair: Array = _add_tree(packer, "%s/%s" % [dir_path, sub], variants)
		added += int(pair[0])
		transformed += int(pair[1])
	return [added, transformed]


## Read a .import sidecar; if it has path.<format>= multi-variant entries,
## select the variants matching `variants` and emit a transformed sidecar
## plus the corresponding .ctex files. Returns [files_added, transformed].
func _add_import_sidecar(packer: PCKPacker, sidecar_path: String, variants: Array) -> Array:
	var text: String = FileAccess.get_file_as_string(sidecar_path)
	if text.is_empty():
		push_warning("[pack] empty sidecar: %s" % sidecar_path)
		return [0, 0]

	# Look for multi-variant: lines like `path.s3tc="res://.godot/imported/foo.s3tc.ctex"`
	var has_multi := false
	for line in text.split("\n"):
		if line.strip_edges().begins_with("path."):
			has_multi = true
			break

	if not has_multi:
		# Single-variant sidecar — pass through unchanged. Add sidecar + the
		# single dest_file referenced.
		var added := 0
		if packer.add_file(sidecar_path, sidecar_path) == OK:
			added += 1
		var dests: Array = _parse_dest_files(text)
		for d in dests:
			if FileAccess.file_exists(d):
				if packer.add_file(d, d) == OK:
					added += 1
		return [added, 0]

	# Multi-variant: pick variants we want, drop the rest.
	var picked_paths: Dictionary = {}  # variant → resource path
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		for v in variants:
			var prefix: String = "path.%s=" % v
			if stripped.begins_with(prefix):
				var quoted: String = stripped.substr(prefix.length())
				picked_paths[v] = quoted.trim_prefix("\"").trim_suffix("\"")

	if picked_paths.is_empty():
		push_warning("[pack] sidecar %s has no matching variants for %s" % [sidecar_path, variants])
		return [0, 0]

	var transformed_text := _rewrite_sidecar(text, variants, picked_paths)
	var transformed_added: int = _add_file_with_content(packer, sidecar_path, transformed_text)
	var ctex_added := 0
	for v in picked_paths:
		var ctex_path: String = picked_paths[v]
		if FileAccess.file_exists(ctex_path):
			if packer.add_file(ctex_path, ctex_path) == OK:
				ctex_added += 1
		else:
			push_warning("[pack] missing ctex: %s (referenced by %s)" % [ctex_path, sidecar_path])
	return [transformed_added + ctex_added, 1]


## Rewrite the sidecar so the chosen variants are kept and other variants are
## removed. If only ONE variant is chosen, also collapse path.<v>= → path=
## and dest_files to single-entry (so the runtime resolver doesn't see a
## multi-variant entry). If multiple variants are chosen (e.g. linux-arm64),
## preserve all path.<v>= lines.
func _rewrite_sidecar(text: String, variants: Array, picked: Dictionary) -> String:
	var lines: PackedStringArray = text.split("\n")
	var out_lines: PackedStringArray = []
	var collapse_to_single: bool = picked.size() == 1
	var single_path: String = picked[picked.keys()[0]] if collapse_to_single else ""

	for line in lines:
		var stripped: String = line.strip_edges()
		# Drop path.<v>= for variants we DIDN'T pick.
		if stripped.begins_with("path."):
			var keep := false
			for v in variants:
				if stripped.begins_with("path.%s=" % v):
					keep = true
					break
			if not keep:
				continue
			# If single-variant, collapse to plain `path=`
			if collapse_to_single:
				out_lines.append("path=\"%s\"" % single_path)
				continue
			# Multi-variant: keep the line as-is (already in chosen set)
			out_lines.append(line)
			continue
		# Rewrite dest_files to only the picked .ctex paths.
		if stripped.begins_with("dest_files="):
			var arr_str: String = "[\"%s\"]" % "\",\"".join(picked.values())
			out_lines.append("dest_files=%s" % arr_str)
			continue
		# Drop the imported_formats metadata array if collapsing — runtime
		# treats this as "this is multi-variant" otherwise. Leave alone for
		# multi-variant case.
		if collapse_to_single and stripped.begins_with("\"imported_formats\":"):
			continue
		# Drop "vram_texture": true marker if collapsing — same reason.
		if collapse_to_single and stripped.begins_with("\"vram_texture\":"):
			continue
		out_lines.append(line)
	return "\n".join(out_lines)


## Parse dest_files=[...] line out of a sidecar. Returns array of res:// paths.
func _parse_dest_files(text: String) -> Array:
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("dest_files="):
			continue
		var rhs: String = stripped.substr("dest_files=".length()).strip_edges()
		# Strip surrounding [...]
		rhs = rhs.trim_prefix("[").trim_suffix("]")
		var out: Array = []
		for raw in rhs.split(","):
			var s: String = raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
			if not s.is_empty():
				out.append(s)
		return out
	return []


## PCKPacker.add_file copies a file by path. To pack a transformed sidecar,
## we have to write the bytes to a temp file first then add by path.
func _add_file_with_content(packer: PCKPacker, virtual_path: String, content: String) -> int:
	var tmp_path: String = "user://_pack_tmp_%d" % Time.get_ticks_usec()
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("[pack] could not open tmp for sidecar rewrite: %s" % virtual_path)
		return 0
	f.store_string(content)
	f.close()
	var err := packer.add_file(virtual_path, tmp_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	if err != OK:
		push_warning("[pack] add_file (rewritten) failed for %s: %s" % [virtual_path, error_string(err)])
		return 0
	return 1


func _resolve_out_path(out_path: String) -> String:
	if out_path.begins_with("res://"):
		return ProjectSettings.globalize_path(out_path)
	if out_path.is_absolute_path():
		return out_path
	return ProjectSettings.globalize_path("res://").path_join(out_path)


func _hash_file(abs_path: String) -> Dictionary:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		push_error("[pack] could not re-open pack for hashing")
		quit(1)
		return {}
	var size: int = f.get_length()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < size:
		ctx.update(f.get_buffer(HASH_CHUNK))
	f.close()
	var digest: PackedByteArray = ctx.finish()
	var hex: String = ""
	for b in digest:
		hex += "%02x" % b
	return {"size": size, "sha256": hex}


func _parse_args() -> Dictionary:
	var out := {"include": []}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var a: String = argv[i]
		if a == "--pack" and i + 1 < argv.size():
			out["pack"] = argv[i + 1]; i += 2
		elif a == "--platform" and i + 1 < argv.size():
			out["platform"] = argv[i + 1]; i += 2
		elif a == "--out" and i + 1 < argv.size():
			out["out"] = argv[i + 1]; i += 2
		elif a == "--include":
			# Consume all following non-flag args as include prefixes.
			i += 1
			var inc: Array = out["include"]
			while i < argv.size() and not argv[i].begins_with("--"):
				inc.append(argv[i])
				i += 1
		else:
			i += 1
	return out
