extends RefCounted
class_name PlacedTraps
## Field trap construction and room snapshots share one type/model mapping.
static func build(kind: String, state: String = "on", record: Dictionary = {}) -> GameElement:
	var trap: GameElement
	match kind:
		"gun_trap": trap = GunTrap.new()
		"burn_trap": trap = BombTrap.new()
		"needler_trap": trap = NeedlerTrap.new()
		"poison_trap": trap = PoisonTrap.new()
		"bear_trap", "capture_trap": trap = BearTrap.new()
		"needle_trap": trap = NeedleTrap.new()
		_: return null
	trap.set_meta("trap_kind", kind)
	trap.element_state = ("off" if state == "on" else state) if trap is BearTrap else state
	trap.rotation.y = deg_to_rad(float(record.get("rotation", 0.0)))
	if trap is GunTrap:
		var source_model := str(record.get("model", "o0c_gun01"))
		if source_model in ["o0c_gun01", "o0c_gun02"]:
			trap.model_path = "valley/" + source_model + ".glb"
	if trap is FieldHazard: trap.restore_hazard(record)
	return trap

static func snapshots(root: Node3D) -> Array:
	var records: Array = []
	for node in root.get_children():
		if not (node is BearTrap or node is NeedleTrap or node is FieldHazard): continue
		var fallback: String = "capture_trap" if node is BearTrap else node.trap_kind
		var record := {"type": str(node.get_meta("trap_kind", fallback)), "state": node.element_state,
			"px": node.position.x, "py": node.position.y, "pz": node.position.z,
			"rotation": rad_to_deg(node.rotation.y), "model": node.model_path.get_file().get_basename()}
		if node is BearTrap and node.is_alive: record.state = "spent"
		if node is FieldHazard: record.merge(node.save_hazard(), true)
		records.append(record)
	return records
