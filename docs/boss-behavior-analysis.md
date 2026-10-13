# Boss behavior analysis for the Godot port

Updated 2026-10-11 after running the original game in melonDS. The first version
of this review was static-only and too shallow. The new evidence includes
**43,300 controller updates in twelve complete runs**, inspected screenshots,
and eleven boss action catalogs regenerated from the ROM. **The current Godot
bosses are not yet 1:1.** This change supplies research and implementation data;
it does not replace the gameplay controllers. Original-frame event dispatch and narrow damage-hook rules are implemented and replay-tested as reusable runtime components.

Read the full [live behavior analysis](../../../psz-re/docs/boss-behavior-live.md)
for controller/state layouts, source addresses, attack execution, all boss
families, reproduction commands, and remaining parity tests. The imported
[boss behavior contract](../data/re_reference/boss_behavior_contract.json)
contains action stages, clip frame counts, Q12 playback rates, notifications,
combat windows/shapes, the complete Reyburn sequence table, and measured timelines.
Original traces and screenshots are retained in
[psz-re/data/traces/boss_live](../../../psz-re/data/traces/boss_live).

## Changes in understanding that affect implementation

| Prior assumption | What the deeper analysis establishes |
|---|---|
| Reyburn enrages below 35% HP | The actual modifier follows a damage budget, a reaction sequence, and animation notification 0. Natural capture: flag 40 at 318/1650 HP, tick 13554, after spending a 1320-point budget. |
| Budget fractions can use actual max HP | Reyburn's capture initializes budgets 660/1320 from the base 3300-HP stat row, while actual max HP is 1650. Its separate cumulative-damage gate does use actual max HP. |
| Historical HP writes showed no phase changes | Those experiments watched the wrong controller: entity+D4 points to visual work; AI is entity+10 with a backlink at controller+4. HP writes also do not recreate accumulated damage. |
| Reyburn counters reset on state entry | They reset at sequence completion. Sequences 8/14 can retain off-angle damage on a 50% roll under flag 40. |
| Reyburn chooses one random attack | It uses pending/current requests, ordered counter/spatial checks, timers, a four-way fallback, and sixteen multi-state sequences. |
| Octo's 90/0/10 rows choose its three attacks | They choose **spout projectile variants** inside the animation notification callback. Main attack selection is a different controller function. |
| Octo enters phase 2 immediately below half HP | It clamps HP at half in mode 0, latches a transition, waits for state boundaries, and runs steps 0→2→14→18→0. Mode changes before the transition latch clears. |
| One animation channel per boss is sufficient | Octo uses body channel 0, short tentacles 1–4, and long tentacles 5–6 concurrently. Robots also use separate channels/controllers. |
| Hit timing must be guessed | The descriptor provides stage/frame events. Live hooks confirm Reyburn bite windows 10–23 and 20–37; the second bite uses root motion. |
| A `lp` clip means an infinite loop | Tower Mother gun and technique clips are repeatedly restarted by their controllers, despite non-looping descriptor flags. |

Do not convert the measured Reyburn result into a new universal 20%-HP enrage
constant. The original mechanism depends on damage history, base-stat scaling,
state eligibility, and a reaction notification. Do not convert debugger wall
time into attack duration. Captures count controller calls, not display frames.

## Tested Godot component

[`BossActionEvents`](../scripts/3d/enemies/boss_action_events.gd) consumes actual animation stage/frame positions and emits original descriptor point events, window starts/updates/ends, and interruption cleanup. Use one instance per model channel. It does not advance animations or choose attacks, and is not yet wired into the authored Reyburn controller.

The headless [replay test](../scripts/tools/test_boss_action_events.gd) matches **49 anchored Reyburn bite windows**, **seven Octo spout notifications**, and Reyburn's modifier notification to the captured original-game ticks. One bite begins before tracing and is excluded from absolute-start replay; its duration is checked in RE. [`BossDamageRules`](../scripts/3d/enemies/boss_damage_rules.gd) also matches the two positive-guarded Reyburn budgets across 167 original hits and Octo's clamp across 78 post-hit samples. It does not implement the independently resetting damage accumulators or scheduler. Boundary checks cover part-budget exhaustion and lethal hits on either side of Octo's mode switch. The combined test is registered in CI. These are narrow component comparisons, not full boss parity.

```sh
godot --headless --path . --script scripts/tools/test_boss_action_events.gd
```

Validation on Godot 4.5.1: the focused boss replay exits 0, and the field-layout
suite reports 36 passed / 0 failed. The general test runner exits 0 and reports
2,580 passed / 0 failed, but also logs an existing `get_rotated_gates` missing
method in `test_runner.gd:8293` against `grid_generator.gd`. Both files are
unchanged by this work; that run is not a clean all-tests-passed result.

## Current implementation gaps

[`reyburn_boss.gd`](../scripts/3d/enemies/reyburn_boss.gd) still contains authored
35% enrage, speed/cooldown multipliers, a 22-second flight interval, fixed
0.35-second telegraphs, damage at 55% of clip duration, and partial chain playback.
Its attack selector and movement do not execute the recovered sixteen sequences.
The original has a three-projectile fan variant as well as timed emission;
replacing every fan with sequential single shots would also be wrong.

[`cell_object_spawner.gd`](../scripts/3d/field/cell_object_spawner.gd) selects a
specialized class only for Reyburn in `_spawn_enemy`; other bosses fall through
to `EnemyBase`. `_spawn_boss` also hardcodes the Reyburn class. Arena and animation
assets alone do not implement another boss.

The damage path must expose source handle/position and receiver part to a boss
hook, permit post-subtraction HP adjustment before death resolution, and avoid
forcing generic hurt animations over controller-selected boss actions. The
shared HP owner still needs attack-window deduplication across multiple parts.

Combat descriptor shape records are **outgoing planar attack geometry** and are
not interchangeable with incoming damage-part bones. Each class-0 event selects
a shape and attack group, and specifies entity/joint coordinates and local X/Z
offsets. The imported contract preserves these distinctions.

## Boss-specific implementation direction

**Reyburn:** port request/current/pending state, sixteen sequence lists, damage
budgets and directional hit history first. Then port turning, bite repetition,
root motion, breath emission, wing movement, tail turns, flight variants, and
jump interpolation. Drive modifier activation from action 2's frame-67 event,
and preserve the outgoing packet multiplier and enhanced sequence variants.

**Octo Diablo:** implement a body controller plus independently advancing limb
work. Add the mode-zero half-HP clamp, deferred transition steps, and separate
spout projectile selection. Preserve target ownership during absorb/eat/vomit,
per-source hit counts, limb damage reactions, and model-channel independence.
The no-write natural crossing provides a reference transition timeline.

**D Chaos/D Mobius and Humilias:** one entity class owns three subordinate
controllers. Species 63/65 choose different opening states; split/combined state
synchronization and continuous HP-based parameter interpolation are in source.
Paru and Arca captures use different animation channels and action tables.

**Mother Trinity:** keep three Mother Piece entities and their HP/controllers
separate from the main body. Piece-count reductions, a body damage budget, and
body flags drive requests. The present live trace covers the piece stage; later
body exposure and encounter completion remain to be captured.

**Dark Falz:** remaining-HP checks use strict `< half` and `< quarter`, with the
quarter branch taking priority. The main AI also tracks stance, damage history,
target handles, and subordinate objects. A seeded-HP experiment crossed both
thresholds through actual hits and recorded the flag changes.

**Blade/Shot/Force/Heaven's Mother:** the shared overlay-23 controller has explicit
species-based style selection. Blade uses target-relative displacement and
near/far attacks; Shot has persistent gun control and controller-managed bursts;
Force warps, waits, and casts a weighted selection with 1–3 repetitions and a
damage-interruption path. Heaven's Mother changes styles and has additional
species-specific shot/cast branches. No live tower-Mother state was available;
these behavior interpretations are static evidence pending emulator tests.

## How to use the contract

The catalog is keyed by original archive name. An `actions[index]` entry contains
ordered `stages` and `events`. An action ID is not an animation slot. Events carry
both stage indices and frames; window events carry a start and end. Q12 rates
are multipliers, not frames per second. `shape_index` points into that archive's
`shapes`; `attack_group` selects another part of the original combat pipeline.
It is not already a final Godot damage number.

`reyburn_layout.sequences` names controller fields whose state entry/update
addresses are in `reyburn_layout.states`. `runs` contains measured changes and
animation calls, and `observed_checks` records the narrow assertions checked
against the original-game captures. These fixtures are a basis for differential
tests, not a substitute for implementing the controllers.

Regenerate and check in psz-re:

```sh
python3 tools/boss_behavior.py --check
```

After regeneration, copy `data/boss_behavior_contract.json`, `boss_reyburn.json`,
and `boss_octo_diablo.json` into this directory's `data/re_reference/`. The latter
two retain historical notes with explicit corrections so old consumers do not
silently reuse the invalid controller and attack-weight interpretations.

## What must pass before calling the port 1:1

Replay matched initial state, inputs, targets, and RNG, comparing action/channel,
state progression, frame-event boundaries, motion/facing, damage/clamps/counters,
projectiles, collision parts, statuses, capture/release behavior, and defeat.
Cover complete fights, different distances/bearings, difficulty/scaling,
interruption, and large hits spanning thresholds. Then compare rendered motion
and arena interactions in the emulator and Godot. **Those end-to-end Godot
comparisons have not yet been performed.**

## Dark Shrine test encounters (2026-10-12)

The dedicated `DarkFalzBoss` and `MotherTrinityBoss` now replace generic melee AI
when these IDs spawn. `DescriptorBoss` shares action playback, event dispatch,
post-damage hooks, projectile ownership and death cleanup. `BossActionClock`
advances the ROM descriptors at 30 ticks/sec and seeks the imported 60-fps GLB
curves, instead of guessing damage from a percentage of a clip. Integer action
durations and Trinity's activation notification are tested against the retained
seeded emulator capture in `data/re_reference/dark_shrine_bosses.json`. This is
not a claim of complete scheduler/animation runtime parity.

Trinity now uses `boss_mother` (source 66), including its matching stat rows.
The old resource incorrectly used tower `mother` (57). The legacy `humilias`
resource also uses source 66; that separate authored encounter is unchanged and
remains explicitly unresolved in the roster audit. Three pieces use their own recovered difficulty rows (1600/3850/5000 base HP),
independent HP and targets; the first death requests action 2, the second requests action 3.
The body stays outside enemy targeting until notification 0 exposes it. Damage
does not interrupt boss animation through the generic flinch path. Headbutts run
9 → 10 × 0..2 → 11 → 8, while distant targets get swing 7 → laser 8. The latter
selection distance is authored, not a recovered spatial predicate.

Falz's one-shot phase requests use strict half/quarter comparisons and preserve
quarter-branch priority when a hit skips half HP. The damage accumulator does
not invent a request-1 stagger. The revised encounter walks and attacks in front, carries three variable-radius
orbiting balls, and sends a telegraphed tail through the floor. The balls retract
for 17→18 radial volleys and return only after deliveries expire. Below quarter
HP, a persistent faster swim phase replaces temporary relocation. These spatial
rules and effect visuals are authored; see [the Falz reference](dark-falz-reference.md).
Generic enemy damage calculation supplies defense-aware damage to the player.

### Test on this branch

1. Open Coliseum Master → Bosses → Mother Trinity, or accept `DEBUG: Mother
   Trinity` at the counter. The arena is `s07z_na1`; the full-size body is fixed in the north cutout.
   See [the animation and placement reference](mother-trinity-reference.md).
2. Attack a piece: Trinity's HP must stay unchanged. Defeat one piece for a
   reaction, then a second for the body transition. Hit the exposed body and
   watch the headbutt/recovery/laser chain.
3. Defeat Trinity; check the health bar disappears and one return warp appears.
   Return and start again: all three pieces and full HP must be restored.
4. Test `DEBUG: Dark Falz Arena` or the Falz Coliseum entry. Check complete
   attack windups and reactions below half and quarter HP. Defeat and retry.
5. These encounters retain the game's existing authored level/difficulty scaling;
   they are not balance-matched to the emulator's savestate/player.

Automated entry points:

```sh
godot --headless --path . res://scripts/tools/test_runner.tscn
godot --headless --path . --script res://scripts/tools/test_boss_action_events.gd
PSZ_DARK_SHRINE_CHECK=1 godot --headless --path . res://scripts/tools/coliseum_probe.tscn
```

The last probe exercises actual field spawning, imported clips, protection,
piece deaths, body activation, shot release, HUD, lethal damage, one-shot reward,
projectile cleanup, room clear and retry. Set `PSZ_PROBE_PACK` to the local asset
pack when required. Optional `PSZ_BOSS_SCREENSHOTS` saves rendered images when
running with a display. Use an isolated `XDG_DATA_HOME` for test saves.

### Still incomplete

This PR is a first playable port, **not 1:1 boss parity**. The three procedural
piece markers are deliberate placeholders: the viewer has original koma meshes,
but they are absent from the distributed game pack. The authored grid movement, spin/attack cycles, synchronized waves and second-loss
cover break now make the opening phase playable; exact retail tactics,
reinforcements, break budgets, attack selection, original Falz subobject visuals,
projectile/beam shapes and trajectories, multiplayer targeting, root motion,
looping sounds and effects still need ports. Kind-1 attack shapes currently use
an approximate planar box; incoming body geometry is also provisional.

There is no automatic Trinity→Falz campaign handoff. Trinity now uses `s07z_na1`; its fixed root placement is an authored visual fit,
not a recovered retail coordinate. Reyburn and Octo retain
their prior gameplay implementations: this PR brings their research and replay
helpers but does not represent either fight as finished or 1:1.
