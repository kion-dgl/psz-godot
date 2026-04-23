extends Control
## Bootstrap scene: fetches the universal asset pack (if any) before entering
## the game.
##
## Behavior:
## - Read res://assets_manifest.json (optional; missing = fast-path to title)
## - Check user://packs/assets-<sha>.pck, download if missing, verify sha256,
##   mount via ProjectSettings.load_resource_pack
## - Delete any stale asset-*.pck files we don't recognize (leftovers from the
##   old per-category layout)
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
# Hosts that returned response_code 0 (TLS handshake or network failure).
# Once blacklisted, remaining URLs to that host are skipped for this run, so
# we don't pay a multi-second TLS timeout for every attempt. Arweave mirrors
# continue to work, so bootstrap still completes.
var _bad_hosts: Dictionary = {}


func _ready() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	print("[bootstrap] psz-godot %s on %s/%s (Godot %s)" % [
		version, OS.get_name(), Engine.get_architecture_name(), Engine.get_version_info().get("string", "?")
	])
	_title.text = "Phantasy Star Zero"
	_status.text = "Starting..."
	_progress.value = 0
	_progress.visible = false

	_http = HTTPRequest.new()
	_http.use_threads = true
	# Skip TLS cert verification for pack downloads. Content is public, URLs
	# are content-addressed (sha256 in filename), and the pack is sha256-
	# verified post-download — so a MITM can at worst substitute bytes that
	# fail the integrity check. Without this, Godot's bundled mbedTLS can
	# reject legitimate R2 certs on Windows (MBEDTLS_ERR_X509_CERT_VERIFY_FAILED
	# / -9984) where Schannel/curl succeed.
	_http.set_tls_options(TLSOptions.client_unsafe())
	add_child(_http)

	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = _read_manifest()
	if manifest.is_empty():
		print("[bootstrap] no manifest — using in-tree /assets/ (dev mode)")
		_goto_title()
		return

	var pack: Dictionary = manifest.get("pack", {})
	if pack.is_empty():
		print("[bootstrap] manifest has no pack — using in-tree /assets/")
		_goto_title()
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))

	var sha: String = str(pack.get("sha256", "")).strip_edges().to_lower()
	var size: int = int(pack.get("size", 0))
	var urls: Array = pack.get("urls", [])
	if sha.is_empty() or urls.is_empty():
		_fatal("Manifest pack entry missing sha256 or urls.")
		return

	var cache_path: String = "%s/assets-%s.pck" % [CACHE_DIR, sha.substr(0, 12)]
	_cleanup_stale(cache_path)

	_status.text = "Checking assets..."
	await _yield_frame()

	var cached_ok: bool = FileAccess.file_exists(cache_path) \
		and await _verify_hash(cache_path, sha)
	if not cached_ok:
		_status.text = "Downloading assets..."
		_progress.visible = true
		_progress.value = 0
		_total_bytes = size
		var ok: bool = await _download_first_available(urls, cache_path)
		if not ok:
			_fatal("Failed to download assets — check your connection.")
			return
		_status.text = "Verifying assets..."
		if not await _verify_hash(cache_path, sha):
			_fatal("Integrity check failed for assets.")
			return
		_progress.visible = false

	if not ProjectSettings.load_resource_pack(cache_path):
		_fatal("Failed to mount assets pack.")
		return
	print("[bootstrap] mounted %s" % cache_path)

	_status.text = "Ready."
	await _yield_frame()
	_goto_title()


## Remove any *.pck under user://packs/ that isn't the one we're about to use.
## Keeps disk clean across version bumps and across the old per-category layout
## (music-*.pck, world-*.pck, etc.) where each bump left orphaned files behind.
func _cleanup_stale(keep_path: String) -> void:
	var abs_dir: String = ProjectSettings.globalize_path(CACHE_DIR)
	var abs_keep: String = ProjectSettings.globalize_path(keep_path)
	var d := DirAccess.open(CACHE_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != ".." and name.ends_with(".pck"):
			var abs_entry: String = abs_dir.path_join(name)
			if abs_entry != abs_keep:
				DirAccess.remove_absolute(abs_entry)
				print("[bootstrap] cleaned stale pack: %s" % name)
		name = d.get_next()
	d.list_dir_end()


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
	for attempt in HTTP_MAX_ATTEMPTS:
		for raw_url in urls:
			var url: String = _resolve_url(str(raw_url))
			var host: String = _url_host(url)
			if host != "" and _bad_hosts.has(host):
				print("[bootstrap] skipping %s (host previously failed this run)" % url)
				continue
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
	# Dev shortcut: LOCAL_DIST in a file:// URL resolves to the repo's dist/.
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
		# response_code == 0 means the request never got an HTTP reply — TLS
		# handshake aborted, DNS failure, or connection reset. Blacklist the
		# host so subsequent attempts don't repeat the multi-second timeout.
		if response_code == 0:
			var host: String = _url_host(url)
			if host != "":
				_bad_hosts[host] = true
				print("[bootstrap] blacklisting host %s for this session" % host)
		return false
	return true


func _url_host(url: String) -> String:
	var rest: String = url
	var scheme_idx: int = url.find("://")
	if scheme_idx >= 0:
		rest = url.substr(scheme_idx + 3)
	var slash: int = rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	return rest


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


func _goto_title() -> void:
	# First-run controller prompt lands between the logo and the title screen
	# (MH Rise / PSO2 order). Once the scheme is saved, later boots skip
	# straight to the title. Delete user://input_config.json to re-onboard.
	if not InputConfig.has_saved_config():
		get_tree().change_scene_to_file("res://scenes/2d/input_select.tscn")
	else:
		get_tree().change_scene_to_file(TITLE_SCENE)


func _fatal(msg: String) -> void:
	_status.text = "Error: %s" % msg
	push_error("[bootstrap] %s" % msg)
