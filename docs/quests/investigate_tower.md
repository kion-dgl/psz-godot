# Investigate Tower — Quest Flow

## Overview

**Location:** tower | **Sections:** 9 (0(grid) → 1(grid) → 2(grid) → 3(grid) → 4(grid) → 5(grid) → 6(grid) → E(transition) → 7(boss))  
**Companion:** `elio` | **Office NPCs:** Mira (pos_1), Elio (pos_2)

_Climb the Eternal Tower and conduct a blade survey._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Defeat the boss: `tower_boss` (Defeat Tower Boss, target 1).

**TODO** — boss-fight beats: HP/behavior placeholder vs. real AI, boss intro line, death line, on-clear telepipe/warp behavior. Note: boss `.tres` may still need to be authored if this is a placeholder ID.

## Briefing (Office)

Office NPCs: Mira (pos_1), Elio (pos_2).

> **Principal:** We've had eyes on the Paru ruins for months. Last week, a structure appeared at the edges that wasn't there before.
>
> **Mira:** It's a tower. Tall — past our cloud-line readings. And it's active. Every band we monitor is pinging off it.
>
> **Elio:** We've been watching it light up sector by sector. Whatever it is, it's coming online.
>
> **Mira:** We need someone to climb it. Document what you find. Recover any logs or terminals you can reach.
>
> **Elio:** I'm coming with you. Mira's notes, my eyes.
>
> **Principal:** Be careful. We don't know what's at the top.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

Companion: `elio`.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `0` (grid)

- **Cells:** 1 · start `1,1` → end `1,1`
- **Entry/exit:** - / north
- **Stages used:** `s080_sa0`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `1` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s081_ga1`, `s081_ib1`, `s081_lb1`, `s081_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 2 — `2` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s082_ga1`, `s082_ib1`, `s082_lb1`, `s082_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 3 — `3` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s083_ga1`, `s083_ib1`, `s083_lb1`, `s083_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 4 — `4` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s084_ga1`, `s084_ib1`, `s084_lb1`, `s084_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 5 — `5` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s085_ga1`, `s085_ib1`, `s085_lb1`, `s085_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 6 — `6` (grid)

- **Cells:** 4 · start `3,1` → end `0,1`
- **Entry/exit:** south / east
- **Stages used:** `s086_ga1`, `s086_ib1`, `s086_lb1`, `s086_sa1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 7 — `e` (transition)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / north
- **Stages used:** `s08e_ib1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 8 — `7` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** south / -
- **Stages used:** `s087_na1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

## Quest Flow

**TODO** — flesh out into a mermaid diagram once dialog beats are set. See `apothecary_supply.md` for the convention.

```mermaid
flowchart TD
    BRIEF[Briefing] --> START[Enter quest area]
    START --> SEC0[Section 0 (0)]
    SEC0 --> SEC1[Section 1 (1)]
    SEC1 --> SEC2[Section 2 (2)]
    SEC2 --> SEC3[Section 3 (3)]
    SEC3 --> SEC4[Section 4 (4)]
    SEC4 --> SEC5[Section 5 (5)]
    SEC5 --> SEC6[Section 6 (6)]
    SEC6 --> SEC7[Section 7 (E)]
    SEC7 --> SEC8[Section 8 (7)]
    SEC8 --> END[Quest complete]
```
