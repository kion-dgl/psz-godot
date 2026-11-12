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

## Read-only checks: never roll damage just to render the HUD.
static func available(p, action: String) -> bool:
	if action.is_empty(): return false
	if ActionPalette.is_consumable(action): return Inventory.get_item_count(action) > 0
	if not TechniqueManager.TECHNIQUES.has(action): return true
	if not is_instance_valid(p) or Inventory.can_use_traps(): return false
	if p._is_defeated or GameState.hp <= 0 or p._freeze.remaining > 0.0 or p._ailments.blocks_attack(): return false
	if p._recovery_left > 0.0 or p.current_state in [p.PlayerState.ATTACKING, p.PlayerState.DODGING, p.PlayerState.DAMAGED, p.PlayerState.DOWN]: return false
	var character = CharacterManager.get_active_character()
	if character == null: return false
	var spell: String = TechniqueManager.get_charged_technique(action)
	if spell == "reverser" and preload("res://scripts/3d/combat/support_technique.gd").revive_target(p) == null: return false
	var level: int = TechniqueManager.get_technique_level(character, spell)
	if level <= 0: return false
	var cost := maxi(1, int(TechniqueManager.TECHNIQUES[spell].get("pp", 5)) - int(float(level) / 5.0))
	return PhotonBlast.flozir_left > 0.0 or GameState.mp >= cost
