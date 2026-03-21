# Scene Flow

Every scene transition in the game, what triggers it, and how SceneManager handles it.

## Transition Methods

SceneManager provides three transition types:

| Method | Behavior | Use Case |
|--------|----------|----------|
| `goto_scene(path, data)` | Replace current scene, clear all overlays, fade transition | Major navigation (city → field) |
| `push_scene(path, data)` | Overlay on top, dim background, preserve base scene | Menus, shops, dialogs |
| `pop_scene(data)` | Dismiss top overlay, re-enable previous scene | Close menu/shop |

## Main Game Flow

```mermaid
graph TD
    Title["Title Screen\ntitle.tscn"]
    CharSelect["Character Select\ncharacter_select.tscn"]
    CharCreate["Character Create\ncharacter_create.tscn"]
    CityOffice["City Office\ncity_office.tscn"]
    CityCounter["City Counter\ncity_counter.tscn"]
    CityMarket["City Market\ncity_market.tscn"]
    CityWarp["City Warp\ncity_warp.tscn"]
    CityUnderground["Underground\ncity_underground.tscn"]
    ValleyField["Valley Field (3D)\nvalley_field.tscn"]

    Title -->|"goto: ui_accept"| CharSelect
    CharSelect -->|"goto: ui_cancel"| Title
    CharSelect -->|"goto: select existing"| CityOffice
    CharSelect -->|"goto: select empty slot"| CharCreate
    CharCreate -->|"goto: ui_cancel"| CharSelect
    CharCreate -->|"goto: confirm"| CityOffice

    CityOffice -->|"goto: exit door"| CityCounter
    CityCounter -->|"goto: area trigger"| CityMarket
    CityCounter -->|"goto: area trigger"| CityWarp
    CityMarket -->|"goto: area trigger"| CityCounter
    CityMarket -->|"goto: area trigger"| CityWarp
    CityWarp -->|"goto: area trigger"| CityMarket
    CityWarp -->|"goto: area trigger"| CityCounter
    CityWarp -->|"goto: area trigger"| CityUnderground
    CityUnderground -->|"goto: area trigger"| CityWarp

    CityWarp -->|"goto: warp pad"| ValleyField
    ValleyField -->|"goto: quest complete / telepipe"| CityWarp
    ValleyField -->|"goto: advance section"| ValleyField
```

## City Hub Navigation

All city areas extend `city_area_base.gd` and transition between each other via area triggers at zone boundaries.

```mermaid
graph LR
    CityOffice["Office"] -->|goto| CityCounter["Counter"]
    CityCounter <-->|goto| CityMarket["Market"]
    CityCounter <-->|goto| CityWarp["Warp"]
    CityMarket <-->|goto| CityWarp
    CityWarp <-->|goto| Underground["Underground"]
```

## Overlay Stack (push/pop)

These scenes are pushed as overlays and popped with ESC / ui_cancel.

```mermaid
graph TD
    subgraph "Base Scene (any 3D city area or field)"
        Base["3D City / Field"]
    end

    subgraph "Menu Overlays (push_scene)"
        CityMenu["City Menu\ncity_menu.tscn"]
        PauseMenu["Field Pause Menu\nfield_pause_menu.tscn"]
        GuildCounter["Guild Counter\nguild_counter.tscn"]
        WarpTele["Warp Teleporter\nwarp_teleporter.tscn"]
        ServicesMenu["Services Menu\nservices_menu.tscn"]
    end

    subgraph "Sub-Overlays (push from menu)"
        Inventory["Inventory\ninventory_screen.tscn"]
        Equipment["Equipment\nequipment_screen.tscn"]
        Status["Status\nstatus.tscn"]
        APScreen["Action Palette\naction_palette.tscn"]
        Storage["Storage\nstorage.tscn"]
    end

    subgraph "Shop Overlays (push from NPC interaction)"
        ItemShop["Item Shop"]
        WeaponShop["Weapon Shop"]
        TechShop["Tech Shop"]
        Tekker["Tekker"]
    end

    Base -->|"ESC in city"| CityMenu
    Base -->|"ESC in field"| PauseMenu
    Base -->|"NPC interact"| GuildCounter
    Base -->|"Warp pad"| WarpTele
    Base -->|"NPC interact"| ServicesMenu

    CityMenu -->|push| Inventory
    CityMenu -->|push| Equipment
    CityMenu -->|push| Status
    CityMenu -->|push| APScreen

    PauseMenu -->|push| Inventory
    PauseMenu -->|push| Equipment
    PauseMenu -->|push| Status
    PauseMenu -->|push| APScreen

    ServicesMenu -->|push| Storage
    ServicesMenu -->|push| ItemShop
    ServicesMenu -->|push| WeaponShop
    ServicesMenu -->|push| TechShop
    ServicesMenu -->|push| Tekker
```

## Quest Flow State Machine

```mermaid
stateDiagram-v2
    [*] --> CityIdle: Game start / return

    CityIdle --> GuildCounter: NPC interact / Principal
    GuildCounter --> QuestAccepted: Accept quest
    GuildCounter --> CityIdle: Cancel / ESC

    QuestAccepted --> CityOffice: Enter office
    CityOffice --> QuestBriefing: Has accepted quest
    QuestBriefing --> CityIdle: Briefing complete

    CityIdle --> WarpTeleporter: Step on warp pad
    WarpTeleporter --> FieldActive: Select area + difficulty
    WarpTeleporter --> CityIdle: ESC / cancel

    FieldActive --> FieldActive: Room clear → next room
    FieldActive --> SectionAdvance: Reach end cell
    SectionAdvance --> FieldActive: Next section starts
    SectionAdvance --> QuestComplete: All sections done

    FieldActive --> Suspended: Pause → Return to Title
    Suspended --> FieldActive: Resume from warp pad

    QuestComplete --> CityWarp: Telepipe exit
    CityWarp --> CityOffice: Walk to office
    CityOffice --> ReportQuest: Talk to Principal
    ReportQuest --> CityIdle: Rewards granted
```

## Field Progression Detail

```mermaid
graph TD
    Enter["Enter Field\n(from warp pad)"] --> LoadGrid["Load grid from\nquest JSON sections"]
    LoadGrid --> SpawnPlayer["Spawn at\ndefault/portal position"]
    SpawnPlayer --> RoomLoop

    subgraph RoomLoop["Room Loop"]
        Idle["Player explores room"]
        Idle -->|"enemies present"| GatesLock["Gates lock"]
        GatesLock --> Combat["Fight enemies"]
        Combat -->|"wave cleared"| NextWave{"More waves?"}
        NextWave -->|yes| Combat
        NextWave -->|no| GatesUnlock["Gates unlock"]
        GatesUnlock --> Idle
        Idle -->|"enter gate/warp"| NextRoom["Load adjacent cell"]
        NextRoom --> Idle
    end

    RoomLoop -->|"reach section end"| SectionCheck{"More sections?"}
    SectionCheck -->|yes| ReloadField["goto_scene: valley_field\n(next section data)"]
    ReloadField --> LoadGrid
    SectionCheck -->|no| Complete["Quest complete\nSpawn telepipe"]
    Complete -->|"goto_scene"| CityWarp["city_warp.tscn"]
```

## Data Passed Between Scenes

SceneManager stores transition data accessible via `get_transition_data()`.

| Transition | Data Keys | Purpose |
|------------|-----------|---------|
| → valley_field | `current_cell_pos`, `spawn_edge`, `keys_collected` | Resume position in grid |
| → city_office | `spawn_key` ("intro" for first visit) | Trigger intro cutscene |
| → guild_counter | `npc_model_path`, `npc_display_name` | Show NPC in counter scene |
| → city areas | `spawn_key` | Player spawn position |
| ← guild_counter (pop) | `quest_accepted: true` | Notify city that quest was accepted |

## Behavioral Contracts

### Contract 1: All scene transitions go through SceneManager
- No direct calls to `get_tree().change_scene_to_file()`
- SceneManager handles fade transitions, overlay stacking, and data passing
- Breaking this contract causes missing transitions or stale overlays

### Contract 2: Overlay stack is LIFO
- `push_scene` adds to top of stack
- `pop_scene` removes from top only
- `goto_scene` clears the entire stack
- Menus MUST pop themselves before pushing sub-menus (or the stack grows unbounded)

### Contract 3: City areas preserve player state
- When transitioning between city areas, `CityState` MUST save player position/rotation
- Returning to a city area MUST restore the player near the exit they left from
- `spawn_key` in transition data overrides this (e.g., "intro" spawn)

### Contract 4: Field sections chain correctly
- Advancing a section calls `goto_scene` with the SAME valley_field scene but new section data
- `keys_collected` MUST carry forward across sections (keys persist within a quest run)
- `current_cell_pos` MUST be set to the new section's start position

### Contract 5: Quest state gates transitions
- Warp pad MUST check `SessionManager.has_accepted_quest()` before allowing field entry
- Guild counter MUST check quest status to show correct options (accept/cancel/report)
- Office briefing MUST only trigger when `has_accepted_quest()` is true
