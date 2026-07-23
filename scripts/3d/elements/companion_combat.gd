class_name CompanionCombat
## Pure decision functions for the companion's phase-1 combat FSM
## (spec /states/companion-combat). Everything here is data-in/data-out —
## no scene, autoload, or node access — so test_runner exercises the
## decisions off-tree. The stateful driver lives in companion_npc.gd.

## Combat tuning (spec /states/companion-combat — the normative values)
const LEASH_RADIUS: float = 12.0  # XZ metres from the PLAYER a target may be
const ENGAGE_REACH_FRAC: float = 0.8  # swing when within this frac of hit_h_dist
const ATTACK_COOLDOWN: float = 1.2  # seconds between swings, / weapon speed_mult
const COMBAT_SCAN_INTERVAL: float = 0.25  # target-scan cadence while following
const COMPANION_DAMAGE_SCALE: float = 0.7  # helper, not the main DPS
const ENGAGE_NO_PROGRESS_TIME: float = 8.0  # blocked-approach self-heal → regroup
const COMBAT_STUCK_TIME: float = 60.0  # autopilot tripwire backstop
const FALLBACK_SWING_TIME: float = 0.5  # swing length when no atk1 clip resolves

## Weapon type per companion (CombatManager.WEAPON_TYPE_CONFIGS keys). Phase 1
## resolves the hit cone / damage from this type; unlisted companions default to
## SABER (0). Kai carries the Axeon gunblade (GUN_BLADE = 7) — a melee swing in
## phase 1 (its ranged mode is phase-2 work), so the shared cone geometry still
## applies. The visual model + swing animation set follow from this type in
## companion_npc.gd (COMPANION_WEAPONS / WEAPON_ANIM).
const COMPANION_WEAPON_TYPES: Dictionary = {
	"kai": 7,     # gunblade (Axeon)
	"sarisa": 2,  # daggers
	"dorn": 1,    # sword
	"elio": 1,    # sword
	"fern": 2,    # daggers
}

## Locomotion clip thresholds (m/s of the companion's OWN measured planar
## speed). The pure selector below and companion_npc's tripwire share them so
## there is a single source (spec /states/companion). RUN_ENTER/RUN_EXIT form a
## hysteresis band: measured speed is a noisy per-frame displacement, so a single
## run/walk threshold flaps the clip when it hovers there (#463). The 1 m/s
## deadband against the ~6 m/s steady follow speed is the one value worth
## confirming on-device.
const IDLE_EPS: float = 0.15   # below this the companion plays "wait"
const RUN_ENTER: float = 4.0   # walk→run only when measured speed climbs ABOVE this
const RUN_EXIT: float = 3.0    # run→walk only when measured speed drops BELOW this


static func weapon_type_for(companion_id: String) -> int:
	return int(COMPANION_WEAPON_TYPES.get(companion_id, 0))


## Locomotion clip from the FSM's movement INTENT reconciled with the
## companion's own measured planar speed (spec /states/companion,
## /states/companion-combat). intent_moving=false always yields "wait"; and even
## when the FSM intends to move, a measured planar speed below IDLE_EPS still
## yields "wait" — the #420 veto, so a body pinned by geometry or the personal-
## space cap never plays a locomotion clip while standing still.
##
## The walk↔run split uses a hysteresis band (#463): measured planar_speed is a
## noisy per-frame displacement, and a single threshold makes it flap when it
## hovers there. So the caller threads in current_clip (the clip playing now):
## enter "run" only ABOVE RUN_ENTER, drop back to "walk" only BELOW RUN_EXIT, and
## in the RUN_EXIT..RUN_ENTER band HOLD the current clip. Coming out of "wait"
## (or any non-"run" clip) uses the enter threshold, so a body that is genuinely
## moving picks walk/run sensibly. Pure so test_runner pins it off-tree.
static func locomotion_clip(intent_moving: bool, planar_speed: float, current_clip: String) -> String:
	if not intent_moving or planar_speed < IDLE_EPS:
		return "wait"
	if current_clip == "run":
		# Already running: hold "run" through the deadband; only a clear drop
		# below RUN_EXIT falls back to "walk".
		return "walk" if planar_speed < RUN_EXIT else "run"
	# walk / wait / anything else: only a clear climb above RUN_ENTER enters "run".
	return "run" if planar_speed > RUN_ENTER else "walk"


## True when pos is within LEASH_RADIUS (XZ) of the player.
static func within_leash(pos: Vector3, player_pos: Vector3) -> bool:
	return Vector2(pos.x - player_pos.x, pos.z - player_pos.z).length() <= LEASH_RADIUS


## Pick a target from candidate dicts [{pos: Vector3, alive: bool}, …].
## preferred_idx is the index of the player's primary reticle target (-1 for
## none): if that candidate is eligible it wins outright (assist priority);
## otherwise the eligible candidate nearest the COMPANION wins. Eligibility =
## alive and within the leash of the PLAYER. Returns the chosen index, -1
## when nothing is eligible.
static func select_target(candidates: Array, player_pos: Vector3, companion_pos: Vector3, preferred_idx: int = -1) -> int:
	var best_idx := -1
	var best_dist := INF
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		if not bool(c.get("alive", false)):
			continue
		var pos: Vector3 = c.get("pos", Vector3.ZERO)
		if not within_leash(pos, player_pos):
			continue
		if i == preferred_idx:
			return i
		var d := Vector2(pos.x - companion_pos.x, pos.z - companion_pos.z).length()
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


## Attack payload for one swing (always combo step 1 — no companion combos in
## phase 1). attack/accuracy are the companion's class stats; config is the
## shared CombatManager weapon-type config. Receiver-side defense/evasion/crit
## stay in the enemy's _on_hit_received — this is only the raw hit.
static func compute_attack(attack_stat: int, accuracy_stat: int, config: Dictionary) -> Dictionary:
	var damage_mult: Array = config.get("damage_mult", [1.0])
	var knockback: Array = config.get("knockback", [3.0])
	var hits: Array = config.get("hits_per_step", [1])
	var raw := maxi(int(float(attack_stat) * float(damage_mult[0]) * COMPANION_DAMAGE_SCALE), 1)
	return {
		"damage": raw,
		"knockback": float(knockback[0]),
		"hits": int(hits[0]),
		"accuracy": accuracy_stat,
		"max_targets": int(config.get("max_targets", 1)),
	}


## True exactly when the swing clock crosses the damaging frame this tick —
## prev_elapsed strictly before it, elapsed at/past it. One damaging frame
## per swing; a non-positive swing_length never fires.
static func swing_crossed_damaging_frac(prev_elapsed: float, elapsed: float, swing_length: float, frac: float) -> bool:
	if swing_length <= 0.0:
		return false
	var t := frac * swing_length
	return prev_elapsed < t and elapsed >= t
