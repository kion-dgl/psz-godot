# Reyburn and Octo Diablo implementation

This branch replaces Reyburn's authored prototype and Octo's generic EnemyBase
AI with dedicated, playable controllers. It is independent of Dark Shrine PR
#753. It supersedes the Reyburn implementation in draft #750; that older branch
should not be merged over this controller. Its forward-facing and full-windup
requirements are retained through descriptor playback and explicit turn states.

The source is psz-re commit 29266e6: overlay-20/21 decompilation, original action
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
- Separate normal/advancing bite counts and 10→11→12 breath. Frame-5 notification
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
  branches therefore remain unavailable to autonomous selection. Timer priority
  rules are recovered, but this is not the complete original selector.
- Octo's absorb/vomit is a visual attack chain; player capture ownership,
  restraint, escape input, eat outcomes and release are not implemented.
  Tentacle placement, incoming spheres, break budget, ranged/sweep contact and
  projectile presentation are provisional. Slam allocation uses the recovered
  local update 3; the complete limb subcontrollers are not ported.
- Octo withdrawal/emergence uses the captured 102/92-update progression after
  the limb wait, with an authored transform relative to the existing arena.
  This is not a fixed half-HP timer, but matching step order alone does not
  validate retail camera, water/collision and spatial transitions.
- Multiplayer target-slot selection, original RNG stream, balance and matched
  full-fight trajectories remain unverified. Existing arena meshes/cameras and
  authored encounter scaling are reused.

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
