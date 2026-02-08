class_name ResourceUtils
## Utility for resource loading that works in both editor and exported builds.
## In exported builds, .tres files become .tres.remap — DirAccess lists the
## remapped names, so we must check for both suffixes.


## List resource file paths in a directory, handling .remap suffix in exports.
static func list_resources(dir_path: String, extension: String = ".tres") -> Array[String]:
	var paths: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(extension):
				paths.append(dir_path + file_name)
			elif file_name.ends_with(extension + ".remap"):
				paths.append(dir_path + file_name.replace(".remap", ""))
		file_name = dir.get_next()
	dir.list_dir_end()
	return paths
