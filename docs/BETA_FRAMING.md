# Beta framing — the objective, the coverage map, and the execution order

Written at the beta cut (2026-06-12, v0.34.3) as the orientation document for
whoever executes Beta. Read this before picking up any Beta issue.

## The objective

**Make Phantasy Star Zero, in the style of Phantasy Star Zero.** Authentic
recreation is the bar: PSZ's systems, PSZ's feel, PSZ's structure. Where our
quests diverge from the original's content (they deliberately do — see #331),
the *systems* around them stay faithful. When a mechanic's exact behavior is
unknown, the references below beat invention; when the references are silent,
match the feel of the DS original and write the decision into the spec.

The Beta milestone definition is the contract: *story quests completable;
telepipes, backtracking, death/recovery, HUD, shops, inventory, save flow all
work; combat tuned enough to finish the story.*

## Non-goals (explicit, so nobody re-litigates them)

- **Multiplayer / online.** Companion NPCs (already implemented) are this
  game's answer to the party slot. No netcode in Beta or after.
- **Visual chat** (PSZ's touchscreen doodle chat) — signature but pointless
  without multiplayer. Quick-chat shortcuts (#126) carry the flavor.
- **Canon quest/reward data fidelity** — our quests are original (#331).

## Reference assets

| What | Where | Use for |
|---|---|---|
| PSOBB decompiled client | `~/projects/psobb-client-source` | Damage/accuracy formulas (`headers/battle.h` — symbol-level, constants located), boss FSM architectures (`headers/bosses.h` + `tests/dragon_fsm`), item/mag struct layouts (`headers/items.h`), animation speed tables |
| kion's targeting RE | github.com/kion-dgl/psobb-re | Targeting + hit-detection writeup (#156's basis) |
| PSZ ROM data | already extracted into `data/` where we have it | Photon Art table (#95), trap items, class trap limits |

PSOBB is the *mechanics* reference (PSZ inherited its combat math lineage);
PSZ-specific systems (just-attack, traps, PB pacing, dodge) follow the DS
game where they differ. The headers are curated and trustworthy; the raw
`src/*.c` dump is searchable when a header is silent.

## Coverage map (system → state → issue)

**Combat foundation** — the dependency spine, in order:
1. #157 CombatResolver: damage formula + accuracy + hitbox presets + frame
   windows. Everything below consumes it. Increment 1 absorbs the #215
   CombatResolver deferral as new spec'd behavior.
2. #155 combo timing (three-tier, just-attack) — plugs into #157 inc 4.
3. #156 camera-focus targeting (scoped down; own RE writeup).
4. #56 / #57 melee + ranged archetype content (rescoped: content, not systems).
5. #95 Photon Arts (data-driven specials on the attack path).
6. #62 bosses (FSM architectures from bosses.h; arena/HP-bar/phase machine).
7. #108 boosted auras (needs design note first; BattleParams-style multipliers).
8. #94 traps (independent; can ship early — items/limits data already exist).

**Coverage gaps found at the cut (filed 2026-06-12):**
- #341 death & recovery (milestone-definition item with no prior issue;
  scape dolls exist as items but nothing consumes them).
- #342 Photon Blast (mags are half-built: feeding/forms done, PB absent).
- #343 character progression (exp/level skeleton exists; growth tables,
  kill-exp wiring, learning gates unverified).
- #344 difficulty unlock loop (all per-difficulty data exists; no gating).
- #345 support techniques (shifta/deband partial; resta/anti/reverser/
  jellen/zalure incomplete or absent).
- #346 backtracking & field-flow audit (milestone-definition item; #239
  covers two bugs, this audits the rest + adds a matrix backtrack phase).

**Systems/UI:** #239 telepipe bugs (first PR — live playtest bug), #190 DOE
scaled reward (trivial on #318 machinery), #141 + #126 quick menu + dpad
(one shared binding spec), #97 multi-resolution, #44 dynamic shops
(design-first, deprioritized — static shops are beta-playable).

**Stale audits:** #177–#181 Alpha quest checklists — reconcile against the
shipped game and close (the #215-reconcile pattern).

## Suggested execution arc

1. **Warm-ups** (independent, build trust in the gates): #239 → #190 → #344.
2. **Foundation**: #157 inc 1–2 (resolver + accuracy) → #343 audit (exp
   loop rides on resolver-adjacent code) → #341 death flow.
3. **Combat content wave**: #157 inc 3–4 → #155 → #56/#57 archetype by
   archetype → #95 PAs → #94 traps → #342 PB.
4. **Capstones**: #62 bosses, #108 auras, #345 support techs.
5. **Throughout**: #97/#141/#126 UI as palate cleansers; #346 audit before
   the backtracking-heavy mid-beta; #44 only after everything above.

## The working agreement (enforced, not aspirational)

Full text: spec `/engineering` (+ CLAUDE.md condensed copy). The short form:
- Hierarchies: behavior in bases, leaves justify themselves, data in
  resources, spec page per hierarchy. Shop screens stay composition (Android).
- Debt: ratchet blocks new debt; growing a baseline needs `Debt-Accepted:`
  and belongs at the END of beta.
- Tests: anything frame/timing/combat gets BOTH a seeded unit test and a
  post-build autopilot probe. One layer is not done planning.
- Gates per PR: suite + ratchet + sanity-check for exact HEAD; full
  regression matrix before merging combat-behavior changes; stop the chain
  at the first failed phase.

## Known traps (learned the hard way; memories exist for each)

- Autopilot reads screen privates via `node.get("_x")` — grep autopilot.gd
  before renaming screen state (#335).
- Pack-only asset preloads can't compile in repo-only CI; `test_script_parse`
  has the skip — don't widen it casually.
- GLB edits need a headless reimport before the next autopilot run.
- Quest chains: a child quest must start from its parent's post-save.
- `.sanity-pass` is HEAD-exact — every commit invalidates it.
