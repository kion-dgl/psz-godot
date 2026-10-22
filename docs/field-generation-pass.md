# Field generation pass (2026-10-21)

Status pass over field/level generation, object placement, and enemy
placement, against the original game. The headline: **the original's
generation algorithm is already solved** in
`data/re_reference/level_generation_algorithm.json` (psz-re work: 5-of-5
savestate fields reproduced exactly, cells and room counts, no fitted
constants). The gap is that `grid_generator.gd` still ports the psz-sketch
5×5 algorithm rather than the solved one. This pass consolidates the solved
parameters into repo data, decodes the missing wave-count rule, and ports
the field RNG.

## New artifacts from this pass

- **`data/re_reference/field_generation_params.json`** (rerun:
  `dump_field_generation_params.py --raw <raw/>`) — per-area generation
  parameters decoded from `quest/single/dive/quest_001SS00.rel`: room
  targets 8..10 (stages 1–3), 9..11 (4–5), 10..12 (6–7); branch pair (2,2)
  → (2,3); shared gate percentages 50/25/50/30/85; the rotating rare-room
  picker slots (stage→slot: 1,2→0, 3→3, 4→2, 5→1, 6,7→4); the five
  per-10000 weights from `random_dungeon.rel`; the rare-room masks and
  slot→room switch; coliseum 8%.
- **Wave-count rule decoded** — decomp `src/arm9/FUN_02057794.c` (banked):
  `count = ctx_min + game_rng(ctx_max − ctx_min + 1)` — an INCLUSIVE range
  on the combat RNG (`PszRng`, already ported). The `ctx` min/max are the
  `[w3, w4]` fields already exported per room in
  `enemy_room_assignment.json`. This closes the count half of the enemy
  placement gap; the slot-subset half (which of the 8–9 authored spawn
  slots a wave occupies) is the `FUN_020573b0` member/entry machinery —
  schema documented (strides 8/12/8, 8-element slot shuffle), field names
  still provisional in the decomp.
- **`scripts/utils/field_rng.gd`** — the field-generation LCG (Nintendo
  64-bit: `state = state*0x5D588B656C078965 + 0x269EC3`, draw
  `((state>>32)*range)>>32`), limb-safe, verified against the big-int
  reference on 200 seeds × 20 draws; vectors embedded in
  `scripts/tools/field_rng_check.gd`. Note it is a DIFFERENT RNG from the
  combat one (`psz_rng.gd`) — the game uses both.

## Original vs current generator — the delta list

| Aspect | Original (solved) | `grid_generator.gd` today |
|---|---|---|
| Grid | 7×10, fixed start at internal (3,6) | 5×5 psz-sketch grid |
| Topology | spanning tree, budget-driven: `target = 2·branches + spine + 1`; branch count ALWAYS 2 | path + branches + key-gates, own rules |
| Room target | per-area ramp (8..10 / 9..11 / 10..12) | fixed |
| Growth | frontier queue, shuffle-then-pop, 4-draw direction bag, one extension pass when short | own growth |
| Goal | uniform random among single-door rooms with depth > 3 (fallback: deepest single-door) | own |
| Shape | degree→shape `i l t x n s g` — **already ported** ✓ | ✓ (from psz-re) |
| Variant | one draw, filtered against neighbours' (shape,class,digit); x/s/g cost no draw | rotations cover connections; variant pool authored |
| Gates | key-gate accept 50%, budget 25%, one/two-key 50/30, enemy-defeat 85% | own gate model (field-gates spec) |
| Category draw | per room: depth-banded 50/20/20/10 → 40/20/20/20 → 25/25/25/25 | not consumed |
| Rare rooms | nr1–nr6 per-area slot (~2%), na1/nc2 marks (~4% each), 90% none; coliseum 8% as E-transition second room | absent |

Object and enemy placement status (both already substantially decoded in
`field_population.gd`'s references): object positions/groups are authored
per room in `room_objects.json` (290 rooms; group 5 traps are rolled, not
built); enemy wave templates and per-room weights are in
`enemy_room_assignment.json` + `enemy_wave_templates.json`; the open items
are the per-room slot-subset selection (573b0 machinery + the per-room seed
at record +0x14) and which set-variant (`d`/`f1..f4`/`s`) each mode/quest
resolves — the deploy side keys on the same per-area quest records.

## Recommended port order

1. Consume `field_generation_params.json` per-area targets/budgets.
2. Replace topology with the solved algorithm (start (3,6), budget identity,
   two-attempt growth, goal rule) on `FieldRng`, keeping the existing
   degree→shape and doorway/rotation layer.
3. Transcription draws in the documented order (rotation → variant → key
   shuffle → seed → category).
4. Enemy waves: weighted template select (existing data) + the new count
   rule + per-room-seeded `PszRng`; slot subset once 573b0's field names
   firm up (decomp ask).
5. Validation: invariant tests (tree, doors==connections, per-area counts)
   in-engine; seed-exact replay against the five savestate fields via a
   psz-re checkout (its `tools/generate.py` is the parity oracle — it
   already reproduces them 5/5).

Rare rooms and the coliseum are optional content: the mechanisms are fully
decoded (including working AR codes in the algorithm JSON) and can be
adopted whenever the content side wants them.
