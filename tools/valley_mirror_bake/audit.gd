extends "res://tools/stage_mirror_bake/audit.gd"
func _stage_rows() -> Dictionary:
	var rows := super._stage_rows().duplicate()
	for path in rows.keys():
		if not "/valley_" in path:
			rows.erase(path)
	return rows
