# PSZ Mini decomp — 1:1 accuracy audit (2026-10-21)

Audit of what `https://psp2i.dev/rozalin/pszm-decomp` (private, cloned to
`/tmp/pszm-decomp` for this audit) can contribute to psz-godot, system by
system, versus what the project already sources from `psz-re` and wikis.

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

### 1. Combat math — finish the recovered chain (high value, small effort)

`scripts/utils/combat_math.gd` carries the retail core (ARM9 02042A4C/
02042964): `(atk×4/10) − ((def×819+2048)>>12)`, Q12 multiplier scale. The
decomp's banked Mini twin `src/arm9/FUN_020440c8.c` matches this structure
exactly — cross-build confirmation — **and adds everything around it that we
currently invent**:

- `drafts/near/arm9/FUN_02044f2c.c` — full hit dispatch: part-based
  attack[59]/defence[29] vector filling via attacker/defender vtables,
  guaranteed-hit path (flag bit 0), miss flagging, and the final damage value
  extraction (`FUN_02036d14`).
- `drafts/near/arm9/FUN_020441a8.c` (0xad4, semantics mapped in header) — the
  damage arm with the **percentage chains**: this is where crit and variance
  actually roll. Replaces our authored "5% crit, +50%, ±10% variance"
  (`spec/src/pages/states/combat-progression.astro` lists these as remake
  choices today). Second arm `FUN_02044cac` is unbanked (ranged/tech path).
- `src/arm9/FUN_020440c8.c` also encodes the always-hit rules we already
  mirrored (types 2/3 bypass) plus a ranged/distance attenuation branch
  (`scale = 100 − factor×2>>12`) we don't have.
- Attribute grid: `src/arm9/FUN_020abfb8.c` + `drafts/near/arm9/FUN_020ad9bc.c`
  — 3×3 category A/B rule entries `{category, receive, invert}` with Q12
  blend (0x3e8000 scale, clamps 0x800/0x1000). This is the engine's real
  native/beast/machine/dark multiplier machinery behind our
  `attribute_attack()`.

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

### 3. Drops — the biggest win available

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
grind +2 verified. The decomp's `src/arm9/FUN_0206cb5c.c` decodes
`item/weapon_id.narc` (4.5 KB — **per weapon-type**, not per-weapon): entries
0–15 carry 216-byte payloads, plus special entries (16 → 1320 B, 20 → 648 B,
etc.). Field meanings are unconfirmed in the decomp, but these payloads are
the natural home of **attack-speed/animation timing** — precisely what our
`WEAPON_TYPE_CONFIGS` combo windows (`combat_manager.gd:107–358`, "initial
#554 tuning, not DS timing") hand-tune. Decoding them is a bounded RE task
with a banked consumer as reference. Adjacent unbanked-but-present data:
`wpneqprm.zarc` (equipment params), `mag_param.narc` (385 B — real mag
feeding table vs our tuned values), `pb_param_data.rel` (Photon Blast),
`shop1–7.narc` (real shop stocks vs our authored inventories),
`item/paeff00–16.rel` (per-weapon-type PA effects), `uniprm/genprm/proprm.rel`
(unit/general/projectile params).

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

## Recommended order

1. **Port RNG** (`FUN_0203e874/45d84/45d5c`) — S, unblocks meaningful odds.
2. **Land the table dumper** (validated Python port of ArchiveUnpacker →
   `scripts/tools/`) **+ drop-table decode with `FUN_020577ac`** — M,
   replaces the least-sourced system (drops) with 24 real weighted tables.
3. **Combat chains** (`FUN_02044f2c`/`441a8` semantics) — M, replaces
   authored crit/variance/strong-attack math with the recovered percentage
   chains.
4. **Level rows — decode done** (`data/re_reference/player_lv_param.json`,
   class mapping resolved). Remaining: consume real rows in `class_data.gd`,
   re-dump from retail zarc, material caps (`FUN_0203e570`) — S–M.
5. **Enemy targeting/hit semantics** (`FUN_02072774`, `02064b58`, `02063a18`)
   and, if desired, 1:1 room populations from `deploy/`/`set/` rels — M–L.
6. **Weapon-type payload decode** (attack timing) + mag/PB/shop tables — M,
   after the dumper lands.
7. **Phase B watch** — enemy EXP, retail boss schedulers (Falz/Mother/
   Humilias), and technic power all live in the dead retail set; bank
   questions for the decomp repo's next sessions rather than inventing.

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
