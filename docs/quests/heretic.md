# Heretic — Quest Flow

## Overview

**Location:** arca | **Sections:** 2 (A(grid) → Z(boss))  
**Companion:** `sarisa` | **Office NPCs:** Sarisa (pos_1)

_Newman guards + Reve heretic boss._

**TODO** — one-paragraph concept: what is the player here for, why does it matter, what does the player learn or feel by the end.

## Objective

Defeat the boss: `chaos_mobius` (Defeat Chaos Mobius, target 1).

**TODO** — boss-fight beats: HP/behavior placeholder vs. real AI, boss intro line, death line, on-clear telepipe/warp behavior. Note: boss `.tres` may still need to be authored if this is a placeholder ID.

## Briefing (Office)

Office NPCs: Sarisa (pos_1).

> **Principal:** The data we recovered from the tower included activation codes for a teleporter — one we didn't know existed. It links to a place called Arca.
>
> **Sarisa:** I know Arca. I came from there.
>
> **Principal:** Sarisa volunteered the moment we said the name.
>
> **Sarisa:** If we're going, I'm going with you. There are things on Arca only I'll recognize — and things you'll need me to recognize.
>
> **Sarisa:** Don't ask me what to expect. I haven't been home in a long time.
>
> **Principal:** Investigate the facility. Report what you find. And listen to her.

**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to one `briefing_dialog` entry in the JSON.

## Companion

Companion: `sarisa`.

**TODO** — companion's voice/role for this quest: what do they comment on, when, why. Specific lines for: entering each section, mid-section beats, objective-progress callouts, final reaction on clear.

## Sections

### Section 0 — `a` (grid)

- **Cells:** 12 · start `2,0` → end `4,4`
- **Entry/exit:** - / east
- **Stages used:** `s06a_ib1`, `s06a_ic3`, `s06a_lb3`, `s06a_lc1`, `s06a_lc2`, `s06a_na1`, `s06a_nb2`, `s06a_nc2`, `s06a_sa1`, `s06a_tb3`, `s06a_tc3`, `s06a_td1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

### Section 1 — `z` (boss)

- **Cells:** 1 · start `0,0` → end `0,0`
- **Entry/exit:** west / -
- **Stages used:** `s06z_na1`

**TODO** — design notes for this section: enemy mix, key gates, pickup/log placements, companion banter beats.

## Quest Flow

**TODO** — flesh out into a mermaid diagram once dialog beats are set. See `apothecary_supply.md` for the convention.

```mermaid
flowchart TD
    BRIEF[Briefing] --> START[Enter quest area]
    START --> SEC0[Section 0 (A)]
    SEC0 --> SEC1[Section 1 (Z)]
    SEC1 --> END[Quest complete]
```
