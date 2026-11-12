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

## Resta/Anti party support and PSO audio

Owner requested party AoE, recipient particles and PSO sound cues for Resta,
Anti, Foie, Barta and Zonde. Support now checks a 6-unit 3D radius at release,
including caster and living registered companions, without a line-of-sight gate.
Healing clamps per-recipient HP; Anti removes actual recipient ailment state.
Out-of-range, dismissed and defeated allies are excluded, as are enemies.
Success feedback follows only actual mutation; the caster still shows an area
ring for an empty/full-health cast. Recipient particles last at most 1.5 seconds
and follow their actor; the stationary radius ring fades in 0.55 seconds.

Companions previously had no HP/status recipient contract. This adds runtime
HP from class stats and curable ailment records. It does not implement enemy
retargeting, companion damage/ailment combat behavior, resurrection, persistence
between scenes, or multiplayer networking. The playtest explicitly injures and
poisons stationary real companions to exercise this support path.

PSO source mappings from data/sfx_labels.json:
- Foie: common_132, SE_PL_FAIOSHOT
- Barta: common_136, SE_TECH_BATA
- Zonde: common_140, SE_TECH_ZOND
- Resta: common_146, SE_TECH_RESTA
- Anti: common_148, SE_TECH_ANTI — catalogue notes conflict with the label;
  this is an audition candidate pending owner listening, not verified original timing.

One positional cue plays at accepted release, respecting the SFX bus. No sound
on rejected casts. Audio is staged in the ignored assets/sfx tree from the local
PSO library; asset-pack publication is still required for distribution. Recreate
with scripts/tools/prepare_playtest_audio.py --source PATH_TO_psobb_sfx.
The support playtest starts on bank 2: F5 poisons the party, F6 lowers HP, F7
moves Kai near/far; Sarisa starts nearby. Readouts expose HP and poison state.

Validation: rendered party-support probe passed 23 checks, including actual
near/far companion mutations, HP cap, defeated exclusion, enemy exclusion,
recipient-only particles, cleanup, no-op cure, insufficient-PP suppression,
and loading all five staged PSO cues. Normal-view screenshots show Resta and
Anti particles attached to both caster and Sarisa. Owner sound/visual approval
remains pending, especially the ambiguously annotated Anti sample.

## Shifta party cast and persistent wrists

Owner requested the same area delivery as Resta, a red cast circle and glowing
red wrist clouds while active. Shifta now uses the shared 6-unit recipient query
and its actual learned level. The existing +10% attack per level formula is
reused; a provisional 60-second runtime duration replaces turn counting for the
3D field. Recast refreshes duration and keeps the stronger amount, never stacks.
Legacy and runtime player Shifta use the larger bonus once. Companion attacks
consume the same runtime effect. This is an ATK stat buff, not technique power.

The buff node owns its timer and two wrist clouds, positioned from actual
070_RArm02 / 040_LArm02 skeleton poses each rendered frame. It reacquires the
skeleton after model changes. Missing wrist bones suppress those indicators
rather than inventing a body attachment. Expiry, defeat/dismissal and scene exit
remove the runtime bonus and effects. Runtime Shifta is not saved.
PSO SE_TECH_SIFTA/common_152 is staged alongside the existing technique cues.

Rendered verification passed nine checks: cost, near/far recipients, actual
player/companion attack stats, both wrist bones on both rigs, PSO cue loading,
nonstacking refresh, defeat cleanup and simultaneous stat/visual expiry. Capture:
/tmp/shifta-captures/party-shifta.png. Owner visual/tuning acceptance pending.

## Owner sound audition corrections — November 11

These supersede the initial filename-based selections and are recorded as owner
listening feedback, not independently recovered original-game dispatch:

| Use | Source label | common sample |
|---|---|---|
| Foie cast | SE_EP4ITEM_W44 | 120 |
| Barta cast | SE_EP4ITEM_WH26 | 124 |
| Zonde cast | SE_W27_SHOOT | 128 |
| Shifta cast | SE_TECH_ZOND | 140 |
| Resta cast | SE_TECH_RAFOIE1 | 134 |
| Anti cast | SE_TECH_RAFOIE2 | 135 |
| Shifta applied to recipient | SE_TECH_RAZONDE | 142 |
| Poison HP tick | SE_PL_POISON | 011 |
| Stun applied | SE_PL_PARALYSIS | 012 |
| Slow (reserved mapping) | SE_PL_SLOW | 013 |

Poison bubbles no longer own an independent audio loop. Poison's actual damage
clock now emits the cue once per HP-loss tick, with none after curing. Stun emits
its cue on accepted application. The slow cue is staged and mapped, but no 3D
slow behavior is invented here. Shifta plays the cast cue once and the power-up
cue at each successful recipient. Existing source labels/notes are preserved;
remake-use annotations in data/sfx_labels.json record the owner correction.

Rafoie, Rabarta and Razonde have completed owner playtesting for this pass.
Deband is next in the support sequence and still needs delivery, defense bonus
and presentation work.

### Rafoie focused follow-up

K is reserved for palette slot 2; Kai positioning remains on F7. The roster check now sends real K press/release events and checks charge readiness and PP timing. `PSZ_TECH_FOCUS=rafoie` starts the normal Foie/Barta/Zonde palette with stationary 10,000 HP targets (R restores them). Hold J to charge Foie into Rafoie, then release.

Rafoie uses owner-selected SE_EP4ITEM_WH02 at cast and SE_EP4ITEM_WH11 at the target explosion. The blast grows into layered turbulent fire spheres with a five-unit radius and center two units above the impact ground, leaving 30% of its diameter below ground. The existing damage/range rules remain unchanged. Accepted during owner playtest.

Rafoie revision: two fire shells plus a red ground ring expanding to the five-unit damage radius. Palette technique release now requires completed charge; early release cancels without casting or PP cost. Keyboard audit covers early-release cancellation as well as charged release.

Palette follow-up: P refills PP only in the Force fixture; F5 retains poison and U refills HP/PP. Technique icons now desaturate and dim dynamically for insufficient charged-spell PP, unlearned/unsupported techniques, CAST restriction, defeat, attack-blocking ailments, and combat recovery. Empty consumables retain their count and also desaturate. Other combat-action availability is unchanged.

### Rabarta radial ice pass

Replaced ten shard projectiles with a continuous translucent, rumpled ice sheet spreading from the cast location at 12 units/sec to the existing eight-unit range. Staggered Barta ice clusters with rounded tilted caps and ground frost emerge along the sheet, then dissolve. The circular sweep damages each eligible enemy once when reached, with world-cover ray checks; it no longer leaves gaps between projectile spokes. `PSZ_TECH_FOCUS=rabarta` provides durable stationary targets; hold/release K, P refills PP. Accepted for now after the contrast revision below.

Rabarta intensity revision: radius reduced from eight to four units; propagation increased from 12 to 28 units/sec (~0.14 seconds to full radius). Stronger blue/cyan translucent sheet, larger ice clusters, and 24 expanding ground-mist billboards. SE_EP4ITEM_S52 (common_126) plays on release.

Rabarta contrast revision: five-unit radius at 16 units/sec (~0.31-second expansion). Fresh ice has an emissive white-cyan leading band, settling into softer translucent pale blue behind it. Mist trails inside the edge and fades relative to the propagation duration.

### Razonde chain pass

Replaces simultaneous overhead strikes with a caster-to-enemy jagged white-core/blue-halo bolt and sequential enemy-to-enemy links spaced 0.12 seconds apart. Prefers the selected eligible target, otherwise nearest; each enemy once, at most ten, eight-unit hop range within the existing twelve-unit cast area. World cover blocks links. SE_W27_HEY (common_130) plays on release. Focus fixture: hold/release L, P refill. Rabarta accepted for now; Razonde accepted after the shared-Zonde-shader revision below.

Razonde visual consistency: chain links now use Zonde’s existing additive FBM lightning shader, matching colors, width and fade timing. An opt-in axis-facing mode orients the same effect between endpoints; default vertical Zonde rendering is unchanged.

### Deband, Jellen and Zalure (2026-11-12)

All three use Shifta's six-unit area, sixty-second refreshable duration and ten-percent-per-level modifier. Deband applies to living self/party and increases defense; Jellen and Zalure apply only to living enemies, reducing attack and defense respectively (capped at 90% reduction). Recasts retain the stronger amount without stacking. Attack clouds/circles are red; defense clouds/circles are blue. Humanoids resolve wrist bones; creatures without arm bones use paired side indicators. Companion defense is exposed in their stats, but enemy retargeting/damage to companions remains separate work.

Owner audio mapping: Deband common_142 (SE_TECH_RAZONDE), Jellen common_141 (SE_TECH_GIZONDE), Zalure common_143 (SE_TECH_MEGIDO). Grants cast common_132 and Megid common_131 are tentative audition mappings; Grants impact common_133 is reserved until its dedicated delivery replaces the existing fallback. Box break already uses common_160 (SE_TECH_CHARGEFIRE). Audio copied locally using the preparation script, not published.

Playtest: PSZ_TECH_SUPPORT=1 PSZ_TECH_FOCUS=buffs; hold/release J/K/L, P refills PP.

Debuff differentiation: Jellen and Zalure now emit paired downward red/blue droplets at their wrist/side anchors instead of showing buff clouds. Droplets fall in world space, fade within 0.55 seconds, and are owned by the status node so expiry/death removes them. Shifta and Deband retain their glowing clouds.

### Grants and Megid prototype

Debuff droplets reduced from 18 to 6 per anchor. Grants replaces its Foie fallback with a 0.95-second rainbow shimmer on one target, then a rising light pillar and one damage event; it retains the level-one 50 PP cost, plays common_132 on cast and common_133 on impact, and cancels safely if the target disappears. No target means no PP cost. Megid is a translucent purple straight projectile with sparse falling droplets, speed 12/range 15 and world collision. It retains 40 PP and uses the existing turn-combat 20% + 1%/level instant-death chance; resisted hits do no fallback damage, bosses are immune in this prototype. Successful hits use the enemy death lifecycle. Focus light_dark: J Grants, K Megid, P refill. These remain diagnostic grants, not new learnable disks.

Megid now pierces an unlimited number of distinct targets along its straight path, rolling once per target. Enemy contact does not consume the orb; its 15-unit range or world collision ends it.

Megid correction: a failed instant-defeat roll now delivers the calculated dark-technique damage through the normal hurtbox path. Boss immunity applies only to instant defeat, not ordinary damage. Piercing and once-per-target contact remain unchanged.

Revive playtest: yellow Reverser cast circle and a rising golden halo on the revived recipient. Nearest defeated local companion within six units receives 10 + 2/level HP; no eligible recipient costs no PP. Sarisa starts at zero HP in the downed animation; N downs her again. The halo also accompanies the existing player Scape Doll revival. Player return-to-city defeat handling is unchanged. Grants and Megid now cast on press with no charge.

Reverser now casts on quick release without requiring charge: nearest defeated ally, existing level-scaled HP. Optional full charge revives all defeated allies within six units to at least half HP. Both cost one normal cast; charge balance is provisional.

### Merge validation and audio delivery

Code-health cleanup split visual construction/ticking, support revival, wrist lookup, and light/dark dispatch without changing their behavior. Full local suite: 14,816 passed, zero failed. The development asset pack was rebuilt from the current published pack plus 19 selected technique/status sounds (raw WAV, import remap and sample per cue); all 20,954 original entries were verified byte-for-byte unchanged and the added streams loaded successfully. No existing packs were pruned. The updated asset manifest/tree deliver these cues to fresh installs.
