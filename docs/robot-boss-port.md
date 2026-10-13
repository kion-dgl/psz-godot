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
