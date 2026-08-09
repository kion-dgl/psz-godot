extends RefCounted
class_name SourceWrap
## Per-axis texture wrap read back from a model's source .glb.
##
## The DS sets wrap per axis and leans on mirroring heavily — surveying the
## exported models gives 482 mirror/mirror, 444 repeat/repeat, and 283 that
## mirror EXACTLY ONE axis (#576). That asymmetry is the tell that the data is
## real: a converter default would produce one uniform pair, and NDS texture
## params carry separate S/T repeat+flip bits, so per-axis is what the hardware
## actually expresses.
##
## Godot's glTF importer collapses all of it into a single `texture_repeat`
## bool on BaseMaterial3D — o0c_needle's two surfaces come back true/false from
## source wraps of (mirror, repeat) and (repeat, mirror) — so the information
## cannot be recovered from the imported material. It can be read straight out
## of the .glb, which ships in the pack alongside the imported scene, and that
## is what this does.
##
## Before this, every caller that wanted mirroring assumed BOTH axes. That is
## right for the box (o01_cont is mirror/mirror) and wrong for every wall
## (o01_wall and friends are repeat/repeat), which is the bug #576 describes.

## glTF sampler wrap enums.
const GL_CLAMP_TO_EDGE := 33071
const GL_MIRRORED_REPEAT := 33648
const GL_REPEAT := 10497

## Parsed results, keyed by .glb resource path. Parsing is a ~2 KB JSON read, but
## elements re-load the same handful of models constantly.
static var _cache: Dictionary = {}


## {texture_filename: {"s": mode, "t": mode}} for a model, where mode is one of
## "mirror" / "repeat" / "clamp". Empty when the file is missing or unparseable —
## callers should treat that as "no opinion" and leave the material alone rather
## than guessing.
static func for_glb(glb_path: String) -> Dictionary:
	if _cache.has(glb_path):
		return _cache[glb_path]
	var parsed := _parse(glb_path)
	_cache[glb_path] = parsed
	return parsed


## Wrap for one texture of one model, or {} when unknown.
static func for_texture(glb_path: String, texture_filename: String) -> Dictionary:
	return for_glb(glb_path).get(texture_filename, {})


static func _mode(value: int) -> String:
	match value:
		GL_MIRRORED_REPEAT:
			return "mirror"
		GL_CLAMP_TO_EDGE:
			return "clamp"
		_:
			return "repeat"


## Read the JSON chunk of a binary glTF and resolve textures -> images -> samplers.
##
## glb layout: 12-byte header (magic, version, length), then chunks of
## (length, type, data). The first chunk is always JSON.
static func _parse(glb_path: String) -> Dictionary:
	var fa := FileAccess.open(glb_path, FileAccess.READ)
	if not fa:
		push_warning("SourceWrap: cannot open " + glb_path)
		return {}
	if fa.get_buffer(4).get_string_from_ascii() != "glTF":
		push_warning("SourceWrap: not a binary glTF: " + glb_path)
		return {}
	fa.get_32()  # version
	fa.get_32()  # total length
	var json_len := fa.get_32()
	fa.get_32()  # chunk type (JSON)
	var json_text := fa.get_buffer(json_len).get_string_from_utf8()

	var json := JSON.new()
	if json.parse(json_text) != OK or not (json.data is Dictionary):
		push_warning("SourceWrap: bad JSON chunk in " + glb_path)
		return {}
	var doc: Dictionary = json.data

	var images: Array = doc.get("images", [])
	var samplers: Array = doc.get("samplers", [])
	var out: Dictionary = {}
	for tex in doc.get("textures", []):
		var source_idx: int = int(tex.get("source", -1))
		var sampler_idx: int = int(tex.get("sampler", -1))
		if source_idx < 0 or source_idx >= images.size():
			continue
		var uri: String = str(images[source_idx].get("uri", ""))
		if uri.is_empty():
			continue
		# A texture may omit its sampler, which means glTF defaults (repeat).
		var s_wrap := GL_REPEAT
		var t_wrap := GL_REPEAT
		if sampler_idx >= 0 and sampler_idx < samplers.size():
			var sampler: Dictionary = samplers[sampler_idx]
			s_wrap = int(sampler.get("wrapS", GL_REPEAT))
			t_wrap = int(sampler.get("wrapT", GL_REPEAT))
		out[uri.get_file()] = {"s": _mode(s_wrap), "t": _mode(t_wrap)}
	return out


## Clear the parse cache. Test-only — the cache is keyed by path and models do
## not change at runtime.
static func clear_cache() -> void:
	_cache.clear()
