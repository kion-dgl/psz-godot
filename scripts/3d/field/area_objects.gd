extends RefCounted
class_name AreaObjects
## Resolves which object-set model an element should load for the active area.
##
## PSZ re-skins a handful of field objects per area: the destructible container
## (`oNN_cont`), the destructible wall (`oNN_wall`) and the wall's break-apart
## debris (`oNN_wallptcl`) are a different mesh AND texture in every field. The
## rest of the archive is shared — every `o0c_*` object is byte-identical across
## all nine fields, so those stay hardcoded at their `valley/` path rather than
## being duplicated eight times.
##
## Before this existed, box.gd and wall.gd loaded `valley/o01_cont.glb` and
## `valley/o01_wall.glb` unconditionally, so Wetlands, Snowfield, Makara, Paru,
## Arca and Dark Shrine all showed Valley crates and Valley walls.
##
## Folder + scene number come from GridGenerator.AREA_CONFIG so there is one
## area table, not two.

# GridGenerator has no class_name; every consumer preloads it (see
# valley_field_controller.gd, warp_pad.gd, weather_controller.gd).
const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

## Object-set suffixes that vary per field.
const PER_FIELD_SUFFIXES := ["cont", "wall", "wallptcl"]

## Area used when the active area has no per-field model for a suffix. The
## Eternal Tower is the real case: it ships `o08_cont` but no wall or debris
## (its rooms are sealed rather than walled off).
const FALLBACK_AREA := "gurhacia"


## Object-set folder for an area, e.g. "ozette" -> "wetlands".
static func folder(area_id: String) -> String:
	var cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, {})
	return str(cfg.get("folder", GridGenerator.AREA_CONFIG[FALLBACK_AREA]["folder"]))


## Two-digit scene number for an area, e.g. "ozette" -> "02" (from prefix "s02").
static func scene_num(area_id: String) -> String:
	var cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, {})
	var prefix: String = str(cfg.get("prefix", GridGenerator.AREA_CONFIG[FALLBACK_AREA]["prefix"]))
	return prefix.substr(1)


## Where an area's per-field model WOULD live, e.g. ("ozette", "cont") ->
## "wetlands/o02_cont.glb". Pure string mapping, no filesystem access, so the
## pack-free test_runner can pin every area.
static func candidate_path(area_id: String, suffix: String) -> String:
	return "%s/o%s_%s.glb" % [folder(area_id), scene_num(area_id), suffix]


## The Valley model for a suffix — what an area falls back to when it ships no
## variant of its own.
static func fallback_path(suffix: String) -> String:
	return candidate_path(FALLBACK_AREA, suffix)


## Model path (relative to assets/objects/) for a per-field suffix, falling back
## to the Valley model when the area does not ship one.
##
## The existence probe is what keeps the Tower's missing wall from becoming a
## load warning and an invisible, uncollidable obstacle.
static func model_path(area_id: String, suffix: String) -> String:
	var candidate := candidate_path(area_id, suffix)
	if ResourceLoader.exists("res://assets/objects/" + candidate):
		return candidate
	var fallback := fallback_path(suffix)
	if candidate != fallback:
		push_warning(
			"AreaObjects: no %s model for area '%s' (%s) — using %s"
			% [suffix, area_id, candidate, fallback]
		)
	return fallback


## Model path for the area the player is currently in.
static func current_model_path(suffix: String) -> String:
	return model_path(SessionManager.get_current_area_id(), suffix)


## Local-space extents of a loaded model, for sizing a collider to the mesh the
## area actually gave us. Thin alias over MeshBounds so callers do not need to
## know about the include-root-transform distinction.
static func model_extents(root: Node3D) -> AABB:
	return MeshBounds.combined(root)
