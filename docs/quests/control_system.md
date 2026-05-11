# Control System — Quest Flow

## Overview

**Location:** dark | **Sections:** 3 (E(transition) → B(grid) → Z(boss))  
**Companion:** `ogi` | **Office NPCs:** Ana (pos_1), Ogi (pos_2)

_Crumbling infrastructure + Mother Trinity boss._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Defeat the boss: `humilias` (Defeat Humilias, target 1).

**TODO** — boss-fight beats: HP/behavior placeholder vs. real AI, boss intro line, death line, on-clear telepipe/warp behavior. Note: boss `.tres` may still need to be authored if this is a placeholder ID.

## Briefing (Office)

Office NPCs: Ana (pos_1), Ogi (pos_2).

> **Ana:** Forgive me. I followed your hunters back here because I had to see if it was true.
>
> **Ana:** You have CASTs. Machines that think. We have not had anything like them on Arca for centuries.
>
> **Ana:** Mother Trinity has been silent for hundreds of years. Our tradition says her voice failed when the neutrino furnace failed — and we have not had a mind capable of repairing the furnace in living memory.
>
> **Ana:** Your CAST — the one called Ogi — could. If he is willing.
>
> **Ana:** If we can wake her, she may be able to help undo what was done. The Great Blank — what was lost during it — may not be lost forever.
>
> **Ana:** Take Ogi. Take me. Let us try.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

Companion: `ogi`.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `e` (transition)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / north
- **Stages used:** `s06e_ia1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `b` (grid)

- **Cells:** 12 · start `4,2` → end `0,1`
- **Entry/exit:** south / north
- **Stages used:** `s06b_ib2`, `s06b_ic1`, `s06b_ic3`, `s06b_lb1`, `s06b_lb3`, `s06b_lc1`, `s06b_lc2`, `s06b_na1`, `s06b_nc2`, `s06b_sa1`, `s06b_tb3`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 2 — `z` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / -
- **Stages used:** `s07z_na1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

## Quest Flow

**TODO** — flesh out into a mermaid diagram once dialog beats are set. See `apothecary_supply.md` for the convention.

```mermaid
flowchart TD
    BRIEF[Briefing] --> START[Enter quest area]
    START --> SEC0[Section 0 (E)]
    SEC0 --> SEC1[Section 1 (B)]
    SEC1 --> SEC2[Section 2 (Z)]
    SEC2 --> END[Quest complete]
```
