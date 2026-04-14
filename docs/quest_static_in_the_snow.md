# Quest: Static in the Snow

**Location:** Rioh Snowfield | **Theme:** Search & Rescue (solo)  
**Objective:** A research team has gone silent in the snowfield. Locate them.

No companion. No client in the office. The player goes in on a lost-signal report from the Principal, traces the expedition's path through their logs, and discovers Dr. Carlo at the camp. First meeting.

## Briefing (Guild Office)

| # | Speaker | Dialog |
|---|---------|--------|
| 1 | Principal | We've lost contact with a research team in the snowfield. Their last transmission was mostly static. |
| 2 | Principal | They were conducting survey work in the deep snow region. We don't know what happened. |
| 3 | Principal | Head to the snowfield and locate the expedition camp. Bring the team home safely. |

## Mission Flow

```mermaid
flowchart TD
    subgraph office["Guild Office"]
        briefing["Briefing with Principal"]
    end

    subgraph sectionA["Section A — Rioh Snowfield (area a)"]
        A_02["0,2 START\ns03a_sa1"]
        A_12["1,2 BRANCH\ns03a_tb3\n3 Reyhound, 1 Usanny"]
        A_11["1,1 branch\ns03a_nb2\n2 Usanny + boxes"]
        A_13["1,3 KEY\ns03a_ib1\n4 Reyhound, 3 Stagg\n+ 2 Usanny (w2)\n5 boxes"]
        A_14["1,4 GATE + BRANCH\ns03a_tb3\n6 Reyhound\nFence + Switch\n---\nLog: Provisions running low\nLog: Visibility dropping fast"]
        A_04["0,4\ns03a_lb3\n2 Usanny, 1 Reyhound\n3 boxes"]
        A_24["2,4 branch\ns03a_nc2\n1 Stagg, 1 Usanny + box"]
        A_03["0,3 END\ns03a_lb1\n3 Stagg (w2), 1 Usanny,\n1 Reyhound\n2 boxes + rare box\n---\nArea warp north"]

        A_02 -->|south| A_12
        A_12 -->|west| A_11
        A_12 -->|east| A_13
        A_13 -->|east| A_14
        A_14 -->|north| A_04
        A_14 -->|south| A_24
        A_04 -->|west| A_03
    end

    subgraph sectionE["Section E — Transition (area e)"]
        E_00["0,0 TRANSITION\ns03e_ia1\n1 Stagg, 1 Reyhound, 1 Usanny\n---\nMessage: ...surrounded...\ncamp is holding...\nwon't last much longer...\n---\nArea warp north"]
    end

    subgraph sectionB["Section B — Deep Snowfield (area b)"]
        B_02["0,2 START\ns03b_sa1"]
        B_12["1,2\ns03b_lb3\n2 Stagg, 1 Usanny"]
        B_11["1,1 BRANCH\ns03b_tb3\n2 Reyhound, 1 Usanny\n---\nLog: Lost more supplies\nto creature ambush"]
        B_21["2,1 KEY + branch\ns03b_ga1\n1 Reyhound, 1 Stagg + box"]
        B_10["1,0 GATE\ns03b_lc2\n1 Stagg, 1 Reyhound,\n1 Usanny\n+ 2 Reyhound (w2)"]
        B_20["2,0\ns03b_ib2\n1 Reyhound, 2 Usanny\n3 boxes"]
        B_30["3,0 BRANCH\ns03b_tb3\n1 Reyhound, 1 Stagg,\n1 Usanny\n+ 1 Usanny, 1 Stagg (w2)"]
        B_31["3,1 branch\ns03b_ga1\n1 Usanny, 1 Reyhound\n+ rare box"]
        B_40["4,0\ns03b_lc2\n1 Reyhound, 1 Stagg,\n1 Hildeghana\n---\nLog: Don't know how much\nlonger we can hold out"]
        B_41["4,1 END — Camp\ns03b_lb1\nCampfire prop\n3 Reyhound + 1 Hildeghana (w2)\n---\nDr. Carlo: Over here!\n---\nROOM CLEAR:\nDr. Carlo rescue dialog\n-> complete_quest + telepipe"]

        B_02 -->|south| B_12
        B_12 -->|west| B_11
        B_11 -->|south| B_21
        B_11 -->|west| B_10
        B_10 -->|south| B_20
        B_20 -->|south| B_30
        B_30 -->|east| B_31
        B_30 -->|south| B_40
        B_40 -->|east| B_41
    end

    office --> sectionA
    A_03 -->|area warp| sectionE
    E_00 -->|area warp| sectionB
```

## All Dialog (in play order)

### Section A — Expedition Logs (missable, interact to read)

| Cell | Text |
|------|------|
| 1,4 | Expedition Log: We're finding it hard to avoid encounters. Provisions are starting to run low. |
| 1,4 | Expedition Log: Visibility dropping fast. Going to push deeper despite the conditions. |

### Section E — Transition

| Cell | Type | Text |
|------|------|------|
| 0,0 | Message | ...surrounded... camp is holding... won't last much longer... |

### Section B — Expedition Logs (missable, interact to read)

| Cell | Text |
|------|------|
| 1,1 | Expedition Log: We lost more supplies to another creature ambush. The wildlife here is more aggressive than anything in the survey data. |
| 4,0 | Expedition Log: I don't know how much longer we can hold out. Almost everything is gone now. |

### Section B — Camp Rescue (cell 4,1)

| Type | Speaker | Dialog |
|------|---------|--------|
| Dialog (enter) | Dr. Carlo | Over here! They've surrounded the camp! |
| Dialog (room clear) | Dr. Carlo | Thank you. The creatures came out of nowhere, we lost contact trying to call for help. |
| Dialog (room clear) | Dr. Carlo | We owe you one. I'll make sure the Principal hears about this. |
| *action* | -- | complete_quest + telepipe |

## Enemy Roster

| Enemy | Display Name | Count | Notes |
|-------|-------------|-------|-------|
| reyhound | Reyhound | ~25 | Wolf, most common. All sections. |
| usanny | Usanny | ~14 | Rabbit, secondary. All sections. |
| stagg | Stagg | ~12 | Deer, mid-tier. Sections A and B. |
| hildeghana | Hildeghana | 2 | Female gorilla. Section B only (4,0 and 4,1 wave 2). Escalation near camp. |

## Mechanics

- **Key + Gate (Section A):** Cell 1,3 drops a key. Gate at 1,4 south blocks access to branch cell 2,4.
- **Fence + Switch (Section A):** Cell 1,4 has a fence (link "a") cleared by a step switch in the same room.
- **Key + Gate (Section B):** Cell 2,1 drops a key. Gate at 1,0 south blocks deeper progression.
- **Waves:** Several cells have wave 2 enemies that spawn after wave 1 is cleared.
- **Area Warps:** Section A exits north from 0,3. Section E exits north. Section B exits south from 4,1 (telepipe).
- **Story Prop:** Campfire at the expedition camp (cell 4,1).

## Narrative Arc

1. **Briefing:** Lost signal from a research team. Principal sends the player alone with minimal info.
2. **Section A (Outer Snowfield):** Hostile territory. First expedition logs found. Provisions running low, visibility dropping. The team pushed deeper.
3. **Transition:** A desperate radio fragment. The situation is worse than expected.
4. **Section B (Deep Snowfield):** More dire logs. Creatures took their supplies. Hildeghana appear near the camp, escalating the threat.
5. **Camp Rescue:** Dr. Carlo calls for help. Clear all enemies. Brief thanks -- first meeting, not a big moment. He'll matter more later.

## Design Notes

- **Solo mission by design.** No companion. The isolation makes the snowfield feel dangerous and the expedition logs more impactful.
- **Dr. Carlo is discovered, not introduced.** He's not in the briefing. The player meets him for the first time at the camp. Like PSO's "The Fake in Yellow" introducing Jean Carlo Montague offhand. He becomes important in later quests.
- **Expedition logs are missable flavor.** Not required for quest completion. Reward for exploration.
- **Hard mode potential:** Add quest items (recover research equipment/data samples) for a collection objective layer.
