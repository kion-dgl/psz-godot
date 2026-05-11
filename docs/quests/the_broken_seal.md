# The Broken Seal — Quest Flow

## Overview

**Location:** makara | **Sections:** 4 (A(grid) → E(transition) → B(grid) → Z(boss))  
**Companion:** `dr_carlo` | **Office NPCs:** Dr. Carlo (pos_1)

_Makara ruins seal puzzle, door to Dark Shrine._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Reach the boss room (no enemy kill required). Section Z's start cell is the goal.

**TODO** — what happens when the player arrives — cutscene, dialog, transition to a follow-up quest, etc.

## Briefing (Office)

Office NPCs: Dr. Carlo (pos_1).

> **Dr. Carlo:** Surveyors found something at Makara two days ago. A structure. Ruins, technically, but...
>
> **Dr. Carlo:** Our dating estimates put the construction at least a thousand years before the Great Blank. Possibly more.
>
> **Dr. Carlo:** There shouldn't be anything that old still standing. There certainly shouldn't be anything that old still intact.
>
> **Dr. Carlo:** Hunters who've approached the perimeter report hearing voices. Not animal calls — words. None of them speak the language.
>
> **Dr. Carlo:** The surveyors also identified crystal formations in the deeper galleries. I want to document them. I'll need someone capable to escort me in.
>
> **Principal:** Dr. Carlo will be with you. Keep him alive. Let him do his work.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

Companion: `dr_carlo`.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `a` (grid)

- **Cells:** 12 · start `4,2` → end `4,1`
- **Entry/exit:** - / south
- **Stages used:** `s04a_ga1`, `s04a_ib2`, `s04a_ic3`, `s04a_lb1`, `s04a_lb3`, `s04a_lc1`, `s04a_lc2`, `s04a_na1`, `s04a_nb2`, `s04a_sa1`, `s04a_tb3`, `s04a_tc3`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `e` (transition)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / north
- **Stages used:** `s04e_ia1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 2 — `b` (grid)

- **Cells:** 13 · start `4,2` → end `0,2`
- **Entry/exit:** south / north
- **Stages used:** `s04b_ga1`, `s04b_ib1`, `s04b_ib2`, `s04b_ic1`, `s04b_ic3`, `s04b_lb1`, `s04b_lb3`, `s04b_lc1`, `s04b_lc2`, `s04b_na1`, `s04b_sa1`, `s04b_tb3`, `s04b_td1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 3 — `z` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / -
- **Stages used:** `s04z_na1`

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
