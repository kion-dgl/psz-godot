# Robot boss port

Paru: Coliseum Master → Bosses → D Chaos & D Mobius. Dedicated quest
`debug_boss_chaos_mobius` now loads s05z_na1. Legacy Sinow debug encounter
remains available. Campaign quest substitutions are not part of this PR.

Source: psz-re `data/robot_controller_contract.json`, ov22, 12,600 fresh
emulator controller snapshots (5,400 Paru + 7,200 Arca), retained screenshots
and source-save hashes. Original saves contain boosted player stats; no
capture-time memory writes. `tools/robot_contract.py --check` verifies
HP tuning, child-counter spans and the observed Arca split/recombine.

Implemented Paru: independent model channels, shared HP/hurt ownership,
54-tick dive, 299-tick aerial cycle, three aerial attacks before coordinated
45/90/150-tick orbit preparation/attack, paired and single projectile cadence,
HP-interpolated idle delays, original intro/idle/death clips.

Not 1:1: authored starting positions, floating-point trajectory adapters,
fixed provisional targeting of the local player, lower approach predicate,
projectile speed/heading/shape/status and original growing area collision.
The floating robot now alternates authored hover attacks and a burrow within the
299-tick span. The original z_003u mesh and put02 tracks supply the drill; o0c_bsef01 supplies
the digging effect (with authored scale/lifetime). Burrowing
hides/disables its receiver, warns at the captured emergence point, and restores
it on emergence. The other robot approaches, dashes, occasionally strafes and
fires post-dash lasers. Linked orbit timing is unchanged. Persistent slow holes
and Zonde casting are not implemented; Zonde is still unconfirmed.
Original split geometry now loads from assets/enemies/boss_robot_paru instead
of Humilias split parts. Native put02 drill animation is retained. The viewer's
z_003u export omitted texture bindings; named material/texture bindings are
restored from z_103u against original Paru textures. Source and runtime hashes
are in data/boss_animations/robot_provenance.json. These assets are published
in the pack referenced by assets_manifest.json and the R2 raw mirror. No full-fight
fidelity claim.

Validation: seeded unit checks in test_runner; actual arena lifecycle/autonomous
attack probe via `PSZ_ROBOT_CHECK=1 godot --headless --path .
res://scripts/tools/coliseum_probe.tscn`. The probe must also pass an exported
build with `PSZ_PROBE_PACK` pointing at the existing asset pack.

## Arca / Humilias

Coliseum Master → Bosses → Humilias, `debug_boss_humilias`, s06z_na1.
Source species65 `boss_robot_cmb`, original 6000/11000/14000 base HP rows;
the shared progression layer still applies remake level scaling. The pack
stores the combined NARC mesh as `boss_robot`; the controller makes this
asset alias explicit, keeping source identity distinct from Paru.

Combined gun chains21/22/23 and24/25/26 release at frame2; drill chains
27/28/29/30 and31/32/33/34 have contact at controller counters[52,67);
sweep35/36/37/38 opens contact at frame8 of37. Quarter-HP thresholds gate three split requests with an authored eight-second
minimum between phases. Both parts return before
combined exposure resumes. Nine independently warned floor slots activate
at105, clear at150, and stay in world/arena coordinates as Humilias moves.
Original centers are −10/0/+10 on each axis; original cell lookup clamps
truncated (coordinate+15)/10 to 0..2 (021A0EC0/02198778).

Mac playtest follow-up: intro shows the two parts converging and combining in
about 2.6 seconds, with camera/control restored afterward. Movement uses hover
exhaust and ground rings. Every ten active seconds a five-panel pattern warns
in amber, then activates cyan at the existing 105-tick boundary. Gun delivery
is a larger cyan laser that freezes on an unguarded hit; dodge avoids both.
Accumulating 8% HP damage triggers the recovered kneel/hold/recover clips,
with a six-second stagger cooldown. The eight-second malfunction split is a
punish window: both parts accept damage and only one late shot is allowed.
These pacing, thresholds, visual effects and pattern choices are authored from
playtest feedback, not recovered retail tuning.

Remaining gaps: authored attack selector, turning/part motion, request delivery
latency, hit geometry, projectile pools and exact retail status durations.
The retail split counter advances only in specific child38 states; this version
uses a deliberately quiet fixed-duration opening.
Floor mode2 persistent visuals/occupancy edges and mode3 status variants
remain unported. Do not interpret the probe or identity correction as 1:1.

`PSZ_HUMILIAS_CHECK=1` selects the Humilias arena probe from coliseum_probe.
It drives autonomous gun/drill/sweep, floor activation, damage-gated split,
paired recombine, retained HP, one defeat, delivery cleanup and retry.

Identity integration also corrects Paru free-roam's legacy Humilias spawn
and its generator recipe to Chaos/Mobius, and removes the source65→63
FieldPopulation alias. Existing story layouts are retained: Heretic stages
Chaos/Mobius in s06z_na1; Control System stages Humilias in s07z_na1. These
legacy story-arena assignments still need a separate campaign review; use
the dedicated Coliseum boss encounters for the intended Paru/Arca arenas.

Validation record for the Paru base PR: 9,949 unit checks; rendered and
exported Linux arena probe; 215-page Astro build; code-health, asset refs,
roster and orphan checks. Full matrix: Boot and Search and Rescue passed.
Free-roam navigation failed at Valley s01a_td1 and Rioh s03b_td2. Paru Pact
canonical/backtrack each failed all three attempts at s05a_lc2, position
(−14.8,0.2,−20.9), no floor ahead. Stopped the dependent dialogue probe.
These match previously documented navigation failures; later quests were
not verified. The arena boss probes are separate and pass.
