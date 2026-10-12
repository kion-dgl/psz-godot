# Reyburn original-parity branch

Branch: `feature/reyburn-original-parity`, based on merged reviewed Reyburn/Octo
work at `1110f94a`. See [the original-game audit](reyburn-original-evidence.md)
for the eight emulator experiments, flight timeline, objects and all 26 clips.

## What changed

* Correct normal claw vs enhanced spin selection. The three aerial requests now
  execute their original state chains instead of a shared multiple-fireball loop.
* Port Q12 sampled natural-cubic paths, lateral exit, offscreen end reentry,
  descending claw, six-pass enhanced spin and return/landing.
* Center breath launches one center-directed projectile, then a separate tracking
  ground-fire trail. Normal claw and enhanced spin emit no breath projectile.
* Separate six-slot projectile and ground-fire pools; delayed fire damage and
  lingering claw hazard. These still use primitive visuals/shared damage adapters.
* Ground breath hold is one/two original updates, with notification-to-launch
  ordering. Ground selection defaults to original pacing rather than authored
  attack rests and approach loops. `original_ground_pacing=false` retains the
  reviewed ground pacing for comparison; flight behavior remains the new port.
* Attach the existing separate horn asset to `atama`; an exhausted head budget
  hides it and disables bite selection.

The reviewed solid torso, melee reach, floor support, defeat cleanup and Octo
behavior are retained. Test changes cover Octo regressions; no Octo implementation
was changed.

## Evidence and validation

`data/re_reference/reyburn_parity.json` is generated in psz-re from original ROM
assets and 74,469 captured controller updates. It includes input histories,
projectile events, coverage, 749 original spline samples, 414 one-update movement
fixtures and a full takeoff position trace.

The Godot Q12 oracle reproduces all 749 sampled points and distances exactly; all
414 follower steps are within one raw Q12 unit. A loaded-arena replay from the
original position/facing completes takeoff in exactly 266 updates; its maximum
aligned position error is 0.014756 world units. That is a measured tolerance,
**not** a claim of exact whole-encounter trajectories.

Commands (Godot 4.5.1; normal imported assets or `PSZ_PROBE_PACK` required):

```sh
godot --headless --path . --script scripts/tools/test_reyburn_parity.gd
godot --headless --path . res://scripts/tools/test_runner.tscn
PSZ_REYBURN_OCTO_CHECK=1 PSZ_PROBE_PACK=/path/to/assets.pck   godot --headless --path . res://scripts/tools/coliseum_probe.tscn
python3 scripts/tools/code_graph.py --check
python3 scripts/tools/orphan_files.py --check
python3 scripts/tools/check_asset_refs.py
python3 scripts/tools/check_repo_layout.py
godot --headless --path . --export-debug macOS build/macos/reyburn-original-parity.zip
```

The arena probe checks all 16 recovered requests, all 26 imported body clips,
three aerial projectile counts, six spin paths, supported/off-mesh landings,
horn break, actual melee/head hit routing, original bite restart intervals,
modifier notification, defeat/retry and autonomous progress. A rendered Xvfb
OpenGL run also passed and produced inspected screenshots. Unit suite: 9,847
passed, zero failed. The math oracle: zero failures.

The asset pack used here lacks city NPC `np_009_00_0` and the Valley boss minimap
SVG. The arena probe reports those resource warnings/errors on scene transitions,
but completes successfully with no GDScript errors. Unit shutdown also reports
existing resource leaks. These logs are not represented as warning-free.

## Mac playtest

Open **Coliseum Master → Bosses → Reyburn**. Use the usual local asset pack.
The new original ground pacing is enabled by default. The unsigned macOS package
was cross-exported on Linux and checked for both arm64 and x86_64 executables,
packaged scripts/fixtures and ZIP integrity; it has not been executed on a Mac.

1. Stay still in front, then repeat from a flank and behind. Record where he turns,
   which ground attack starts, and whether collision traps the player.
2. Circle both ways and repeatedly approach/retreat. Watch for edge stalls or
   indefinite turn/run loops. These are high-priority remaining parity checks.
3. Let multiple flights finish. Expect claw and center breath in normal state;
   enhanced attack flights become six-path spins. Count from **landing**, not
   takeoff: the nominal next-flight countdown is 1500 original updates.
4. For center breath, avoid the arena center, then watch the ground-fire trail
   steer toward the target. Report damage before a visible warning separately
   from visual placeholder complaints.
5. Attack the head until the horn breaks. Confirm the horn disappears and he
   stops choosing bites. Check death cleanup, return warp and a fresh retry.

## Remaining 1:1 gaps

This is a reviewable parity experiment, not a completed 1:1 certification. The
original recordings use one altered-stat Normal save with NPC companions; one
horn test explicitly seeds the part budget. No clean-stat solo/RNG sweep,
Hard/Super Hard or multiplayer coverage is claimed.

Original intro/death cameras, run/jump/bite root motion, exact target selection,
small-angle ground steering, enhanced entity time scaling (original B4 uses
4710/4096 per call; this port still uses a unit controller clock), airborne
facing/pitch, all attack-region semantics,
sound timing and the 13 original effect bindings need further work. Primitive
projectiles/fire/hazard and shared damage are explicit port adapters. Floor
validation and a degenerate spin-path guard are Godot safeguards. Whole-flight
comparison beyond the measured takeoff remains open. The two archive clips with
no descriptor references are accounted for as unused, not assigned invented
combat behavior.
