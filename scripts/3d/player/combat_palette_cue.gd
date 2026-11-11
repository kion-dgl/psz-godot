extends RefCounted
## Palette-only presentation of real attack, charge and recovery clocks.
static func read(p) -> Dictionary:
	if not is_instance_valid(p) or p.combat_aim == null or not p.combat_aim.eligible() or GameState.is_gameplay_blocked(): return {}
	if p._charging_slot >= 0:
		return {"progress": clampf(p._tech_charge_timer / p.TECH_CHARGE_THRESHOLD, 0, 1), "ready": p._tech_charge_ready, "queued": false, "charging": true, "slot": p._charging_slot}
	if p.current_state == p.PlayerState.DODGING:
		var duration: float = p._dodge_clip_duration if p._dodge_clip_duration > 0 else p.DODGE_DURATION
		return {"progress": clampf(p.dodge_timer / duration, 0, 1), "ready": false, "queued": false, "recovery": true}
	if p.current_state != p.PlayerState.ATTACKING: return {}
	var feedback: Dictionary = p.combat_aim.combo_feedback()
	return {"progress": feedback.fraction, "ready": feedback.state == "CLICK", "queued": feedback.state == "QUEUED", "open": feedback.open, "close": feedback.close, "recovery": p.combo_state <= 0 or p.combo_state >= 3}

static func applies(cue: Dictionary, action: String, slot: int) -> bool:
	if cue.get("charging", false): return slot == int(cue.slot)
	return action in ["attack", "strong_attack"] or (cue.get("recovery", false) and TechniqueManager.TECHNIQUES.has(action))
