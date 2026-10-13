# Reyburn and Octo Diablo implementation

Player-observed requirements and the next-pass acceptance checklist are recorded
in [Boss observations and acceptance checklist](boss-playtest-observations.md).
Use that checklist to drive mechanical work and later original-game comparisons.

This branch replaces Reyburn's authored prototype and Octo's generic EnemyBase
AI with dedicated, playable controllers. The Octo follow-up also integrates
main at 97d3f93e, including the reviewed Dark Shrine PR #753 and Coliseum changes.
It supersedes the Reyburn implementation in draft #750; that older branch
should not be merged over this controller. Its forward-facing and full-windup
requirements are retained through descriptor playback and explicit turn states.

The initial source is psz-re commit 29266e6: overlay-20/21 decompilation, original action
catalogs, and retained melonDS captures. The original research includes 43,300
controller updates across twelve boss runs. Those captures were made during the
preceding research work; this PR replays them and runs Godot, rather than claiming
that a new emulator capture or matched-input full-fight comparison was made.

## What is implemented

`DescriptorBoss` owns descriptor playback, frame-crossing events, combat-window
hit memory, post-subtraction damage hooks, projectiles and one-shot death cleanup.
`BossActionClock` uses 30 action ticks/sec and seeks the converted 60-fps curves.
It retains catch-up time across action changes. Damage does not force a generic
flinch over a boss action.

`ReyburnController` separates original damage-history and request selection from
`ReyburnBoss` scene/movement work:

- Sixteen recovered sequence identities, with turn, bite, breath, wing, tail,
  reaction, jump and aerial state adapters. The old 35%-HP modifier, 22-second
  flight trigger, fixed extra windup and 55%-clip hit timing are removed.
- Base-stat HP budgets, inclusive side-hit bearing, completion-time counter
  resets, ordered damage/spatial priorities, fallback without reroll and the
  recovered 375/1500/150 timer values. The base row and scaled encounter HP are
  distinct. Existing authored level/difficulty scaling remains in effect.
- Modifier activation at action 2 notification 0 (frame 67), rather than on HP
  subtraction. Head-budget exhaustion queues the separate damage reaction.
- Separate normal/advancing bite counts, including the one-update restart
  handshake: the in-arena 16→16→17→4 intervals match captured 27/27/52 ticks
  (original starts 331/358/385/437). Controller entry retains frame zero.
  Breath runs 10→11→12. Frame-5 notification
  releases a single shot or three-shot fan; repeat interval is nine ticks,
  heading spacing is ±0x0e38 and the owned pool is capped at six projectiles.
- Four bone-attached incoming parts share HP and hit ownership. Melee cone scans
  choose an actual eligible part, as do physical projectile contacts. Hit source
  and receiver-part context now reach the post-damage hook. NSBMD joint indices
  12/18 map by name to `atama`/`sippo_02`; GLB bone indices are reordered.

`OctoController` and `OctoDiabloBoss` provide:

- Post-subtraction half-HP clamp in mode 0, deferred transition latch and step
  order 0→2→14→18→0. Body completion starts the wait for independently active
  limbs. Withdrawal changes mode before emergence clears the latch; lethal
  damage is allowed once mode is 1.
- Body spout 8→9→10→11→1, aim wait up to 30 updates, frame-5 notification,
  difficulty-dependent repetition and projectile-row weights [90,0,10]/[0,90,10].
- Body and six separate tentacle AnimationPlayers/clocks. Mode 0 uses four short
  tentacles; mode 1 reveals two long tentacles. Ranged, slam/pull/tear,
  sweep/screw and absorb/vomit chains are playable. Main timer/hit priorities
  are separate from projectile weighting.
- Shared HP for limb hits, local reactions, hidden-limb hurtbox disabling and
  complete channel/projectile cleanup on death. Both arena spawn paths bind HUD,
  rewards and return-warp behavior, and both can be restarted.

## Corrected tentacle animations

The distributed pack's two tentacle meshes had body clips rather than the
part-specific clips. The mesh geometry and textures are usable. Two small
AnimationLibrary resources in `data/boss_animations` replace only those clip
libraries at runtime, and ship with the application export. The pack is unchanged.
All 21 short-tentacle and 16 long-tentacle clips were exported from the corrected
asset-viewer GLBs. Input hashes and reproduction command are in
`data/boss_animations/provenance.json`; exporter:
`res://scripts/tools/export_octo_clips.gd`. The field probe resolves all 35 descriptor
limb actions against these libraries, including animations not yet selected by AI.

## Explicit fidelity gaps

This is an implementation PR for playtesting, **not completed 1:1 parity**.
Do not treat passing component tests as a full original-game fight comparison.

- Reyburn executes all sixteen sequence identities, but flight approach/travel,
  claw motion, landing, running, turn easing, wing movement, jump destination,
  tail recovery and advancing-bite translation still use Godot movement adapters.
  Original root-motion transfer, per-state completion handshake ticks, action
  rate/blend controls and every request parameter are not fully ported.
- The fixed-tick clock covers the imported descriptors used here; it is not the
  full ARM9 animation runtime. Entity speed modifiers and special frame flags
  need differential tests before being generalized to every enemy.
- Outgoing kind-0 circles follow the recovered event origins. Kind-1 shapes
  remain approximate boxes. Original attack-group damage, statuses, effects,
  looping audio and projectile speed/trajectory/variant presentation are not
  reproduced exactly. The modifier currently scales final delivery damage;
  retail scales an intermediate combat packet field.
- Octo's single-player spatial/limb eligibility adapters do not yet port all
  `0219A7E4`, `0219A8C0`, `02199194` predicates or per-source-slot counts. Some
  branches use single-player eligibility approximations. Timer priority
  rules are recovered, but this is not the complete original selector.
- Octo now pulls the player and separates the measured center/edge failure
  paths. Successful capture ownership, restraint, escape input, eat outcomes
  and release are still not implemented: reaching the mouth does not swallow
  or damage the player. Tentacle root placement and incoming spheres remain
  approximations, although hurt parts now follow named animated joints.
  Slam allocation uses local update 3; the complete limb subcontrollers,
  joint-pair volumes and multiplayer selectors are not ported.
- Octo withdrawal/emergence uses the captured 102/92-update progression after
  the limb wait, with an authored transform relative to the existing arena.
  This is not a fixed half-HP timer, but matching step order alone does not
  validate retail camera, water/collision and spatial transitions.
- Multiplayer target-slot selection, original RNG stream, balance and matched
  full-fight trajectories remain unverified. Existing arena meshes/cameras and
  authored encounter scaling are reused.

## Brief Reyburn entrance

The October 12 Mac playtest found Reyburn initially facing away while its long
intro played during live gameplay. The observed original uses an arena-entry
cutscene: player entrance, overhead flight and loop, landing, then opening roar.
The local presentation now compresses that order into 4.5 seconds: 1.6 seconds
of flight, 1 second of landing, and 1.9 seconds of roar. These durations and the
camera/path are authored choices, not measured retail timings. The camera stays
4.5 units behind the player at the normal 1.9-unit height and tracks the dragon.
Landing searches for supported floor roughly 27 units from the player, with a
body-width margin; unsupported candidates are rejected. Player control
and the regular orbit camera return immediately after the roar, with Reyburn
facing the player. Damage and AI scheduling are held during the presentation;
scene exit also releases the player and camera. Live animation pacing and camera
framing still need the next hands-on playtest.

The follow-up playtest found repeated bites immediately after control returned
and continued attacks against the defeated player. An authored pacing layer now
holds attack selection and pursuit for 75 ticks (2.5 seconds) after entry and each
sequence. A completed bite sequence also prevents another bite request for 180
ticks (6 seconds), through both the distance selector and random fallback.
Timings within a bite sequence remain unchanged. The player defeat latch cancels
attack queues and existing projectiles and switches Reyburn to idle; a revived
or replaced player gets a fresh rest period before combat resumes. These values
are playtest tuning, not recovered original-game cooldowns.

## Flight and ground steering follow-up

The next Mac playtest found an off-arena landing, one airborne fireball per
flight, and stationary turret-like ground turns. Aerial cycles now make two or
three fireball passes, relocating between shots, before approaching a supported
landing point. The shot aims down from the head toward the player. Landing
selection raycasts the environment collision mesh at the center and eight points
around a four-unit body footprint, rejects steep or uneven support, and samples
from the established floor height rather than the airborne body height. A failed
landing check triggers a safe approach search; it does not descend at the invalid
position. Jump destinations and advancing bites also use the support check.

Ground pursuit, pre-attack alignment and running now accelerate forward speed
and yaw speed. Turning is capped at 32 degrees/second and coupled to actual
travel, so blocked movement cannot rotate the body in place. An obstructed path
tries a short reverse, and an alignment that times out abandons that request
rather than snapping toward the player. These movement rates, the aerial path,
and pass counts are authored adapters to the playtest observations, pending
comparison with original-game movement. The live probe covers all three aerial
sequences, actual fireball deliveries, relocation, off-mesh recovery and steering.

## Ground contact and attack positioning

The following playtest found occasional floating feet, excessive circling,
walking through the dragon, and repeated damage from footstep windows. Ground
locomotion now applies the sampled collision-floor height to the body. Repositioning
chooses a supported flank destination, dashes toward it, then turns back for a
fireball. It commits once range and bearing allow the existing pre-attack turn
to finish alignment; a denied firing angle ends the maneuver after seven seconds.

Reyburn uses a full-width cylindrical torso on a dedicated solid-boss collision
layer. The player now collides with that layer as well as the environment; other
enemy body layers are unchanged. Ordinary walk/run descriptor combat windows are
suppressed while their sound events remain active, avoiding footstep damage chains.
Deliberate attack windows remain active. These are authored playtest changes, not
claims about recovered original footstep damage rules. Live probes verify player
movement is blocked by the torso, floor following, harmless locomotion, immediate
fireball selection from a usable vantage and bounded repositioning.

## Playtest

Open **Coliseum Master → Bosses → Reyburn / Octo Diablo**, or the existing
`DEBUG: Reyburn Arena` and `DEBUG: Octo Diablo Arena` counter missions.

For Reyburn, compare bite windups, head/tail targeting, side-hit reactions,
breath fan, modifier reaction and complete aerial return. Watch for unreachable
positions or lingering damage after death. For Octo, attack through half HP:
the body should finish its attack, wait for limbs, withdraw and reveal the long
tentacles. HP can drop below half once mode changes, before emergence finishes.
Defeat each boss, return, and retry with fresh HP and channels.

Automated entry points (use isolated save directories):

```sh
XDG_DATA_HOME=/tmp/psz-ro-tests godot --headless --path . res://scripts/tools/test_runner.tscn
godot --headless --path . --script scripts/tools/test_boss_action_events.gd
XDG_DATA_HOME=/tmp/psz-ro-probe PSZ_REYBURN_OCTO_CHECK=1 PSZ_PROBE_PACK=/path/to/assets.pck \
  godot --headless --path . res://scripts/tools/coliseum_probe.tscn
```

The field probe uses actual arena spawning and rigs, controlled action stepping,
incoming damage, real player melee, shared-part hit deduplication, modifier
notification, all sixteen Reyburn sequences, spout delivery, Octo transition,
independent channels, HUD, death, rewards, return warp and repeated encounters.
Set `PSZ_BOSS_SCREENSHOTS` when running with a display for framed rendered images.
Two fresh retries additionally run autonomous boss selection against a scripted
player orbit and real damage calls, reaching late phase without action/phase
injection. It is an integration probe, not an autonomous player completing a fight.
The existing `PSZ_BOSS_LIFECYCLE_CHECK=1` probe remains supported.

Scorecard: Bosses (`score:bosses`) and Combat (`score:combat`). Bosses next-review
wording is updated; owner grade/date remain unchanged pending Kion's Mac playtest.


## Octo follow-up for Mac review (2026-10-12)

Based on **psz-re b1f69d0**, `docs/octo-encounter-followup.md`, the retained
8,100-update center trace, 5,207-update edge/death trace, and separate successful
ink-hit probe. The Godot changes do not claim a new matched-input emulator run.
Reyburn's reviewed controller and captured bite timing remain unchanged.

- **Spawn correction:** the generic floor-repair routine previously moved Octo
  from the water opening to the nearest plank, twelve units away. Octo now keeps
  its authored spawn; both phases and recoil share the correct center anchor.
- **Intro:** channel 2 rises at update 25, hides at 85; channel 1 rises at 90,
  hides at 150; the body rises at 180; play resumes at 240. A behind-player
  camera tracks these reveals and restores the prior camera/control state.
  These are authored camera views at recovered boundaries, not imported retail
  camera curves. The first rise is supported by static code, not the late save.
- **Center suction:** actions `12→13→15→16→17→18→2→4→1`, with intervals
  **61/91/21/16/35/41/181/21** updates. Pull is collision/floor-aware and below
  normal running speed. Vomit recoils the entity nine units, then exposes the
  tired body for 181 updates (about six seconds), followed by a 25-update return.
- **Edge suction:** `12→13→14→3→4→1`, intervals **61/154/31/151/23**. No recoil;
  tired recovery lasts 151 updates (about five seconds). Both currently take
  the failure path; successful swallow/capture remains a parity gap.
- **Requests:** 17 spins the body, with the recovered radius-17 contact window
  `[30,90)`; 12 runs the two screw clips (contact starts at local update 45);
  13 moves to another octagonal side; 15 temporarily reveals short channels 3/4
  while turning, then returns to the two long tentacles. Side movement uses a
  tuned 18-unit radius/120-update arc, not a recovered movement curve.
- **Tentacles:** short limbs face outward with separate raised/stretched waits.
  A nearby available limb attacks instead of starting all four slams together.
  Incoming spheres now follow `Point07`/`Point10`, mapped by original model
  names; short parts use 3–6, long parts 11/12. Exact joint-pair volumes and
  secondary parts are still missing. Waiting damage reactions use strict
  `> maxHP/5`, replacing the unconditional one-tenth-HP reaction.
- **Ink:** only variant 1 (combat record 6) can poison. Base chances are
  50/100/100 percent by difficulty. Player poison uses the recovered 150-update
  interval and 1230/1380/1530-update durations, and clears through existing
  status recovery. The remake's generic 5%-max-HP DoT and absent retail status
  resistance/immunity rules are explicit balance gaps. Other variants do not
  install poison; dodge/defeat/recovery guards remain in effect.
- **Defeat:** action 21, procedural sinking during updates 20–109, hidden at
  110, cleanup at 181. Camera/control restores and rain/lightning stop; the
  existing cloudy sky receives an authored brighter grade. New encounters
  restore the storm. Original event flags, palette and sink curve remain open.

The imported octagonal plank mesh and collision are reused. This is not a claim
of proven original collision masks, melee reach, full attack damage/effects,
independent four-player limb selection, or successful suction capture parity.

### Mac review route

Pull `feature/reyburn-octo-behavior`, then open **Coliseum Master → Bosses →
Octo Diablo** or **DEBUG: Octo Diablo Arena**. Watch the intro before moving.
Circle the central hole and try melee on raised/stretched joints. Bait suction
and run away; compare the center recoil/stun to the shorter edge recovery.
Attack through half HP, check the two long tentacles and movement to another
side, then check ink poison, defeat sinking, cleared rain/cloudy sky, return,
and a fresh rainy retry. Report camera clipping, inaccessible hurt locations,
movement through planks, and phase/death stalls. Successful swallowing is not
available in this build and should not be mistaken for an accidental regression.

The arena probe now asserts original suction action-start timestamps, recoil,
intro order, spin completion, joint attachments, both edge movement requests,
poison cadence/cleanup/dodge, 181-update defeat, weather reset, and the existing
Reyburn sequences/rewards/HUD/return/retry checks. It uses controlled stepping
and a scripted player orbit; it is not a full human-play balance test.


### Integration with current main

Merged main `97d3f93e` after GitHub reported conflicts with #753. The reviewed
Reyburn controller, selector and `BossActionClock` remain byte-for-byte unchanged.
The shared descriptor helper retains Shrine aiming/projectile-origin hooks and
supports its single capsule/head receiver in the multipart target scanner.
All four boss dispatch entries, standard Shrine camera, Trinity anchor, current
Coliseum controls and both probe entry points are retained.

## Octo playtest corrections (2026-10-12)

The opening now faces the player, central spin retains four extended tentacles,
and edge placement samples the actual outer plank collision boundary instead of
using the fixed 18-unit radius. Long tentacle roots flank the body. Suction has
procedural inward wind streaks. Defeat fades rain over four seconds and blends
the cloudy sky over six seconds while preserving the starting sky material.
Weather tweens belong to the surviving arena nodes, so boss cleanup does not
interrupt them. All values remain authored tuning; visual acceptance is pending
against P01–P06 in the observation checklist.
