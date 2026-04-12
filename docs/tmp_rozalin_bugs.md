# Rozalin Bug Report — 2026-04-12

## Bug 1: Backtracking warps to wrong section
- **Steps**: Section 2 of Paru Pact, cleared enemies except one, walked back through area warp
- **Expected**: Return to Section 1 
- **Actual**: Warped to Section 3 instead
- **Also**: Going back from Sec3 to Sec2 auto-cleared the remaining enemy
- **Root cause (suspected)**: The `is_entry`/`is_exit` direction logic in area warp creation may be matching the wrong portal direction, sending the player forward instead of backward

## Bug 2: Weapon SFX not playing for some users
- **Steps**: Equip Brand (saber), attack enemies
- **Expected**: Saber swing sound plays
- **Actual**: No sound on controller or keyboard for Rozalin, works for Kion
- **Root cause (suspected)**: `_glob_cache()` uses `DirAccess` which may fail in exported builds or when running from a different working directory. The glob pattern `res://assets/sfx/weapons/saber_swing_*.wav` might return empty on some setups.

## Bug 3: Cancel sound killed by close guard
- **Steps**: Open start menu, navigate to sub-menu, press cancel to go back
- **Expected**: Cancel/back sound plays
- **Actual**: No sound plays when canceling within sub-menus
- **Root cause**: The `if not _is_open` guard added to fix the double-close-sound also blocks cancel sounds when going back between sub-menus (since `_go_back()` is called by the mode handler which sets `handled=true`, but `_is_open` is still true — actually wait, the guard checks `if not _is_open` and returns early. Sub-menus don't close the menu, so `_is_open` stays true. This shouldn't be affected...)
- **Need to verify**: Is the cancel sound actually missing, or is it the specific case of fully closing from MAIN mode?

## Bug 4: Menu sound layering (PSO reference)
- **PSO behavior (Rozalin's observations)**:
  - Navigating within same menu level: only cursor move sound
  - Accept into new visual menu: accept + open menu sound
  - Cancel back one level (same visual): only cancel sound  
  - Cancel back with visual change: cancel + open menu sound
- **Current behavior**: Generic SFX handler plays one sound per action regardless of context
- **Priority**: Low — polish, not a regression

## Action Items
1. **Bug 1**: Investigate area warp direction logic for backward warps in multi-section quests
2. **Bug 2**: Add fallback for weapon SFX when glob fails, add debug logging
3. **Bug 3**: Verify the cancel sound guard logic — test on this branch
4. **Bug 4**: Defer to future polish pass
