# Mother Trinity: arena and animation reference

Tracking issue: https://github.com/kion-dgl/psz-godot/issues/755

Reference recorded from Kion's visual inspection on 2026-10-12 for PR #753.
Viewer: https://kion-dgl.github.io/psz-godot/tools/storybook/enemies/
Select `boss_mother` (Mother Trinity), not the tower Mother variants.

## Spatial contract

Mother Trinity belongs in **`s07z_na1`**, not the Eternal Tower summit.
The full-size body fits the broken northern edge of the player platform, with
stage cables behind her back. She is mostly static and attacks the platform;
her whole body must not chase or rotate toward the player. The current authored
fit is root `(0, 0, -10)`, yaw `0` (+Z toward the platform), model scale `1`.
This placement is visually checked against the exported stage, not claimed as a
recovered ROM spawn coordinate. Piece starting positions are on the platform.
The head damage receiver follows the animation; lasers originate at the head.

## Visual observations

Descriptions below preserve the observer's uncertainty. They are animation
observations, not proof of attack timing or gameplay triggers. Kion listed
`cmbend` twice with different observations; keep both until a viewer pass
resolves the label rather than silently relabeling either as `cmblp`.

| Animation | Observation |
| --- | --- |
| `z_004_cmbend` | Vertical downward attack with her left hand. |
| `z_004_cmbend` (second observation) | Arms shift around; possibly the end of the preceding attack. Duplicate label unresolved. |
| `z_004_cmblp` | Present in the rig and action 6; no distinct user description yet. |
| `z_004_cmbst` | Raises arms, perhaps to start an attack. |
| `z_004_dam1` | Takes damage. |
| `z_004_ded` | Defeat animation. |
| `z_004_fall` | Falls onto the platform. |
| `z_004_fallwat` | Stunned. |
| `z_004_hedb2lp` | Lifts her head completely. |
| `z_004_hedb2wt2` | Partly lifts head, lowers arms to brace herself. |
| `z_004_hedbhitlp` | Head down, similar to stun. |
| `z_004_hedblp` | Body up and pulled back; possibly laughing/charging, likely head-bash telegraph. |
| `z_004_hedb` | Brings head down to attack the player. |
| `z_004_hedbst` | Looks like standing up after a head bash. |
| `z_004_hit` | Moderate hit; falls onto her arms. |
| `z_004_laserlp` | Laser preparation. |
| `z_004_laser` | Casts laser toward the player. |
| `z_004_laserst` | Name suggests laser start. |
| `z_004_move` | Looks like a taunt. |
| `z_004_stdup` | Stands after the moderate hit. |
| `z_004_swinglp` | Swing preparation. |
| `z_004_swingst` | Swing start. |
| `z_004_swing` | Swing attack. |
| `z_004_wat1` | Standing wait. |
| `z_004_wat2` | Hunched wait. |

## Recovered descriptor order

`data/re_reference/boss_behavior_contract.json`, catalog `boss_mother`, supplies
these orders independently of the descriptions above. Keep descriptor timings
and notifications; do not reorder clips based on suffixes or a still pose.

| Action | Ordered clips (prefix `z_004_` omitted) |
| --- | --- |
| 0 / 1 | `wat1` / `wat2` |
| 2 | `dam1` |
| 3 | `dam1 → move → hit` (body exposure notification) |
| 4 | `fall → fallwat ×3 → stdup` |
| 5 | `ded` |
| 6 | `cmbst → cmblp ×3 → cmbend` |
| 7 | `swingst → swinglp → swing` |
| 8 | `laserst → laserlp → laser` |
| 9 | `hedbst → hedblp → hedb → hedbhitlp` |
| 10 | `hedb2lp → hedblp → hedb → hedbhitlp` |
| 11 | `hedb2wt2` |

For example, `hedbst` visually rises but begins action 9 from the hunched idle;
it is not evidence that the recovered chain should put it after `hedb`.

## Verification and remaining work

The live probe checks the stage ID, cutout placement, fixed facing under an
off-axis target, piece spawn positions, animated head receiver, downward laser,
phase transitions, death cleanup and retry. Inspect rendered entry/body images
as well as assertions. A passing timing test alone cannot validate arena fit.

The three procedural piece visuals, exact retail tactics/attack selection, swing
joint transform, beam shape, effects, audio completeness and original spawn
coordinate still require further verification. The current laser remains a
projectile approximation. The game camera is widened in this arena to show
more of the full-size boss and platform. Manual combat/balance review remains
necessary; these checks do not establish retail fidelity.


## Follow-up observation: board phase and body entry

Kion's follow-up confirms three hopping objects: each lands at the center of a
floor square and no square can hold two. They spin, cast a technique or perform
a melee attack, then hop again. Mother can command a small wave from all three
simultaneously. Two pieces must break before Mother enters the broken-platform
body phase; the last piece remains active. The goal is a cohesive encounter,
not a claim of 1:1 behavior.

The exported floor visibly has a 5×5 grid with 4-unit tiles, centered at
`x,z = -8,-4,0,4,8`. The authored board uses the four southern rows; the northern
row is reserved for the body-entry zone. Destinations and occupied source cells
are both reserved during flight. Pieces prefer a free neighboring square toward
the player, spin, alternate melee/technique attacks, then recover. A command waits
for all living pieces to land and wind up before releasing simultaneous radial
waves (one damage resolution per player across the volley).

An intact cover across the three northern middle tiles is reconstructed using
the existing stage floor texture. Mother starts behind it and moves into the
cutout during the second-loss transition. The cover breaks at the existing body
exposure event; the survivor pauses during entry and then resumes. This is an
authored visual reconstruction, **not identification of an original cover asset**.

Viewer identities: `boss_mother/z_004` is Mother Trinity;
`boss_mother_piece/z_004_koma_a` and its `koma_b`/`koma_c` parts are her pieces;
`mother/b_072` is Heaven Mother, separate from Blade/Shot/Force. The viewer also
contains `ef_e_d_arnd` and `ef_e_d_stg` under `boss_mother_piece`; their role in
wave/stage behavior needs visual confirmation, not inference from filenames.
