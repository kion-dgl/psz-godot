# System Dependencies

Maps every autoload-to-autoload dependency and groups non-autoload consumers by subsystem.

## Autoload Dependency Graph

```mermaid
graph TD
    subgraph "Registries (pure data, no dependencies)"
        ItemReg["ItemRegistry"]
        WeaponReg["WeaponRegistry"]
        ArmorReg["ArmorRegistry"]
        EnemyReg["EnemyRegistry"]
        ClassReg["ClassRegistry"]
        ConsumableReg["ConsumableRegistry"]
        ShopReg["ShopRegistry"]
        UnitReg["UnitRegistry"]
        PhotonArtReg["PhotonArtRegistry"]
        MissionReg["MissionRegistry"]
        DropReg["DropRegistry"]
        MaterialReg["MaterialRegistry"]
        ModifierReg["ModifierRegistry"]
        SetBonusReg["SetBonusRegistry"]
    end

    subgraph "Standalone (no autoload dependencies)"
        SceneManager
        EnemySpawner
        CityState
        PlayerConfig
        TimeManager
        QuestLoader
        ActionPalette
        InputConfig
        MagManager
    end

    subgraph "Composite (depend on other autoloads)"
        GameState
        Inventory
        CharacterManager
        SaveManager
        CombatManager
        ShopManager
        SessionManager
        TechniqueManager
    end

    %% Inventory dependencies
    Inventory --> ItemReg
    Inventory --> WeaponReg
    Inventory --> ArmorReg
    Inventory --> UnitReg
    Inventory --> ConsumableReg
    Inventory --> MaterialReg
    Inventory --> ModifierReg
    Inventory --> TechniqueManager
    Inventory --> GameState

    %% CharacterManager dependencies
    CharacterManager --> ClassReg
    CharacterManager --> Inventory
    CharacterManager --> GameState
    CharacterManager --> ActionPalette

    %% SaveManager dependencies
    SaveManager --> CharacterManager
    SaveManager --> GameState

    %% CombatManager dependencies
    CombatManager --> CharacterManager
    CombatManager --> ClassReg
    CombatManager --> WeaponReg
    CombatManager --> ArmorReg
    CombatManager --> SetBonusReg
    CombatManager --> TechniqueManager
    CombatManager --> PhotonArtReg
    CombatManager --> DropReg
    CombatManager --> Inventory

    %% ShopManager dependencies
    ShopManager --> ShopReg
    ShopManager --> CharacterManager
    ShopManager --> Inventory
    ShopManager --> GameState
    ShopManager --> WeaponReg

    %% SessionManager dependencies
    SessionManager --> QuestLoader
    SessionManager --> MissionReg

    %% TechniqueManager dependencies
    TechniqueManager --> ClassReg
```

## Dependency Depth

How deep in the dependency chain each autoload sits. Higher depth = more transitive risk.

| Depth | Autoloads |
|-------|-----------|
| 0 (leaf) | All Registries, SceneManager, EnemySpawner, CityState, PlayerConfig, TimeManager, QuestLoader, ActionPalette, InputConfig, MagManager, GameState |
| 1 | TechniqueManager, SessionManager |
| 2 | Inventory (→ registries + GameState + TechniqueManager) |
| 3 | CharacterManager (→ Inventory → ...) |
| 4 | SaveManager, CombatManager, ShopManager (→ CharacterManager → ...) |

## Non-Autoload Consumers by Subsystem

### City Subsystem (scripts/3d/city/)

```mermaid
graph LR
    subgraph "City Scripts"
        CityBase["city_area_base.gd"]
        CityOffice["city_office_controller.gd"]
        CityCounter["city_counter_controller.gd"]
        CityMenu["city_menu.gd"]
        WarpPad["warp_pad.gd"]
    end

    CityBase --> SceneManager
    CityBase --> CityState
    CityBase --> CharacterManager
    CityBase --> TimeManager

    CityOffice --> SessionManager
    CityOffice --> CityState
    CityOffice --> CharacterManager
    CityOffice --> QuestLoader
    CityOffice --> SceneManager

    CityCounter --> SceneManager
    CityCounter --> SessionManager

    CityMenu --> SceneManager
    CityMenu --> SaveManager
    CityMenu --> SessionManager

    WarpPad --> SessionManager
    WarpPad --> SceneManager
```

### Field Subsystem (scripts/3d/field/)

```mermaid
graph LR
    subgraph "Field Scripts"
        VFC["valley_field_controller.gd"]
        FieldHUD["field_hud.gd"]
        PauseMenu["field_pause_menu.gd"]
    end

    VFC --> SessionManager
    VFC --> CombatManager
    VFC --> EnemySpawner
    VFC --> TimeManager
    VFC --> CharacterManager
    VFC --> GameState
    VFC --> Inventory
    VFC --> SceneManager

    FieldHUD --> GameState
    FieldHUD --> CharacterManager
    FieldHUD --> SessionManager
    FieldHUD --> ActionPalette

    PauseMenu --> SceneManager
    PauseMenu --> SessionManager
    PauseMenu --> GameState
    PauseMenu --> SaveManager
    PauseMenu --> CityState
    PauseMenu --> ActionPalette
```

### Player (scripts/3d/player/)

```mermaid
graph LR
    Player["player.gd"]

    Player --> CharacterManager
    Player --> GameState
    Player --> CombatManager
    Player --> SessionManager
    Player --> TimeManager
    Player --> EnemySpawner
    Player --> PlayerConfig
```

### 2D Menus (scripts/2d/)

```mermaid
graph LR
    subgraph "Menu Scripts"
        Title["title.gd"]
        CharSelect["character_select.gd"]
        CharCreate["character_create.gd"]
        GuildCounter["guild_counter.gd"]
        WarpTele["warp_teleporter.gd"]
        InvScreen["inventory_screen.gd"]
        EquipScreen["equipment_screen.gd"]
        StatusScreen["status.gd"]
        APScreen["action_palette_screen.gd"]
        StorageScreen["storage.gd"]
    end

    Title --> SceneManager
    Title --> SaveManager
    Title --> InputConfig

    CharSelect --> CharacterManager
    CharSelect --> ClassReg["ClassRegistry"]
    CharSelect --> PlayerConfig
    CharSelect --> SceneManager

    CharCreate --> SceneManager
    CharCreate --> ClassReg
    CharCreate --> PlayerConfig
    CharCreate --> CharacterManager
    CharCreate --> SaveManager
    CharCreate --> CityState

    GuildCounter --> SceneManager
    GuildCounter --> SessionManager
    GuildCounter --> MissionReg["MissionRegistry"]
    GuildCounter --> QuestLoader
    GuildCounter --> GameState
    GuildCounter --> SaveManager

    WarpTele --> SessionManager
    WarpTele --> SceneManager

    InvScreen --> Inventory
    InvScreen --> ItemReg["ItemRegistry"]
    InvScreen --> CombatManager
    InvScreen --> MagManager
    InvScreen --> CharacterManager
    InvScreen --> GameState

    EquipScreen --> CharacterManager
    EquipScreen --> GameState
    EquipScreen --> WeaponReg["WeaponRegistry"]
    EquipScreen --> ArmorReg["ArmorRegistry"]
    EquipScreen --> UnitReg["UnitRegistry"]
    EquipScreen --> Inventory

    StatusScreen --> CharacterManager
    StatusScreen --> GameState
    StatusScreen --> Inventory
    StatusScreen --> MissionReg
    StatusScreen --> MagManager

    APScreen --> ActionPalette

    StorageScreen --> GameState
    StorageScreen --> Inventory
    StorageScreen --> CharacterManager
```

### Shops (scripts/2d/shops/)

```mermaid
graph LR
    subgraph "Shop Scripts"
        ItemShop["item_shop.gd"]
        WeaponShop["weapon_shop.gd"]
        TechShop["tech_shop.gd"]
        Tekker["tekker.gd"]
    end

    ItemShop --> ShopManager
    ItemShop --> Inventory
    ItemShop --> GameState

    WeaponShop --> ShopManager
    WeaponShop --> WeaponReg["WeaponRegistry"]
    WeaponShop --> Inventory
    WeaponShop --> GameState

    TechShop --> TechniqueManager
    TechShop --> Inventory
    TechShop --> GameState

    Tekker --> WeaponReg
    Tekker --> Inventory
    Tekker --> GameState
```

## Coupling Hotspots

Systems with the most incoming dependencies (most coupled, highest regression risk):

| Autoload | Incoming Deps (autoloads) | Incoming Deps (scripts) | Risk |
|----------|--------------------------|------------------------|------|
| GameState | Inventory, CharacterManager, ShopManager, SaveManager | 15+ scripts | HIGH |
| CharacterManager | SaveManager, CombatManager, ShopManager | 10+ scripts | HIGH |
| Inventory | CombatManager, CharacterManager | 12+ scripts | HIGH |
| SceneManager | (none) | 15+ scripts | MEDIUM |
| SessionManager | (none) | 10+ scripts | MEDIUM |
| ClassRegistry | CharacterManager, CombatManager, TechniqueManager | 3 scripts | LOW |

## Behavioral Contracts

### Contract 1: Registries are stateless
- Registry autoloads MUST NOT reference other autoloads
- They load data once in `_ready()` and serve lookups
- Changing a registry MUST NOT have side effects on game state

### Contract 2: SaveManager only talks to CharacterManager + GameState
- Save/load MUST go through CharacterManager (character data) and GameState (shared storage)
- SaveManager MUST NOT directly access Inventory, CombatManager, or any other system
- All saveable state MUST be accessible through these two entry points

### Contract 3: SessionManager is the quest authority
- Only SessionManager tracks quest progress (accepted, suspended, completed)
- QuestLoader reads files but does not track state
- Field controllers read session state but do not write quest progress directly

### Contract 4: CombatManager does not persist
- Combat state lives only during active combat encounters
- CombatManager reads from CharacterManager/Inventory but MUST NOT write back directly
- Rewards (XP, drops, meseta) are applied by the field controller after combat resolution
