# Dark Falz: moving encounter reference

PR: https://github.com/kion-dgl/psz-godot/pull/753

## Kion's original-game observations

- The current `s07z_na2` arena is correct.
- Falz walks around the arena and attacks what is in front of him.
- Three balls continuously rotate around him; their orbit reach varies.
- A tail occasionally emerges from the floor to attack the player.
- Falz has a shadow. The balls withdraw into it before an all-direction
  projectile attack, and emerge again after the projectiles disappear.
- At low health Falz sinks into his shadow, becomes faster, and moves around
  attacking more actively.

These observations supersede the earlier ranged-only implementation. They do
not identify exact retail timers, radii, tail/effect models, or HP thresholds.

## Authored implementation

Normal Falz walks at 3 units/second, closing distance or circling nearby targets.
After 3 seconds of movement he locks his facing for a frontal strike using
`z_005_nagi` (action 14, notification 13). Its provisional reach is a forward
9-by-7 rectangle; the rear is excluded. The clip completes before walking resumes.

Three procedural balls orbit at equal angular spacing, with radius varying
between 3.5 and 7.5 units. Swept contact is dodgeable and shares a 1.2-second
cooldown, preventing three simultaneous contact hits. The procedural dark disk
marks the shadow; these visuals are not claimed as original effect assets.

After 14 seconds spent moving, Falz retracts the balls during `difst/diflp`
(action 17, two loop repetitions). `diffusn` (18, notification 2) releases twelve
radial shots at speed 8 with maximum travel 32. Balls remain harmless and hidden
until every owned volley projectile has expired or collided and the animation
has finished, then return during action 16. The volley has a shared hit budget.

The tail warns for 1 second at the player's sampled floor position, emerges
with a 0.45-second strike window, and retreats for 0.65 seconds. Moving away or
dodging avoids its strike; the warning never follows the player. Tail cadence
counts movement time: first after 6 seconds, then every 8 (5 while submerged).
The visible segmented tail is an authored placeholder.

Recovered strict half/quarter HP reactions and quarter precedence remain intact.
Below quarter HP, after the reaction, Falz uses `wat2swm` (3), then stays in
`swm` (4), with the model lowered into the shadow. He moves at 6 units/second,
with 1.8-second movement periods and a short swim-pose frontal attack. The strike
starts after 0.45 seconds and recovery lasts through the clip. He remains
attackable throughout: persistent untargetability would prevent finishing the
fight. The quarter threshold and this spatial behavior are authored, not a
claim that the original's form transition occurs at exactly 25 percent.

## Assets and verification

The packed `boss_darkfalz` rig contains the body and 25 animations, but no ball
or tail submodels. The viewer repository has separate effect candidates including
`ef_e_d_bit`, `ef_dktnt`, `ef_e_d_sdw`, and shadow variants. Their names alone do
not establish their roles. Original-effect identification/import remains open.

`falz_encounter_tests.gd` checks orbit spacing, retraction, forward-only reach
and the speed relationship. `falz_encounter_probe.gd` exercises real arena
walking, orbit contact/dodge, locked tail warning, volley lifetime ordering,
phase transition, faster swim attacks, death cleanup and a fresh retry. Rendered
screenshots verify normal, shadow-volley, tail, and submerged presentation.
These tests do not replace manual balance assessment or establish 1:1 fidelity.
