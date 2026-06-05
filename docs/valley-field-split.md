# Refactor tracker — splitting `valley_field_controller.gd`

Breaking up the field-controller god-file (~3,900 lines) into focused modules,
**one extraction per PR**, each gated on a green regression matrix. Part of the
pre-beta refactor milestone (issue #215).

## Per-increment workflow (the loop)

1. **Refactor** — extract one module on a fresh branch off `main`.
2. **Validate** — `godot --headless --editor --quit` (reimport gate) +
   `test_runner.tscn` (unit suite) + `run_regression_matrix.sh` (full spine).
   Red → fix before proceeding.
3. **PR** — bump version (3 sources), push, `gh pr create`.
4. **Review** — wait for Copilot + CI green; address comments.
5. **Merge** — after Copilot signs off (user-authorized for this effort).
6. **Next** — branch the next increment off the freshly-merged `main`.

## Increments

- [x] **0. Prereq: PR #255** (Tier 1 dead-code sweep + endgame matrix) — **MERGED**.
- [x] **0b. PR #257** — autoplay `dbus-run-session` wrapper (unblocked the matrix
      from a Godot AccessKit/DBus SIGABRT) — **MERGED**.
- [x] **1. `StageRotation`** — extracted pure rotation helpers (`rotate_dir`,
      `dir_to_yaw`) to `scripts/3d/field/stage_rotation.gd`; deduped the copy in
      `room_minimap.gd`; dropped dead `_grid_to_original_dir` + `_rotate_point`.
      *Reimport clean; tests assertion-neutral; full matrix 15/15 green on the
      dbus-fixed main. PR #256 — merging.*
- [ ] **2. `CellObjectSpawner`** — the `_spawn_box / _spawn_enemy / _spawn_fence
      / _spawn_switch / _spawn_message / _spawn_wall / _spawn_npc / _spawn_trap…`
      wall. The big coupled one (needs a back-reference to the controller).
- [ ] **3. `MapCollisionBuilder`** — `_setup_map_collision`,
      `_filter_floor_collision`, `_collect_collision_faces`,
      `_create_collision_from_meshes`, `_configure_collision_nodes`.
- [ ] **4. `PortalGateManager`** — `_parse_baked_portals`,
      `_compute_portal_from_config`, `_build_portal_data_from_config`, gate
      triggers + labels + material fixups.
- [ ] **5. `CellStateManager`** — `_save_cell_state`, `_restore_cell_objects`,
      `_spawn_cell_objects`, `_spawn_fresh_cell_objects`.
- [ ] **6. `WeatherController`** — `_spawn_weather`, `_kick_weather`,
      `_spawn_stage_effects`.

## Status log

- 2026-06-04 — Tracker created. PR #255 up (needs 0.32.2 re-bump). Increment 1
  code-complete, matrix validating. Branch strategy: land #255 → rebase
  increment 1 onto main → continue.
- 2026-06-05 — #255 merged. Hit a Godot AccessKit/DBus SIGABRT that broke the
  matrix on any windowed launch → fixed with a `dbus-run-session` wrapper
  (#257, merged). Rebased increment 1 onto the fixed main; full matrix 15/15
  green. PR #256 merging. Next: increment 2 (`CellObjectSpawner`).

## Notes / gotchas

- Stage rotation is a **label swap** — never apply a rotation matrix to floor
  geometry/waypoints/objectives.
- The autopilot harness needs a session DBus bus — launches are wrapped in
  `dbus-run-session` (optional, warns if absent) to avoid an AccessKit crash.
- The merge-gate hook requires a fresh `.sanity-pass` for the **exact** commit
  being merged — addressing review comments means re-running `npm run sanity-check`.
- Version bump is **three sources** (VERSION, project.godot `config/version`,
  export_presets.cfg `version/name`) and only at PR-open.
- `main` is protected — PR + Copilot review required; merging triggers release CD.
