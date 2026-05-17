# Finding Ogi — Quest Flow

## Overview

**Location:** rioh | **Sections:** 4 (A(grid) → E(transition) → A(grid) → Z(boss))  
**Companion:** `ren` | **Office NPCs:** Ren (pos_1)

_A veteran CAST hunter has gone missing in the Rioh Snowfield. Find him and recover his body parts._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Collect 6 quest items:

| # | item_id | Label | Target |
|---|---|---|---|
| 1 | `ogi_head` | Ogi's Head | 1 |
| 2 | `ogi_body` | Ogi's Body | 1 |
| 3 | `ogi_right_arm` | Ogi's Right Arm | 1 |
| 4 | `ogi_left_arm` | Ogi's Left Arm | 1 |
| 5 | `ogi_right_leg` | Ogi's Right Leg | 1 |
| 6 | `ogi_left_leg` | Ogi's Left Leg | 1 |

**TODO** — pickup placements (section, cell), per-item reaction dialog from the companion, and remaining-count banter pattern.

## Briefing (Office)

Office NPCs: Ren (pos_1).

> **Ren:** We've lost contact with Ogi. He's a CAST, deployed to the Rioh snowfield three days ago.
>
> **Ren:** His patrol channel went dark mid-route. No distress, no last transmission. Just silence.
>
> **Ren:** We don't know what happened. Find out. Bring back what you can.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

Companion: `ren`.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `a` (grid)

- **Cells:** 9 · start `0,2` → end `2,4`
- **Entry/exit:** - / east
- **Stages used:** `s03a_ic1`, `s03a_lb3`, `s03a_lc1`, `s03a_lc2`, `s03a_nb2`, `s03a_nc2`, `s03a_sa1`, `s03a_tb3`, `s03a_tc3`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `e` (transition)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / north
- **Stages used:** `s03e_ia1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 2 — `a` (grid)

- **Cells:** 15 · start `4,2` → end `0,4`
- **Entry/exit:** south / north
- **Stages used:** `s03a_ga1`, `s03a_ib1`, `s03a_ib2`, `s03a_ic1`, `s03a_ic3`, `s03a_lb1`, `s03a_lb3`, `s03a_lc1`, `s03a_lc2`, `s03a_na1`, `s03a_nb2`, `s03a_nc2`, `s03a_sa1`, `s03a_tb3`, `s03a_xb2`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 3 — `z` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / -
- **Stages used:** `s03z_na1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

## Quest Flow

**TODO** — flesh out into a mermaid diagram once dialog beats are set. See `apothecary_supply.md` for the convention.

```mermaid
flowchart TD
    BRIEF[Briefing] --> START[Enter quest area]
    START --> SEC0[Section 0 (A)]
    SEC0 --> SEC1[Section 1 (E)]
    SEC1 --> SEC2[Section 2 (A)]
    SEC2 --> SEC3[Section 3 (Z)]
    SEC3 --> END[Quest complete]
```
