---
name: nudge
description: Apply gate nudge positions from [GateNudge] log output to unified-stage-configs.json
user_invocable: true
---

# /nudge — Apply Gate Position Nudges

The user will paste one or more `[GateNudge]` log lines from the Godot console. Each line has this format:

```
[GateNudge] dir=south cell=1,1 stage=s03a_nc2 portal=portal_1770724448196_4mfd4mgom → gate_pos=[-15.37, 0.00, 19.13]
```

## Steps

1. Parse each line to extract: `stage` (stage_id), `portal` (portal_id), and `gate_pos` ([x, y, z]).
2. Open `data/stage_configs/unified-stage-configs.json`.
3. Find the stage config by stage_id, then find the portal entry matching the portal_id.
4. Update the portal's `"position"` array to the new gate_pos values.
5. Save the file.
6. `git add data/stage_configs/unified-stage-configs.json` and commit with message: `Nudge gate positions: <list of stage_ids>`
7. `git push`

## Important

- Match portals by **portal ID**, not by direction name (direction in the log is the game direction after rotation, not the config direction).
- Multiple nudge lines can be applied in one invocation.
- Round position values to 2 decimal places.
