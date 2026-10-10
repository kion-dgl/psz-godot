extends RefCounted
## Local verified-pack receipt. Written only after SHA-256 validation + mount.
## This avoids rescanning unchanged app-private data on every launch; it is
## not an authenticity check against someone preserving size and timestamp.

const SUFFIX := ".verified.json"


static func matches(path: String, expected_sha: String, expected_size: int) -> bool:
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + SUFFIX):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path + SUFFIX)) != OK:
		return false
	var raw: Variant = parser.data
	if not raw is Dictionary:
		return false
	if not (raw.get("size") is float or raw.get("size") is int) \
		or not (raw.get("modified") is float or raw.get("modified") is int):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := f.get_length()
	f.close()
	return raw.get("sha256", "") == expected_sha \
		and int(raw.get("size", -1)) == size and size == expected_size \
		and int(raw.get("modified", -1)) == FileAccess.get_modified_time(path)


static func record(path: String, sha: String) -> bool:
	var pack := FileAccess.open(path, FileAccess.READ)
	if pack == null:
		return false
	var receipt := {
		"sha256": sha, "size": pack.get_length(),
		"modified": FileAccess.get_modified_time(path),
	}
	pack.close()
	var temp_path := path + SUFFIX + ".tmp"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(receipt))
	f.close()
	return DirAccess.rename_absolute(temp_path, path + SUFFIX) == OK
