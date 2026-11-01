extends "res://tools/stage_mirror_bake/viewer.gd"
## Keep the approved Valley comparison entry point scoped to Valley.
func _source_paths() -> Array:
	return super._source_paths().filter(func(path): return "/valley_" in path)
