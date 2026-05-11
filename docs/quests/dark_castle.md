# Dark Castle — Quest Flow

## Overview

**Location:** dark | **Sections:** 4 (A(grid) → E(transition) → B(grid) → Z(boss))  
**Companion:** _none_ | **Office NPCs:** Principal (pos_1)

_Falz boss, Lassic's ethereal castle remains._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Defeat the boss: `dark_falz` (Defeat Dark Falz, target 1).

**TODO** — boss-fight beats: HP/behavior placeholder vs. real AI, boss intro line, death line, on-clear telepipe/warp behavior. Note: boss `.tres` may still need to be authored if this is a placeholder ID.

## Briefing (Office)

Office NPCs: Principal (pos_1).

> **Principal:** Kai is missing.
>
> **Principal:** He left for Makara six hours after the seal in the inner chamber broke. Took two team members and a comm channel. The team came back. He didn't.
>
> **Principal:** We're not assuming anything yet. He could be alive. He could have lost his bearings inside the structure that's now open. He could have followed something in.
>
> **Dr. Carlo:** The ruins are still there. So is whatever was sealed. If he went deeper, he went into something we don't have a name for.
>
> **Principal:** Find him. Bring him back if you can.
>
> **Principal:** And if you can't... bring back the truth.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

No companion.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `a` (grid)

- **Cells:** 12 · start `4,2` → end `4,1`
- **Entry/exit:** - / south
- **Stages used:** `s07a_ga1`, `s07a_ib1`, `s07a_ic3`, `s07a_lb1`, `s07a_lb3`, `s07a_lc1`, `s07a_lc2`, `s07a_nb2`, `s07a_nc2`, `s07a_sa1`, `s07a_tb3`, `s07a_tc3`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `e` (transition)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / north
- **Stages used:** `s07e_ia1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 2 — `b` (grid)

- **Cells:** 10 · start `2,4` → end `3,4`
- **Entry/exit:** south / east
- **Stages used:** `s07b_ga1`, `s07b_ib1`, `s07b_lb1`, `s07b_lc1`, `s07b_lc2`, `s07b_na1`, `s07b_sa1`, `s07b_tb3`, `s07b_td2`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 3 — `z` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** west / -
- **Stages used:** `s07z_na2`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

## Quest Flow

**TODO** — flesh out into a mermaid diagram once dialog beats are set. See `apothecary_supply.md` for the convention.

```mermaid
flowchart TD
    BRIEF[Briefing] --> START[Enter quest area]
    START --> SEC0[Section 0 (A)]
    SEC0 --> SEC1[Section 1 (E)]
    SEC1 --> SEC2[Section 2 (B)]
    SEC2 --> SEC3[Section 3 (Z)]
    SEC3 --> END[Quest complete]
```
