extends Control
## Bootstrap scene: resolves the asset pack before entering the game.
##
## Behavior:
## - Read res://assets_manifest.json (optional; missing = fast-path to title)
## - For each pack entry: check user://packs/<name>-<sha>.pck, download if
##   missing, verify sha256, mount with ProjectSettings.load_resource_pack
## - On success transition to res://scenes/2d/title.tscn
##
## The bootstrap itself must not reference res://assets/* — fonts and colors
## stay embedded so the UI renders before any pack is mounted.

const TITLE_SCENE := "res://scenes/2d/title.tscn"
const MANIFEST_PATH := "res://assets_manifest.json"
const CACHE_DIR := "user://packs"
const HASH_CHUNK := 1 << 20  # 1 MiB

# Retry policy: Arweave uploads via Turbo take several minutes to propagate
# to public gateways; treat 4xx/5xx as transient unless we've exhausted our
# budget. Per-URL attempts; the outer loop rotates through all mirrors first.
const HTTP_MAX_ATTEMPTS := 4
const HTTP_RETRY_DELAYS := [5.0, 15.0, 30.0, 60.0]  # seconds between attempts

@onready var _status: Label = $Center/VBox/Status
@onready var _progress: ProgressBar = $Center/VBox/Progress
@onready var _title: Label = $Center/VBox/Title

var _http: HTTPRequest
var _total_bytes: int = 0


func _ready() -> void:
	_title.text = "Phantasy Star Zero"
	_status.text = "Starting..."
	_progress.value = 0
	_progress.visible = false

	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)

	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		print("[bootstrap] no manifest — using in-tree /assets/ (dev mode)")
		_goto_title()
		return

	var packs: Array = manifest.get("packs", [])
	if packs.is_empty():
		print("[bootstrap] manifest has no packs — using in-tree /assets/")
		_goto_title()
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))

	for i in packs.size():
		var pack: Dictionary = packs[i]
		var name: String = _sanitize_pack_name(str(pack.get("name", "pack%d" % i)))
		var sha: String = str(pack.get("sha256", "")).strip_edges().to_lower()
		var size: int = int(pack.get("size", 0))
		var urls: Array = pack.get("urls", [])
		var cache_path := "%s/%s-%s.pck" % [CACHE_DIR, name, sha.substr(0, 12)]

		_status.text = "Checking %s..." % name
		await _yield_frame()

		var cached_ok: bool = FileAccess.file_exists(cache_path) \
			and await _verify_hash(cache_path, sha)
		if not cached_ok:
			_status.text = "Downloading %s..." % name
			_progress.visible = true
			_progress.value = 0
			_total_bytes = size
			var ok: bool = await _download_first_available(urls, cache_path)
			if not ok:
				_fatal("Failed to download %s — check your connection." % name)
				return
			_status.text = "Verifying %s..." % name
			if not await _verify_hash(cache_path, sha):
				_fatal("Integrity check failed for %s." % name)
				return
			_progress.visible = false

		if not ProjectSettings.load_resource_pack(cache_path):
			_fatal("Failed to mount %s." % name)
			return
		print("[bootstrap] mounted %s" % cache_path)

	_status.text = "Ready."
	await _yield_frame()
	_goto_title()


func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("[bootstrap] malformed manifest at %s" % MANIFEST_PATH)
	return {}


func _download_first_available(urls: Array, cache_path: String) -> bool:
	# First pass: try every URL once quickly. Second+ passes with backoff for
	# URLs that returned transient 4xx/5xx — covers Arweave gateway propagation.
	for attempt in HTTP_MAX_ATTEMPTS:
		for raw_url in urls:
			var url: String = _resolve_url(str(raw_url))
			print("[bootstrap] trying %s (attempt %d)" % [url, attempt + 1])
			if url.begins_with("file://"):
				if await _copy_local(url, cache_path):
					return true
				continue
			var ok: bool = await _http_download(url, cache_path)
			if ok:
				return true
		if attempt + 1 < HTTP_MAX_ATTEMPTS:
			var delay: float = HTTP_RETRY_DELAYS[mini(attempt, HTTP_RETRY_DELAYS.size() - 1)]
			_status.text = "Waiting for CDN... retry in %ds" % int(delay)
			await get_tree().create_timer(delay).timeout
	return false


func _resolve_url(url: String) -> String:
	# Dev shortcut: LOCAL_DIST token is replaced with the repo's dist/ dir so
	# a file:// URL in the manifest resolves against wherever the project is.
	if url.contains("LOCAL_DIST"):
		var proj_dir: String = ProjectSettings.globalize_path("res://").rstrip("/")
		url = url.replace("LOCAL_DIST", proj_dir + "/dist")
	return url


func _copy_local(file_url: String, dest: String) -> bool:
	var src: String = file_url.trim_prefix("file://")
	var src_abs: String = ProjectSettings.globalize_path(src) if src.begins_with("res://") else src
	if not FileAccess.file_exists(src_abs):
		push_warning("[bootstrap] local file missing: %s" % src_abs)
		return false
	var dest_abs: String = ProjectSettings.globalize_path(dest)
	var in_f := FileAccess.open(src_abs, FileAccess.READ)
	if in_f == null:
		push_warning("[bootstrap] copy open failed: cannot read %s" % src_abs)
		return false
	var out_f := FileAccess.open(dest_abs, FileAccess.WRITE)
	if out_f == null:
		in_f.close()
		push_warning("[bootstrap] copy open failed: cannot write %s" % dest_abs)
		return false
	var total: int = in_f.get_length()
	_total_bytes = total
	var copied: int = 0
	while in_f.get_position() < total:
		var chunk := in_f.get_buffer(HASH_CHUNK)
		out_f.store_buffer(chunk)
		copied += chunk.size()
		_progress.value = float(copied) / float(total) * 100.0
		await _yield_frame()
	in_f.close()
	out_f.close()
	return true


func _http_download(url: String, cache_path: String) -> bool:
	var dest_abs: String = ProjectSettings.globalize_path(cache_path)
	_http.download_file = dest_abs
	# Capture completion via a dictionary (shared by reference inside the
	# lambda, unlike a re-bound local array) so the progress loop can poll
	# without racing `await request_completed` — the signal can fire during
	# a process_frame yield and would otherwise block forever.
	var done := {"complete": false, "response_code": 0}
	var cb := func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		done["response_code"] = code
		done["complete"] = true
	_http.request_completed.connect(cb, CONNECT_ONE_SHOT)
	var err: int = _http.request(url)
	if err != OK:
		_http.request_completed.disconnect(cb)
		push_warning("[bootstrap] http request failed: %s" % error_string(err))
		return false
	while not done["complete"]:
		var got: int = _http.get_downloaded_bytes()
		if _total_bytes > 0:
			_progress.value = float(got) / float(_total_bytes) * 100.0
		await _yield_frame()
	var response_code: int = int(done["response_code"])
	if response_code != 200:
		push_warning("[bootstrap] http %d on %s" % [response_code, url])
		return false
	return true


func _verify_hash(path: String, expected_hex: String) -> bool:
	var abs: String = ProjectSettings.globalize_path(path)
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return false
	var size: int = f.get_length()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < size:
		ctx.update(f.get_buffer(HASH_CHUNK))
		await _yield_frame()
	f.close()
	var digest: PackedByteArray = ctx.finish()
	var hex: String = ""
	for b in digest:
		hex += "%02x" % b
	if hex != expected_hex.strip_edges().to_lower():
		push_warning("[bootstrap] hash mismatch: got %s want %s" % [hex, expected_hex])
		return false
	return true


func _yield_frame() -> Signal:
	return get_tree().process_frame


func _sanitize_pack_name(name: String) -> String:
	# Strip anything that could traverse out of CACHE_DIR. Manifest is in the
	# repo and typically trusted, but belt-and-suspenders.
	var safe: String = ""
	for c in name:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_" or c == "-":
			safe += c
	if safe.is_empty():
		safe = "pack"
	return safe


func _goto_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _fatal(msg: String) -> void:
	_status.text = "Error: %s" % msg
	push_error("[bootstrap] %s" % msg)
