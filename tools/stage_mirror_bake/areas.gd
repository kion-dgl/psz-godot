extends RefCounted
const AREAS := {"valley": "gurhacia", "wetlands": "ozette", "snowfield": "rioh", "makara": "makara", "paru": "paru", "arca": "arca", "shrine": "dark", "tower": "tower"}
static func area(path: String) -> String:
 return AREAS.get(path.split("/")[4].get_slice("_", 0), "")
