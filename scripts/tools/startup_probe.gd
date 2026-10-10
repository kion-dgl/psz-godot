extends Node
## Isolated startup matrix. Run with a disposable user directory; never wipes
## the player's packs. Uses the real bootstrap scene with a tiny fixture pack.

class ProbeBoot extends "res://scripts/2d/bootstrap.gd":
	signal finished(ok: bool)
	var fixture_manifest: Dictionary
	var hash_count := 0
	func _read_manifest() -> Dictionary:
		return fixture_manifest
	func _goto_title() -> void:
		finished.emit(true)
	func _fatal(message: String) -> void:
		super._fatal(message)
		finished.emit(false)
	func _verify_hash(path: String, sha: String) -> bool:
		hash_count += 1
		return await super._verify_hash(path, sha)

var _failures := 0
var _manifest: Dictionary
var _cache_path: String
var _valid_sha: String


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/custom_user_dir_name", "").begins_with("psz-startup-test-"):
		push_error("Startup probe requires an isolated psz-startup-test-* user directory")
		get_tree().quit(1)
		return
	print("[startup-probe] userdir: " + OS.get_user_data_dir())
	preload("res://scripts/tools/startup_cache_tests.gd").run(self)
	await preload("res://scripts/tools/spectator_frame_tests.gd").run_live(self)
	_prepare_fixture()
	await _check_boot("first download", true, 1)
	await _check_boot("verified repeat launch", false, 0)
	DirAccess.remove_absolute(_cache_path + ".verified.json")
	await _check_boot("legacy cache verified once", false, 1)
	var f := FileAccess.open(_cache_path, FileAccess.WRITE)
	f.store_string("interrupted download")
	f.close()
	await _check_boot("corrupt cache repaired", true, 2)
	# A full-hash failure must not create a receipt or enter the title.
	DirAccess.remove_absolute(_cache_path)
	DirAccess.remove_absolute(_cache_path + ".verified.json")
	_manifest["pack"]["sha256"] = "0".repeat(64)
	await _check_boot("bad download rejected", true, 1, false)
	print("[startup-probe] %s" % ("DONE ok" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)


func _prepare_fixture() -> void:
	var source := FileAccess.open("user://startup-fixture.txt", FileAccess.WRITE)
	source.store_string("startup probe fixture\n".repeat(50000))
	source.close()
	var fixture_path := OS.get_environment("PSZ_STARTUP_FIXTURE_PATH")
	if fixture_path.is_empty(): fixture_path = "user://startup-fixture.pck"
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(fixture_path), OK, "create fixture pack")
	assert_eq(packer.add_file("res://startup-fixture.txt", "user://startup-fixture.txt"), OK, "add fixture content")
	assert_eq(packer.flush(), OK, "flush fixture pack")
	var sha := FileAccess.get_sha256(fixture_path)
	_valid_sha = sha
	var url := OS.get_environment("PSZ_STARTUP_FIXTURE_URL")
	if url.is_empty(): url = "file://" + ProjectSettings.globalize_path(fixture_path)
	_manifest = {"pack": {"sha256": sha,
		"size": FileAccess.get_file_as_bytes(fixture_path).size(),
		"urls": [url]}}
	_cache_path = "user://packs/assets-%s.pck" % sha.substr(0, 12)


func _check_boot(label: String, download: bool, hashes: int, success := true) -> void:
	var boot = load("res://scenes/2d/bootstrap.tscn").instantiate()
	boot.set_script(ProbeBoot)
	boot.fixture_manifest = _manifest
	var started := Time.get_ticks_msec()
	add_child(boot)
	var ok: bool = await boot.finished
	assert_eq(ok, success, label + " result")
	assert_eq(boot._download_visible, download, label + " download visibility")
	assert_eq(boot.hash_count, hashes, label + " full hash scans")
	if not download:
		assert_true(boot._http == null, label + " avoids HTTP client initialization")
	if not success:
		assert_true(boot._retry.visible, "failed download exposes Retry")
		assert_true(not FileAccess.file_exists("user://packs/assets-000000000000.pck.verified.json"), "invalid download has no receipt")
	if not success:
		boot.fixture_manifest["pack"]["sha256"] = _valid_sha
		boot._retry.pressed.emit.call_deferred()
		var recovered: bool = await boot.finished
		assert_true(recovered, "Retry recovers after the download source is corrected")
		assert_true(not boot._retry.visible, "Retry hides while preparation resumes")
	print("[startup-probe] %s: %dms" % [label, Time.get_ticks_msec() - started])
	boot.queue_free()
	await get_tree().process_frame


func assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error("[startup-probe] " + label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	assert_true(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
