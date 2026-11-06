class_name PlayerAvatar extends RefCounted
## Shared VRM-only loader for gameplay and character previews.
## pszLegacyRig/1 restores native PSZ animation binds; arbitrary VRM retargeting
## is not yet supported. See docs/character-vrm-policy.md.

static func instantiate(path: String) -> Node3D:
	if not path.ends_with(".vrm") or not FileAccess.file_exists(path):
		push_error("Player avatar missing or not VRM: " + path)
		return null
	var compatible := legacy_buffer(FileAccess.get_file_as_bytes(path))
	if compatible.is_empty():
		push_error("Unsupported VRM animation profile: " + path)
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(compatible, path.get_base_dir(), state) != OK:
		push_error("Unable to load player VRM: " + path)
		return null
	var result := document.generate_scene(state)
	if result:
		result.set_meta("psz_avatar_format", "VRM 1.0 / pszLegacyRig/1")
		result.set_meta("psz_avatar_path", path)
	return result

static func legacy_buffer(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < 28 or bytes.slice(0, 4).get_string_from_ascii() != "glTF" or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size():
		return PackedByteArray()
	var json_length := bytes.decode_u32(12)
	if json_length > bytes.size() - 28 or bytes.decode_u32(16) != 0x4e4f534a:
		return PackedByteArray()
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	if not parsed is Dictionary:
		return PackedByteArray()
	var doc := _restore_legacy_document(parsed)
	if doc.is_empty():
		return PackedByteArray()
	var encoded := JSON.stringify(doc).to_utf8_buffer()
	while encoded.size() % 4: encoded.append(32)
	var binary_chunk := bytes.slice(20 + json_length)
	if binary_chunk.size() < 8 or binary_chunk.decode_u32(4) != 0x004e4942 or binary_chunk.decode_u32(0) != binary_chunk.size() - 8:
		return PackedByteArray()
	var result := PackedByteArray()
	result.resize(20)
	result.encode_u32(0, 0x46546c67)
	result.encode_u32(4, 2)
	result.encode_u32(8, 20 + encoded.size() + binary_chunk.size())
	result.encode_u32(12, encoded.size())
	result.encode_u32(16, 0x4e4f534a)
	result.append_array(encoded)
	result.append_array(binary_chunk)
	return result

static func _restore_legacy_document(parsed: Dictionary) -> Dictionary:
	var doc: Dictionary = parsed
	var profile := _get_profile(doc)
	if profile.get("version") != 1 or str(profile.get("model", "")).is_empty() or not profile.get("nodes") is Array:
		return {}
	var skins: Array = doc.get("skins", [])
	var meshes: Array = doc.get("meshes", [])
	var accessors: Array = doc.get("accessors", [])
	var position := int(profile.get("positionAccessor", -1))
	var inverse := int(profile.get("inverseBindMatrices", -1))
	if skins.size() != 1 or meshes.size() != 1 or position < 0 or position >= accessors.size() or inverse < 0 or inverse >= accessors.size():
		return {}
	if meshes[0].get("primitives", []).is_empty() or profile.nodes.size() != doc.get("nodes", []).size():
		return {}
	doc.nodes = profile.nodes
	doc.skins[0].inverseBindMatrices = inverse
	for primitive in doc.meshes[0].primitives:
		primitive.attributes.POSITION = position
	# VRM metadata describes the portable T-pose, not this internal PSZ scene.
	doc.erase("extensions")
	doc.erase("extras")
	doc.extensionsUsed = ["KHR_materials_unlit"]
	return doc

static func _get_profile(doc: Dictionary) -> Dictionary:
	var extensions: Variant = doc.get("extensions")
	var extras: Variant = doc.get("extras")
	if not extensions is Dictionary or not extras is Dictionary:
		return {}
	var vrm: Variant = extensions.get("VRMC_vrm")
	var profile: Variant = extras.get("pszLegacyRig")
	if not vrm is Dictionary or not profile is Dictionary:
		return {}
	if vrm.get("specVersion") != "1.0":
		return {}
	return profile
