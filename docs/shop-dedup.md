# Refactor tracker — shop de-duplication (`ShopBase`)

Eight shop/menu screens under `scripts/2d/shops/` (+ `storage.gd`,
`equipment_screen.gd`) all `extends Control` with **no shared base** and a lot
of copy-pasted scaffolding. Goal: extract a `ShopBase` that owns the shared
plumbing, collapse the pure duplication, and turn the *drift* (same function,
divergent code) into explicit override hooks so a fix reaches every shop.

This is the map we refactor against (companion to a player-facing
`/mechanics/shops` behavior page). Lower-risk than the player.gd split and the
duplication is already visible.

## The screens

| Script | Lines |
|---|---|
| `scripts/2d/shops/crafting_shop.gd` | 796 |
| `scripts/2d/shops/weapon_shop.gd` | 642 |
| `scripts/2d/shops/item_shop.gd` | 601 |
| `scripts/2d/storage.gd` | 570 |
| `scripts/2d/equipment_screen.gd` | 498 |
| `scripts/2d/shops/tekker.gd` | 395 |
| `scripts/2d/shops/photon_shop.gd` | 303 |
| `scripts/2d/shops/tech_shop.gd` | 280 |

All `extends Control`. ~4,085 lines total.

## Common flow (each node/arrow is a real function — this is the de-dup map)

```
_ready ──> _setup_portrait
       ──> _load_shop_items / _generate_*   (build the lists)
       ──> _refresh_display
                 ▲
_unhandled_input ─┤── up/down ──> _update_selection ──> _refresh_display
                  ├── repeat held ──> _on_nav_repeat ──> _update_selection
                  ├── confirm ──> _open_confirm_modal ──> _open_*_confirm
                  │                       └─> _buy_selected / _sell_selected ──> _refresh_display
                  └── cancel ──> close
helpers: _get_meseta, _get_current_list, _update_hint
```

## Dup / drift matrix (verified by hashing each function body per shop)

🟢 pure dup (identical bytes) · 🟡 partial (some shops identical) · 🔴 drift (same name, different code) · ⚪ legitimately per-shop

| Function | Class | Notes |
|---|---|---|
| `_get_meseta` | 🟢 | byte-identical in all 4 that define it — lift verbatim |
| `_on_nav_repeat` | 🟢 | byte-identical across all 7 — lift verbatim |
| `_setup_portrait` | 🟡 | `photon_shop` == `crafting_shop` (identical 35L); `item`/`weapon` are 2-line stubs; `tekker`/`storage` differ — collapse the identical pair, hook the rest |
| `_open_confirm_modal` | 🔴 | first ~5 lines (list/bounds/selected-item guard) identical everywhere, then per-shop confirm bodies (item: disk/sell/bulk-buy; weapon: prompt+`on_yes`) — base owns the guard, shops override the body |
| `_unhandled_input` | 🔴 | all 8 differ — but all are the same nav skeleton (dir keys → selection, confirm/cancel) with shop-specific actions — base owns the skeleton, shops supply actions |
| `_refresh_display` | ⚪ | all 8 differ (66–120L) — genuinely per-shop content rendering; **stays an override**, not duplication |

## `ShopBase` shape (template method)

- **Lift to `ShopBase extends Control` (shared):** `_get_meseta`, `_on_nav_repeat`,
  selection state (`_selected_index`, `_update_selection`), the
  `_unhandled_input` nav skeleton, the `_open_confirm_modal` guard, and a
  shared confirm helper (`_confirm(prompt, on_yes)`).
- **Overridable hooks (legit per-shop):** `_get_current_list()`, the confirm
  body / `_confirm_selected(item)`, `_refresh_display()` (content), tabs, and
  `_setup_portrait()` for the shops that diverge.
- **Reconcile:** fold the identical `photon`/`crafting` `_setup_portrait` into
  the base; audit the `_unhandled_input` key-handling differences for any that
  are accidental vs intentional.

## Coverage (the forcing function)

Shops are **not** in the autopilot regression matrix (it never opens a shop).
`scripts/tools/test_runner.gd` has `test_shops` (logic-level), but the UI/nav
and confirm-modal paths — exactly the drifted code — aren't covered. **Before
changing the drifted `_unhandled_input` / `_open_confirm_modal`**, add a
shop-interaction smoke (open shop → navigate → buy → confirm meseta/inventory
change) or rely on manual verification, so nav/confirm regressions are caught.

## Canonical names & naming drift

Canonical names (the player-facing list). The data `.tres` `name` field is the
authority where one exists; the drift is in code/scene/title strings.

| Canonical | data id | script / scene | drift to reconcile |
|---|---|---|---|
| **Item Shop** | `item_shop` | `item_shop` | — (consistent). **Sells technique disks** via its Disks tab. |
| **Weapon Shop** | `weapon_shop` | `weapon_shop` | — |
| **Tekker** | — | `tekker` | uses a `Mode` enum (Grind/Identify), not `Tab` like the others |
| **Photon Collector** | `photon_collector` | `photon_shop` | canonical name confirmed "Photon Collector" (it trades photon drops, not meseta). Only file-level drift remains: scene/script is `photon_shop`. Rename deferred (risky), not a player-facing issue. |
| **Synthesis Shop** | — | `crafting_shop` | code identifier is `crafting_shop`; player-facing title/NPC already say "Synthesis Shop". File/scene/id rename deferred (risky). |
| **Blackjack** | — | `scenes/2d/blackjack/blackjack_table.tscn` | not under `shops/`; gambling table |
| **Storage Counter** | — | `storage` | a bank, not a vendor |
| **Guild Counter** | — | `guild_counter` | quest accept/report, not a vendor |

Fixed this pass: `tech_shop` title `"TECH SHOP"` → `"Tech Shop"` (casing).

**Redundant: standalone `tech_shop`.** Technique disks are sold in *two* places —
the Item Shop's **Disks** tab (`TechniqueManager.generate_shop_inventory`) and the
standalone `tech_shop` (own script/scene/`.tres`, routed from the city Services
menu). Disks are canonically the Item Shop's. **Remove the standalone `tech_shop`**
(script, scene, `.tres`, the Services-menu route) once nothing else depends on it.

## Buy affordance (a `ShopBase` responsibility)

The intended UX is **not** reactive rejection. The player can select any item to
read its details, but the **Buy action is disabled** (greyed, with a reason —
"No room" / "Lv N req" / "Can't afford") for anything they can't take, so they
never reach a rejection. That makes a shared predicate `_can_buy(item) -> {ok,
reason}` plus disabled-row rendering a base-class job (today each shop reimplements
afford/room checks inline, or not at all). See `/mechanics/shops`.

## Plan (layered, one PR each)

- [x] **0. Docs** — this tracker + `/mechanics/shops` + the top-level Architecture
      page & layer color-coding.
- [x] **0b. Remove standalone `tech_shop`** (done) — disks live in Item Shop; drop the
      redundant script/scene/`.tres` + Services-menu route.
- [x] **1. `ShopBase` + pure dups** (done) — new `scripts/2d/shops/shop_base.gd`;
      lift `_get_meseta` + `_on_nav_repeat`; make the screens extend it.
      Lowest risk (identical code), validated by `test_shops` + reimport.
- [ ] **2. Buy affordance** — base owns `_can_buy(item) -> {ok, reason}` + disabled-row
      rendering; shops stop reimplementing afford/room checks.
- [ ] **3. Nav skeleton** — move the shared `_unhandled_input` skeleton into the
      base with action hooks; reconcile accidental key drift.
- [ ] **4. Confirm flow** — base owns the `_open_confirm_modal` guard + a
      `_confirm()` helper; shops override the body.
- [ ] **5. Portrait** — collapse the identical `photon`/`crafting` setup; hook the rest.

## Status log
- 2026-06-06 — Added buy-guard regression tests to `test_shops` (affordability
  + room: `buy_item` refuses + leaves state unchanged) as the pre-change net for
  increment 2 — the invariants `_can_buy()` must mirror. Tests 1413/0.
- 2026-06-06 — Canonical names settled (Item/Weapon/Tekker/Photon/Synthesis/
  Blackjack + Storage/Guild counters); naming drift + standalone-`tech_shop`
  redundancy logged; `_can_buy` affordance added to the plan. Fixed `tech_shop`
  title casing.
- 2026-06-06 — Tracker created. Dup/drift matrix verified by per-function body
  hashing (corrected one false-positive: `_on_nav_repeat` is pure dup across all
  7, not drifted). No code changed yet — docs first.
