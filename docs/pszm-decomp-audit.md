# PSZ Mini decomp — 1:1 accuracy audit (2026-10-21)

Audit of what `https://psp2i.dev/rozalin/pszm-decomp` (private, cloned to
`/tmp/pszm-decomp` for this audit) can contribute to psz-godot, system by
system, versus what the project already sources from `psz-re` and wikis.

**Scope note (2026-10-21):** the project direction is western-punk/PSO with
original weapon content — so this audit's live priorities are BEHAVIOR
systems (see "Direction" and the behavior-first roadmap at the end); item
data sections below are kept for reference but deprioritized.

## What the decomp actually is

A byte-matching decompilation of **Phantasy Star Zero Mini** (KPSJ, DSiWare).
Two facts matter more than the "Mini" name:

1. **The Mini ROM ships the full game's data filesystem.** `extracted/files/`
   contains all 9 areas (city/moorland/wetland/snowfield/graveyard/ruins/
   facilities/darkness/tower message packs), story + free + multi quests,
   `quest/random_dungeon.rel`, `quest/tower.rel`, per-room deploy/set/spawn
   tables for s01–s07 × a/b (+ `e` entry and `z` boss rooms, using the same
   room codes as our stages, e.g. `s07a_ga1`), 24 drop tables, 7 shop tables,
   mag params, PA-effect params (`item/paeff00–16`), PB params
   (`player/pb_param_data.rel`), and companion params (`apc/apc_param.zarc`).
2. **~61% of the ARM9 (3,202 functions, 496 KB) is the full PS0 game, dead in
   the demo** — parked as the "Phase B map" for a future retail decomp
   (`notes/project-direction.md`). Not banked C today, but it proves where the
   full-game logic lives.

Code recovery tiers (see decomp `AGENTS.md`, `notes/parked-ledger.md`):

| Tier | Where | Status | Port safety |
|---|---|---|---|
| Banked | `src/arm9/`, `src/ov001`, `src/ov004` (1,316 files) | byte-verified, annotated | highest |
| Near (semantics proven) | `drafts/near/arm9/` (169 files) | logic fully understood, codegen not byte-matched | high — project rule is "park only after semantics are fully recovered" |
| Readable | `src-readable/arm9/` (16 files) | humanized twins of banked code | highest |
| Dead map | unbanked | 3,202 full-game functions | future Phase B |

Key structural fact: **stat tables live in ROM data files, not code.** The
decomp's unique value is the *verified readers* — banked functions that decode
those tables — which is exactly what psz-re's static analysis could not pin
down ("fields remain unknown", "EXP column unconfirmed", "class→member
identities not inferred" in our own CI checkers).

## Scorecard

| System | Fidelity today | Decomp contribution | Value | Effort |
|---|---|---|---|---|
| Damage/crit/variance chains | core recovered; crit 5%, ±10% variance authored | `FUN_02044f2c` + `FUN_020441a8` (near) recover the real chains | High | S–M |
| RNG | Godot `randi` | `FUN_0203e874` + `FUN_02045d84` + `FUN_02045d5c` banked | High | S |
| Drops | **zero ROM provenance** — 20% flat, uniform pick | 24 drop NARCs + weighted-select `FUN_020577ac` banked | **Highest** | M |
| Class stats & materials | 6 authored breakpoints over ROM anchors | `FUN_020412d8` row layout + `FUN_0203e570` material caps — **converted to JSON, class mapping resolved** | High | S–M |
| Enemy stats | retail table already in (`enemy_combat_stats.json`) | nothing new for stats; EXP still open | Low | — |
| Enemy AI/targeting | hand-tuned ranges/windows | scanner `FUN_02072774`, range `FUN_02064b58`, hit-dedupe `FUN_02063a18` | Medium | M |
| Bosses | Reyburn near-exact; Falz/Mother/Humilias authored | machinery + cross-validation only (demo has 1 boss) | Low–Med | M |
| Weapon attributes | ~360 items, ROM-anchored + wiki-agreement CI | per-type 216 B payloads (attack timing) — **the missing attack-speed data** | Medium | M |
| Mag / PB / shops | hand-tuned | `mag_param.narc`, `pb_param_data.rel`, `shop1–7.narc` present; readers unbanked | Medium | M |
| Techniques | invented power table | **no technic data identified** in Mini files or matched code | None yet | — |

## Detail by system

### 1. Combat math — chain fully decoded (2026-10-21 update)

`scripts/utils/combat_math.gd` carries the retail core (ARM9 02042A4C/
02042964): `(atk×4/10) − ((def×819+2048)>>12)`, Q12 multiplier scale. The
decomp's banked Mini twin `src/arm9/FUN_020440c8.c` matches this structure
exactly — cross-build confirmation.

**`drafts/near/arm9/FUN_020441a8.c` (melee damage arm, 0xad4) is now decoded**
(the float-helper trio resolves to a standard percent→Q12 rounding idiom):

- Damage core: `((A + B + C×attr_pct) − defense) / 5`, then × kind multiplier
  (attack+0xc8) × resistance factor × body-part multiplier — our
  `combat_math.damage()` skeleton and part-multiplier handling already match.
- **Crit is stat-driven, not flat**: `crit% = (attack[0xdc]+attack[0xe0]+
  attack[0xe4]) / 10`, percent-rolled; **crit adds +50%** (`d + d/2`) — our
  ×1.5 is already correct; flat 5% corresponds to a stat sum of 50.
- **Ranged sweet spot**: type-1 attacks gain **+5% crit** when the
  relation/distance factor lands in `[round(atk_word×0.8), atk_word]`.
- **Defender damage-reduce state**: flag bit at defence+0x60 multiplies the
  whole result by 0.8 (Q12 3277).
- **Element-vs-family** applies as `(attack_element_word + 100)%` scaling on
  only the C component — confirms our "family % applies to weapon ATP only".
- Negation gate before damage: defender stats (+0x4c/+0x50/+0x54) can void the
  hit outright (percent roll; attack+0x88 ≠ 0 forces it).
- **Status-infliction chain**: kind→type mapping (attack+0x8c kinds 6/7/10/11
  or explicit +0x70), level from +0x90, chance +0x94 × resist factor, level
  tables at ROM `0x020cbc04` (5 levels × 5 types), immunity masks
  (defence+0x30/+0x3c/+0x34). Replaces our authored `10% + 10%×element_level`
  once the level table is dumped.
- `drafts/near/arm9/FUN_02044038.c` — **the damage variance**: for kind-20
  attacks it draws the game RNG to 0..9 and writes category/value groups into
  the attack work fields, with a signed negate-mod-32 branch. Field names are
  still `???` in the decomp — one targeted session from portable semantics.
  Our ±10% authored variance sits exactly here in the pipeline.

Still open: the second damage arm `FUN_02044cac` (attack kind 1) is unbanked;
the attack-vector fill (attacker vtable+8, `FUN_02044dd4`) defines which
player/weapon stats land in words 0xb8/0xbc/0xc0/0xdc..0xe4 — needed before
the crit% formula can be wired to real stats. Attribute grid:
`src/arm9/FUN_020abfb8.c` + `drafts/near/arm9/FUN_020ad9bc.c` (3×3 category
rules, Q12 blend 0x3e8000, clamps 0x800/0x1000) remains as before.

### 2. RNG — PORTED (scripts/utils/psz_rng.gd)

`src/arm9/FUN_0203e874.c` (64-bit state: `acc = s2 + s1*s0`; result =
`high32(high32(acc) * n)`), `FUN_02045d84` (percentage roll:
`pct>=100 → hit, pct<=0 → miss, else RNG(100) < pct`), `FUN_02045d5c`
(`lo + RNG(hi−lo)` — the damage-variance roll provider). Ported to
`scripts/utils/psz_rng.gd` (32/16-bit limb math, no overflow assumptions);
`scripts/tools/psz_rng_reference.py` is the big-int mirror that generated the
vectors embedded in the headless check
`scripts/tools/psz_rng_check.gd` (run:
`godot --headless --path . --script res://scripts/tools/psz_rng_check.gd`).
Not yet wired into combat/drop rolls — swap-in is the remaining step when
those systems adopt recovered odds.

### 3. Drops — DEPRIORITIZED (2026-10-21: item content is creative territory; wiki lists suffice)

Today: `drop_config.gd` flat 20% chance, 30/70 item-vs-meseta, **uniform**
pick from a wiki-shaped list (`cell_object_spawner.gd:985–1040`). The decomp
has both halves of the real system:

- **Data**: `extracted/files/item/drop/{normal,hard,v_hard}1–8.narc` — 24
  tables (sizes grow with difficulty: ~1 KB normal vs ~3.4 KB hard/v.hard).
- **Algorithm**: `src/arm9/FUN_020577ac.c` (banked) — weighted selection over
  12-byte rows `{u32 id; int weight; s8 mode}` (mode 0 = always, 1 = only if
  input==0, 2 = only if input!=0), `RNG(total)`, first cumulative sum wins.
  Same picker drives spawn selection, so one port covers two systems.

The per-table NARC readers are unbanked, but row shape + picker semantics are
known, and our CI already has NARC tooling (`check_systems_reference.py`
decodes ROM NARCs). Validate decoded Mini tables against retail psz-re
extracts before switching — build divergence check, same as wpnprm anchoring.

### 4. Class stats, levels, materials — CONVERTED; mapping resolved

**Done (2026-10-21):** `scripts/tools/dump_player_lv_param.py` decodes
`player_lv_param.zarc` → `data/re_reference/player_lv_param.json` (14 members
× 100 levels × 7 stats + XP thresholds + `player_type_param` raw rows). The
class→member identity — explicitly unresolved in
`check_progression_reference.py` — fell out of curve-matching the decoded rows
against `data/classes/*.tres`: **13/14 exact at every breakpoint; member 11 =
hucaseal with a single diff** (accuracy L20: tres 172 vs ROM 178 — likely a
transcription typo to fix or bless). Bonus finding: the tres breakpoints were
ROM-real all along; only the intermediate levels were interpolated.

Remaining: consume the real 100-level rows in `class_data.gd` (replace
breakpoint interpolation), re-run the dumper against retail
`psz-re build/fs/player/player_lv_param.zarc` to upgrade provenance past the
Mini copy (XP diverges at L5–L9 and L45), and decide the hucaseal L20 value.
Still open in the same family:

- `src/arm9/FUN_02041118.c` — level-group loader (`row = (level−1)/5`, 20
  groups, records `{tag, ID, byte, byte}`): candidate for the
  learn-tables/technique-unlocks.
- `src/arm9/FUN_0203e570.c` — material/stat-upgrade writer: raise-only,
  `min(val, 0xff)`, indices 7–9 — real material caps vs our current handling.

### 5. Enemies — stats are already ahead; behavior is the port target

Enemy HP/ATK(min/max)/DFP/EVP for 65 enemies × 3 tiers are already ROM-real
in `data/re_reference/enemy_combat_stats.json` (CI-verified). The Mini adds
nothing there (6 demo enemies). What it adds is **engine-level behavior
semantics** that are not demo-specific:

- `drafts/near/arm9/FUN_02072774.c` — combat scanner: hit-list walk, Q12
  normalize, atan2 bearing vs current heading, arc-width gate
  (`angle <= half[0x26]>>1`), eligibility predicates, **15-slot
  remembered-hit table**, separate dispatch for focused vs other targets.
  Direct replacement model for our hand-tuned aggro/attack ranges.
- `src/arm9/FUN_02064b58.c` — attack/aggro range predicate with
  attachment-type exclusions (0x28, 0x2a–0x2c, 0x38, 0x3d–0x3f…).
- `src/arm9/FUN_02063a18.c` — hit application: 10-entry recent-hit dedupe,
  busy-flag eligibility, special-hit classification (`actor+0x244 == 12`),
  secondary-hit slot masks, feedback-effect dispatch (147-entry factory
  `FUN_0204dc30`).
- `drafts/near/arm9/FUN_020573b0.c` + `FUN_0205c2c8.c` — spawn-table builder
  (group/member/entry strides 8/12/8, weighted member select, 8-element
  order shuffle unless group flag 4) and deployment loader. Together with
  the 1,742 `enemy/deploy/` and `set/` rels (including `_r` rare-room
  variants), this is a path to **1:1 room populations**, not just 1:1 stats.

Still open: enemy **EXP/meseta** — the unread "EXP-shaped column" is not
decoded by the Mini's live code either; expect it from Phase B (retail dead
set) or a targeted retail-side RE pass.

### 6. Bosses — mostly cross-validation for now

The demo has one boss (`enemy/boss_dragon.narc`). Our boss data is already
deeper (11-model catalog from retail + 43k melonDS captures in
`boss_behavior_contract.json`); Reyburn is parity-validated to ±1 Q12 unit.
What the decmp adds: boss-field entry lookup `FUN_02068328`, health-gated
hit-feedback scaling `FUN_02081430` (`r = (scale<<12)/h + 0x1000`), boss AABB
`FUN_020a8320`, and the generic entity SMs (`FUN_0201c308`, `FUN_020645ac`,
`FUN_02064728`) the retail bosses also ride on. When dumped, boss_dragon's
table row is a direct cross-check of our captured dragon/Reyburn stats.
**The authored schedulers (Falz, Mother Trinity, Humilias, Paru robot) can
only become 1:1 via Phase B** — their logic is in the 3,202-function dead
set, not the Mini's live code.

### 7. Weapon attributes — solid already; the gap is per-type timing

The ~360-item dataset is ROM-anchored with wiki-agreement asserted in CI;
grind +2 verified. Structure findings (2026-10-21):

- `item/weapon_id.narc` (ZPR-wrapped NARC, 4,522 → 12,772 B): **27 entries —
  16 × 320 B per-weapon-type DSIF rels (256-byte NDR payload each) plus 11
  special entries** (1408/416×5/736/96/416/496/1520 B) matching the
  `FUN_0206cb5c` group layout. These per-type payloads are the natural home
  of attack-speed/PA-slot data that our hand-tuned `WEAPON_TYPE_CONFIGS`
  approximates; first byte of each wpnprm row (10/40/30/20…) looks like the
  type/model link. Field decode is the remaining RE task.
- `item/wpnprm.rel` (per-weapon rows): 4,592 B DSIF → **362 rows × 12 bytes**
  after a 136-byte sub-header (NDR second field 0x10f8 = 362×12). The Mini
  and retail copies differ by only **26 bytes** — same table, tiny build
  tweaks. Field decode already exists in `psz-re/tools/wpnprm.py` (our CI
  imports it for saber/handgun anchors); the retail copy is available in the
  `psz-asset-viewer` GitHub clone under `raw/item/` (the Projects working
  copy gitignores `raw/`). Extend the CI check to full-set agreement rather
  than re-deriving offsets.
- **Retail provenance source discovered**: `psz-asset-viewer`'s repo carries
  the full retail `raw/` extraction (player, item, enemy, quest dirs). The
  committed `player_lv_param.json` was re-dumped from it; XP now matches
  `experience_table.tres` **99/99** after fixing a pre-existing L46
  totalExp typo (234,820 → ROM 234,720 — the table's own expToNext values
  already implied the ROM number). The Mini's L5–L9 XP differences are
  demo-only tuning, not retail behavior.

Adjacent unbanked-but-present data: `wpneqprm.zarc` (equipment params),
`mag_param.narc` (ZPR→NARC→one 608 B DSIF with a 512-byte table — real mag
feeding values vs our tuned ones), `pb_param_data.rel` (Photon Blast — CI
already pins its charge buckets), `shop1–7.narc` (real shop stocks),
`item/paeff00–16.rel` (per-type PA effects), `uniprm/genprm/proprm.rel`
(unit/general/projectile params), `apc/apc_param.zarc` (companion AI: action
sets, equipment, sp actions, tactics — 5 DSIF rels).

### 8. Techniques — no source found yet

No technic-named file in the Mini filesystem and no technic references in the
matched set. Tech power is either inside `genprm.rel`/`global_dat.narc`/
lv_param aux rows or only in the dead retail code. Keep the invented
`TECHNIQUES` table flagged as unsourced; revisit after the param-rel readers
are ported or Phase B opens.

## Prerequisite tooling — already solved

The one-time dumper prerequisite from the first draft of this audit is
**already covered by our own tooling**:

- **[DashGL/ArchiveUnpacker](https://github.com/DashGL/ArchiveUnpacker)** (our
  MIT TypeScript library, zero deps) — ZPR (XOR-0x95 + PRS), ZARC container,
  NARC. **Verified against the Mini's files in this audit** via a faithful
  Python transcription: `wpnprm.rel` and every `item/drop/*.narc` decompress
  cleanly (the `.narc` drop files are ZPR-wrapped under the extension);
  `player_lv_param.zarc` parses as a plain ZARC.
- **[DashGL/psz-asset-viewer](https://github.com/DashGL/psz-asset-viewer)** —
  holds a full retail `raw/` extraction (same filesystem layout as the decomp's
  `extracted/files/`) plus Bun exploration scripts for weapon models, enemies,
  player animations, and item effects. Useful for mapping narc contents to
  assets; its scripts target models/textures, not stat tables — table decode
  knowledge still comes from the decomp's banked readers.

Remaining work is landing a small `scripts/tools/` dumper (the validated
Python port from this session is the starting point) that emits into
`data/re_reference/` with `source` fields per repo convention, plus CI anchors
once values are cross-validated against retail psz-re extracts.

## Validation results (2026-10-21, this session)

Proof-of-concept decode of the Mini's `player/player_lv_param.zarc` using a
Python port of ArchiveUnpacker, confirming the audit's level-rows item:

- ZARC → **14 × `player_param_XX.rel` (2,480 B) + `player_type_param.rel`**
  (192 B; holds repeated 100/80 constants in 8 groups — cap-like values,
  consumer decode needed).
- Each param file: DSIF container, NDR section, **100 rows × 24 bytes** from
  0x30 — exactly the `FUN_020412d8` layout. Seven nonzero u16 stat columns,
  **monotonically non-decreasing for all 100 levels** (class 0: HP-ish column
  82 → 482 (L50) → 700 (L100), etc.). These are the real curves that can
  replace our authored `{20,40,60,80}` breakpoints.
- Row-tail u32 = cumulative XP: **93/99 levels match our retail-derived
  `experience_table.tres` exactly**. Diffs: L5–L9 (Mini ramps slower: e.g.
  L7 1,250 vs retail 1,710) and L45 (234,720 vs 234,820) — a genuine
  Mini-vs-retail divergence; **retail stays authoritative** where they differ.
- Drop tables: each `item/drop/{tier}{1-8}.narc` is ZPR → NARC with **3 named
  DSIF rels** (`enemy_normal.rel` ~5.2 KB, plus two ~200–340 B tables).
  `enemy_normal.rel` rows visibly carry the `FUN_020577ac` weighted-select
  shape — recurring weight **50,000** (per-100k, i.e. 50%) with id/mode
  fields. Field-by-field decode still requires the consumer RE (unbanked),
  as expected.

## Direction (owner, 2026-10-21) — behavior over content

psz-godot is leaning into its western-punk/PSO identity: normal weapons
(sabers, brands, …) are original thematic content that makes photon weaponry
stand out. So item/equipment CONTENT (weapon lists, drops, shop stocks,
rare tables) is creative territory — wiki-sourced lists suffice and the ROM
drop/shop tables are **deprioritized**. What we take from the original game
is **gameplay behavior**: stats, targeting, enemy AI, bosses, timings,
hits/hitboxes, combos, and stage generation. The roadmap below is ordered by
that.

### Animation timings — EXTRACTED (clips only) + the real combat-window table

Two different datasets, now both extracted:

1. **Clip lengths** (`data/re_reference/player_anim_timings.json`, rerun:
   `dump_player_anim_timings.py --viewer <viewer>`): exact per-type clip
   frames at 30fps from the GLBs — saber combo 17/18/16f, sword 23/23/25f,
   handgun 14/15/17f, PAs, technique casts, and the hit-reaction family
   (`dam_n` 6f, `dam_h` 19f, `dam_d` 19f+loop+get-up). These are the
   ANIMATIONS — bounds and pacing reference, not the gameplay windows.
2. **Action parameter rows** (`data/re_reference/player_action_params.json`,
   rerun: `dump_player_action_params.py --raw <raw/>`): the actual per-type
   gameplay timing windows around the attack chain. Inside every
   `raw/player/XX_type_[m|w]_pa00.narc`, next to the animations, rides a
   DSIF rel whose shared 152-byte action rows carry ~25–35 per-type bytes:
   per combo step a window total + hit-window byte pairs + event bytes,
   plus a fourth row with the heavy/PA event list. Saber windows
   20/22/23 vs clips 17/18/16; sword 44/43/48 vs clips 23/23/25 — the
   gameplay window is deliberately longer than the clip (continue/cancel
   margin). Which byte is hit-frame vs combo-continue vs heavy-branch is
   **pending the consumer function** — the player action driver is the top
   decomp-session ask (it reads this table and drives the 30Hz action
   clock, the same descriptor playback the boss code already ports).
   `weapon_id.narc` turned out to be an item-resource resolver (six
   10-bit fields per row, 1023=invalid — model/effect resource picks), not
   timing data; the small `paeff*.rel` files are effect-chain tables for
   the `FUN_0204dc30` effect factory.

### Stage generation — inventory extracted; generator logic is the target

`data/re_reference/stage_room_inventory.json` (rerun:
`dump_stage_room_inventory.py --raw <raw/>`) maps the original floor
vocabulary from the retail file tree:

- 9 areas: s00 city (nr1–nr6 rooms), s01–s07 fields (two layout variants
  a/b each, ~19–23 room slots, entry `e` room, boss `z` room), s08 tower
  (per-floor structure s081–s086 + caps).
- Room-shape families by code prefix (ga, ib, ic, lb, lc, na, nb, nc, sa,
  tb, tc, td, xb) with per-room variant pools: set rels `_d` `_f1.._f4`
  `_s` (+ `_r` rare) and matching `enemy/deploy/<mode>/` tables — the
  original generator picks among per-room LAYOUT variants (a/b alternate
  which f-slot they skip), not freeform grids.
- `quest/random_dungeon.rel` decodes to a tiny DSIF config (28 bytes) —
  includes a doubling series 50/100/200/400/800 (depth/difficulty scaling?);
  the actual room-graph selection logic is code-side.
- Code-side assets: spawn/wave allocator semantics fully recovered in
  `drafts/near/arm9/FUN_020573b0.c` (group/member/entry table schema below),
  deployment loader `FUN_0205c2c8.c`, weighted-select `FUN_020577ac.c`
  (banked). The room-LINKING algorithm (how rooms chain into a floor) is in
  the dead retail set — the main Phase B request alongside boss schedulers.
  Until then, sampling our grid generator from the inventory (same room
  families, same variant-pool behavior) is achievable now.

**Spawn/wave table schema (FUN_020573b0, semantics recovered):** group
stride 8 `{first-member half, count, state, seed, flags, used}`; member
stride 12 `{group, count, first-entry, metadata×2, variant, max}`; entry
stride 8 `{kind, order, flags, parent-member}`; count chosen by
`FUN_02057794`, members weighted-selected by `FUN_020577ac`, spawn order
shuffled by an 8-element permutation unless group flag 4. (A final flag2
selection loop is compiled-out/disabled in the ROM — count starts 0 and
tests < 0; do not "fix" it.)

### Recommended order (behavior-first)

1. **Combo/hit-reaction timing**: decode the action-param row semantics
   (decomp ask: the player action driver consuming the pa00 DSIF table) and
   retune `WEAPON_TYPE_CONFIGS` windows from `player_action_params.json`
   (windows, not clips). Until the field mapping lands, clips are pacing
   bounds only — S once mapped.
2. **Stage generation**: switch the grid generator to sample the real room
   inventory + variant pools; port `FUN_020573b0`'s group/member/entry wave
   allocator over the deploy rels for 1:1 room populations — M.
3. **Enemy targeting**: port `FUN_02072774` scanner semantics (arc-width
   gates, 15-slot remembered-hit, focused-vs-other dispatch) and
   `FUN_02064b58` range predicate into `enemy_base` — M.
4. **Hit application**: `FUN_02063a18` (10-entry recent-hit dedupe,
   eligibility, feedback effect factory `FUN_0204dc30`) — M.
5. **Combat chain wiring**: crit% stat-sum (needs attack-vector fill RE),
   variance (`FUN_02044038` field names — decomp request), status chain +
   `020cbc04` level tables, defender ×0.8 state, ranged +5% crit band — M,
   partially blocked on fill functions.
6. **Enemy entity SMs** (`FUN_0201c308`, `020645ac`, `02064728`, `0204e2ac`)
   as the reference architecture for behavior upgrades — L.
7. **Phase B requests** (bank as decomp-session asks): **player action
   driver** (consumer of the pa00 action rows — unlocks #1), room-graph
   generator, Falz/Mother/Humilias schedulers, enemy EXP, technic power,
   APC tactics consumers (`apc_param.zarc` rels decode but need field
   semantics).

Previously completed: RNG port (`scripts/utils/psz_rng.gd`), ROM-exact class
stat rows + retail XP provenance (L46 typo fixed), boss captures (existing),
enemy stat table (existing).

## Path reference (decomp repo-relative)

- Damage: `src/arm9/FUN_020440c8.c`, `drafts/near/arm9/FUN_02044f2c.c`,
  `drafts/near/arm9/FUN_020441a8.c`; RNG: `src/arm9/FUN_0203e874.c`,
  `FUN_02045d84.c`, `FUN_02045d5c.c`
- Drops/spawn: `src/arm9/FUN_020577ac.c`, `drafts/near/arm9/FUN_020573b0.c`,
  `FUN_0205c2c8.c`; data under `extracted/files/item/drop/`,
  `enemy/deploy/`, `set/`
- Levels/stats: `src/arm9/FUN_020412d8.c`, `FUN_02041118.c`, `FUN_0203e570.c`;
  data `extracted/files/player/player_lv_param.zarc`
- Weapons/items: `src/arm9/FUN_0206cd8c.c`, `FUN_0206cb5c.c`; data
  `extracted/files/item/` (weapon_id, wpnprm, wpneqprm, mag_param, paeff*,
  shop/, text/)
- Enemy behavior: `drafts/near/arm9/FUN_02072774.c`, `src/arm9/FUN_02064b58.c`,
  `FUN_02063a18.c`, `FUN_0201c308.c`, `FUN_020645ac.c`, `FUN_02064728.c`
- Boss machinery: `src/arm9/FUN_02068328.c`, `FUN_02081430.c`, `FUN_020a8320.c`
- Decompression/NARC: `src/arm9/FUN_020a6308.c`, `FUN_020aa8b4.c`,
  `FUN_020ab014.c`, `drafts/arm9/FUN_020a6378.c`
- Strategy context: `notes/project-direction.md` (Phase A/B split),
  `notes/parked-ledger.md`, `AGENTS.md`
