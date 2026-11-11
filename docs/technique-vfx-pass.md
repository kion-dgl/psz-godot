# Technique VFX pass (#797)

Baseline: main 425f85a3, following the approved Force palette in #794.
Work branch: codex/797-technique-vfx.

## Audit and visual contract

Foie and Barta currently share Projectile's small emissive sphere. Rafoie uses
an expanding generic sphere; Rabarta emits ten generic spheres. Resta changes
HP and shows a number without a spell-specific visual. Charge uses the shared
model glow, rising particles and optional debug timing ring. Projectile sweeps
already own hit timing and world cover in the aim prototype.

The first presentation pass uses an orange/gold flame with a short tapered tail
for Foie, a low cyan crystal cluster for Barta, and mint/gold rising motes with
an open ring for Resta. Silhouettes must distinguish spells without relying on
colour. Bodies stay compact; transparent effects must respect depth and never
hide enemies behind cover. No full-screen bloom, dynamic lights or opaque AoE
shells. Palette timing circles remain the authoritative input/recovery cue.

Release begins at the existing effect dispatch. Contact sparks begin at the
existing projectile contact, not after an animation timer. Sparks mean contact,
not a guarantee of damage/status. Resta's success pulse follows an actual HP
increase; full-health casting gets a smaller neutral pulse. Charged Rafoie uses
an open expanding fire ring at its existing explosion centre; Rabarta reuses ice
crystals on the existing ten projectiles. Resta charge keeps the same healing.
No level-dependent visual tier is invented.

Presentation nodes own no collision, damage, PP, targeting or action timers.
Projectile children die with their projectile; independent bursts have bounded
lifetimes and belong to the current scene. Existing charge cancellation remains
shared with other attacks. Asset catalogue models are optional and not present
in this clean checkout; this first pass uses procedural meshes/materials, with
no claim of exact PSZ asset or animation fidelity.

## Review still required

Normal, shoulder and lock-on views on FOmar/rod and FOmarl/wand; repeated and
overlapping casts; misses, world contact, interruption/defeat and scene exit.
Owner acceptance and before/after gameplay footage are required before closing
#797. Shared charge presentation is a subsequent part of the same issue.

## Initial implementation validation

The rendered standalone effect probe passes: distinct travel visuals preserve
collision radii, healing expires, projectile removal destroys travel visuals,
100 simultaneous bursts fully expire, and scene removal destroys unfinished
bursts. The approximately 0.2-second stress interval includes the intentional
0.2-second wait; it is not a frame-time benchmark. Initial image capture:
`/tmp/psz-tech-vfx-captures/technique-vfx-first-pass.png`.

FOmar/rod and FOmarl/wand each pass 83 live fixture assertions using
`python3 scripts/tools/run_ranger_aim.py --check --class fomar --weapon rod`
and the equivalent `--class fomarl --weapon wand`. Both report DONE ok,
including real Foie/Barta contact and PP consumption, Resta healing, charge and
recovery cues, aim/lock and loadout switching. Both also emit an ObjectDB / one
resource-in-use warning at process exit; its origin is not established by this
pass. The dedicated VFX probe confirms zero remaining technique_visuals nodes.
The clean worktree required local assets and their import cache from the existing
prototype checkout before these real-rig checks could run.

Repeat the effect probe with:
`python3 scripts/tools/run_ranger_aim.py --check --scene res://scripts/tools/technique_visual_probe.tscn`
Add `--rendered` and set `PSZ_BOSS_SCREENSHOTS` to capture the visual preview.

This is an initial implementation, not completion of all #797 acceptance items.
No issue closure or fidelity-grade promotion is justified yet.

## Owner playtest feedback — November 11

Foie needs a convincing fireball; Barta should harden and dissolve along a
progressing line; Zonde looks good. Revised Foie to a turbulent shader-driven
orb/plume. Base Barta emits stationary ice sections at 0.5-unit intervals along
the actual swept path (clipped at world contact). Each section grows for 0.09s,
holds until 0.22s and dissolves by 0.6s. Remaining ice is visual only and cannot
hit again. Rabarta retains radial shards; Zonde is unchanged. Existing damage,
projectile speed, range, collision radius, cost and casting timing are preserved.

Rendered effect probe passes continuous ice emission and bounded cleanup;
shader compilation succeeds in the rendered Compatibility backend.

## Barta reference-driven revision

Owner approved Foie and supplied four ice references. Barta now uses locally
seeded, irregular bevelled masses with broad caps, varied height/lean/width,
3–5 pieces per group, nonuniform spacing, and staggered emergence. The local RNG
does not advance gameplay's shared random stream. Ice alpha varies around
0.28–0.70 before growth/dissolve fades; the floor remains visible through it.
A depth-tested animated frost cloud moves at the front, with short-lived haze
around the trailing formations. The old repeated pointed cones are removed
from base Barta. Foie and Zonde are unchanged by this revision.

Verified rendered Compatibility shader compilation, outward mesh winding,
continuous emission, cleanup including scene removal, and live Barta PP/contact
plus charged release. Inspected normal and side-view Coliseum captures. This
revision retains the existing collision/damage path and 0.6-second visual expiry.

## Range and tilt playtest iteration

Owner found Barta's reach excessive and asked for varied tip angles. Trial
player base-Barta travel distance is 9 units (was 15); aiming uses the same range.
Enemy profiles retain their authored distances. Each ice mass now receives
independent pitch and roll in ±0.7 radians, plus varied yaw, around its ground
anchor. Foie, Zonde and charged Rabarta are unchanged.

## Owner acceptance — November 11

Owner accepted the shortened Barta reach and varied ice angles ("looks good")
and requested commit/push. Foie was accepted earlier; Zonde was assessed as
looking good. This approves the reviewed base effects, not the entire technique
roster. Next focused playtest: charged Foie/Barta/Zonde (Rafoie/Rabarta/Razonde),
then Resta and Anti. Blocked support and Grants/Megid fallback delivery remain
implementation gaps from the roster audit.
