# Input System

How the player's control scheme selection flows through the game.

## Control Scheme Selection

The player selects a control scheme on the **title screen**. This choice persists to `user://input_config.json` and MUST propagate to every screen that displays button prompts.

```mermaid
graph TD
    subgraph "Title Screen (title.gd)"
        TS_Left["ui_left / ui_right"] -->|"InputConfig.cycle()"| IC
    end

    IC["InputConfig (autoload)"]
    IC -->|"persists"| File["user://input_config.json"]
    IC -->|"loads on _ready()"| File

    IC -->|"scheme_changed signal"| TS_Display["Title: _update_scheme_display()"]
    TS_Display -->|"updates icon from SCHEME_ICONS"| TS_Icon["Controller icon preview"]

    subgraph "Kenney Assets"
        KB["Keyboard icon"]
        KBM["KB + Mouse icon"]
        Xbox["Xbox controller icon"]
        Switch["Switch controller icon"]
    end
```

## Current Consumers

```mermaid
graph LR
    IC["InputConfig"]

    IC -->|"scheme_changed signal"| Title["title.gd"]
    IC -.->|"NOT connected"| HUD["hud.gd"]
    IC -.->|"NOT connected"| APS["action_palette_screen.gd"]
    IC -.->|"NOT connected"| Field["field_hud.gd"]
    IC -.->|"NOT connected"| Dialog["dialog_box.gd"]

    style HUD stroke:#f55,stroke-dasharray: 5 5
    style APS stroke:#f55,stroke-dasharray: 5 5
    style Field stroke:#f55,stroke-dasharray: 5 5
    style Dialog stroke:#f55,stroke-dasharray: 5 5
```

> Red dashed = **should** consume InputConfig but currently does not.

## Scheme Constants

| Scheme ID   | Label         | Button Layout | Icon Source                     |
|-------------|---------------|---------------|---------------------------------|
| `keyboard`  | Keyboard      | N/A           | `kenney_input-prompts/Keyboard` |
| `kb_mouse`  | KB + Mouse    | N/A           | `kenney_input-prompts/Mouse`    |
| `xinput`    | Xbox / XInput | Standard ABXY | `kenney_input-prompts/Xbox`     |
| `switch`    | Switch        | Swapped A/B, X/Y | `kenney_input-prompts/Switch` |

## Switch Button Remapping

When `InputConfig.current_scheme == "switch"`, `_apply_button_mapping()` swaps joypad face buttons so physical labels match on-screen prompts:

```mermaid
graph LR
    subgraph "Xbox Layout (default)"
        A0["JOY_BUTTON_0 = A (confirm)"]
        B1["JOY_BUTTON_1 = B (cancel)"]
        X2["JOY_BUTTON_2 = X"]
        Y3["JOY_BUTTON_3 = Y"]
    end

    subgraph "Switch Layout (remapped)"
        S1["JOY_BUTTON_1 = A (confirm)"]
        S0["JOY_BUTTON_0 = B (cancel)"]
        S3["JOY_BUTTON_3 = X"]
        S2["JOY_BUTTON_2 = Y"]
    end

    A0 -->|swap| S1
    B1 -->|swap| S0
    X2 -->|swap| S3
    Y3 -->|swap| S2
```

## Behavioral Contracts

These are the expected behaviors. If any of these break, something regressed.

### Contract 1: Scheme persists across sessions
- `InputConfig._ready()` MUST load from `user://input_config.json`
- `InputConfig.cycle()` MUST save to `user://input_config.json`
- A player who selects Xbox on the title screen MUST see Xbox selected on next launch

### Contract 2: All button prompt UIs reflect current scheme
- **Title screen**: MUST show correct controller icon for selected scheme
- **HUD interaction prompts**: SHOULD show scheme-appropriate button label (e.g., "E" vs "A" vs "B")
- **Action palette**: SHOULD show scheme-appropriate face button icons on each slot
- **Dialog boxes**: SHOULD show scheme-appropriate "advance" prompt

### Contract 3: Switch remapping applies to gameplay
- When scheme is `switch`, `_apply_button_mapping()` MUST be called
- Confirm action MUST map to physical A button (JOY_BUTTON_1 on Switch)
- Cancel action MUST map to physical B button (JOY_BUTTON_0 on Switch)

### Contract 4: Scheme change propagates at runtime
- Changing scheme MUST emit `scheme_changed` signal
- ALL connected listeners MUST update their displays immediately
- No scene reload should be required

## Gap Analysis

Current gaps where InputConfig is NOT consumed but SHOULD be:

| System | File | Issue |
|--------|------|-------|
| HUD interaction prompt | `scripts/3d/ui/hud.gd` | Shows generic "interact" text, not scheme-specific button icon |
| Action palette screen | `scripts/2d/action_palette_screen.gd` | Uses hardcoded "A/B" hint text regardless of scheme |
| Field HUD | `scripts/3d/field/field_hud.gd` | Action diamond shows slot names but not button icons |
| Dialog box | `scripts/3d/ui/dialog_box.gd` | "Advance" prompt not scheme-aware |
