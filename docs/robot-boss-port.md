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
The initial aerial impacts are bounded pulses, not original expanding areas.
Full split mesh differs from the combined archive's split geometry shipped
in the asset pack; original curves are retargeted by bone name (provenance in
`data/boss_animations/robot_provenance.json`). No full-fight fidelity claim.

Validation: seeded unit checks in test_runner; actual arena lifecycle/autonomous
attack probe via `PSZ_ROBOT_CHECK=1 godot --headless --path .
res://scripts/tools/coliseum_probe.tscn`. The probe must also pass an exported
build with `PSZ_PROBE_PACK` pointing at the existing asset pack.
