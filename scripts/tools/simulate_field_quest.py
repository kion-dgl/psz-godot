#!/usr/bin/env python3
"""Simulate field quests to validate they are completable.

Three layers of testing:
  Layer 1 - Static Analysis: BFS reachability, key ordering, floor checks, room area
  Layer 2 - State Machine Simulation: walk through quest, track keys/enemies/visits
  Layer 3 - Pathfinding: A* within rooms to verify all objects physically reachable

Usage:
  python scripts/tools/simulate_field_quest.py                     # All field quests, all layers
  python scripts/tools/simulate_field_quest.py --quest valley_field_01  # Specific quest
  python scripts/tools/simulate_field_quest.py --layer 1           # Static only
  python scripts/tools/simulate_field_quest.py --layer 2           # Static + simulation
  python scripts/tools/simulate_field_quest.py --layer 3           # All layers
  python scripts/tools/simulate_field_quest.py --dir data/quests   # Custom directory
"""

import argparse
import heapq
import json
import os
import struct
import sys
from collections import deque
from typing import Optional
from quest_geom import point_in_triangle

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, '..', '..')
FIELD_QUEST_DIR = os.path.join(PROJECT_ROOT, 'data', 'field_quests')
STAGE_CONFIG_PATH = os.path.join(PROJECT_ROOT, 'data', 'stage_configs', 'unified-stage-configs.json')
STAGES_DIR = os.path.join(PROJECT_ROOT, 'assets', 'stages')

OPPOSITE_DIR = {
    'north': 'south',
    'south': 'north',
    'east': 'west',
    'west': 'east',
}

ROTATION_MAPS = {
    0: {'north': 'north', 'south': 'south', 'east': 'east', 'west': 'west'},
    90: {'north': 'east', 'east': 'south', 'south': 'west', 'west': 'north'},
    180: {'north': 'south', 'south': 'north', 'east': 'west', 'west': 'east'},
    270: {'north': 'west', 'west': 'south', 'south': 'east', 'east': 'north'},
}

MIN_FLOOR_AREA_WITH_ENEMIES = 50.0  # sq units

# Spatial object types that should be on walkable floor
FLOOR_OBJECT_TYPES = {'enemy', 'box', 'rare_box', 'key'}


# ---------------------------------------------------------------------------
# Floor GLB parsing
# ---------------------------------------------------------------------------

def _build_floor_glb_index() -> dict[str, str]:
    """Scan assets/stages/ to build a mapping of stage_id -> floor GLB path."""
    index = {}
    for dirpath, dirnames, filenames in os.walk(STAGES_DIR):
        for fname in filenames:
            if fname.endswith('-floor.glb'):
                stage_id = fname.replace('-floor.glb', '')
                index[stage_id] = os.path.join(dirpath, fname)
    return index


_floor_glb_index: Optional[dict[str, str]] = None


def get_floor_glb_path(stage_id: str) -> Optional[str]:
    """Get the floor GLB path for a stage_id."""
    global _floor_glb_index
    if _floor_glb_index is None:
        _floor_glb_index = _build_floor_glb_index()
    return _floor_glb_index.get(stage_id)


def load_floor_triangles(glb_path: str) -> list[tuple]:
    """Extract floor triangles as list of [(x1,z1), (x2,z2), (x3,z3)].

    Uses only the XZ plane (Y is up in Godot).
    """
    with open(glb_path, 'rb') as f:
        magic, version, length = struct.unpack('<III', f.read(12))
        chunk_len, chunk_type = struct.unpack('<II', f.read(8))
        json_data = json.loads(f.read(chunk_len))
        # Handle padding to 4-byte boundary
        padding = (4 - chunk_len % 4) % 4
        f.read(padding)
        chunk_len2, chunk_type2 = struct.unpack('<II', f.read(8))
        bin_data = f.read(chunk_len2)

    accessors = json_data.get('accessors', [])
    buffer_views = json_data.get('bufferViews', [])
    triangles = []

    for mesh in json_data.get('meshes', []):
        for prim in mesh.get('primitives', []):
            pos_idx = prim.get('attributes', {}).get('POSITION')
            idx_idx = prim.get('indices')
            if pos_idx is None:
                continue

            acc = accessors[pos_idx]
            bv = buffer_views[acc['bufferView']]
            offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            stride = bv.get('byteStride', 12)
            verts = []
            for i in range(acc['count']):
                x, y, z = struct.unpack_from('<fff', bin_data, offset + i * stride)
                verts.append((x, z))

            if idx_idx is not None:
                iacc = accessors[idx_idx]
                ibv = buffer_views[iacc['bufferView']]
                ioff = ibv.get('byteOffset', 0) + iacc.get('byteOffset', 0)
                if iacc['componentType'] == 5123:  # UNSIGNED_SHORT
                    indices = [struct.unpack_from('<H', bin_data, ioff + i * 2)[0]
                               for i in range(iacc['count'])]
                elif iacc['componentType'] == 5125:  # UNSIGNED_INT
                    indices = [struct.unpack_from('<I', bin_data, ioff + i * 4)[0]
                               for i in range(iacc['count'])]
                else:  # UNSIGNED_BYTE
                    indices = [struct.unpack_from('<B', bin_data, ioff + i)[0]
                               for i in range(iacc['count'])]
                for i in range(0, len(indices), 3):
                    triangles.append((verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]]))
            else:
                for i in range(0, len(verts), 3):
                    triangles.append((verts[i], verts[i + 1], verts[i + 2]))

    return triangles


def filter_floor_triangles(
    all_triangles: list[tuple],
    floor_collision: dict,
) -> list[tuple]:
    """Apply floorCollision config to filter triangles.

    Default: all triangles are walkable floor.
    tri_N: false -> exclude triangle N
    tri_N: true  -> force include triangle N (no-op since default is include)
    """
    tri_overrides = floor_collision.get('triangles', {})
    filtered = []
    for i, tri in enumerate(all_triangles):
        key = f'tri_{i}'
        override = tri_overrides.get(key)
        if override is False:
            continue  # Excluded
        filtered.append(tri)
    return filtered


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------



def _point_to_triangle_dist_sq(px: float, pz: float, t: tuple) -> float:
    """Compute squared distance from point to nearest point on triangle (2D).

    Uses projection onto edges and clamping.
    """
    (x1, z1), (x2, z2), (x3, z3) = t
    # If inside, distance is 0
    if point_in_triangle(px, pz, t):
        return 0.0
    # Check distance to each edge
    edges = [((x1, z1), (x2, z2)), ((x2, z2), (x3, z3)), ((x3, z3), (x1, z1))]
    min_d2 = float('inf')
    for (ax, az), (bx, bz) in edges:
        dx, dz = bx - ax, bz - az
        len_sq = dx * dx + dz * dz
        if len_sq < 1e-10:
            d2 = (px - ax) ** 2 + (pz - az) ** 2
        else:
            t_param = max(0, min(1, ((px - ax) * dx + (pz - az) * dz) / len_sq))
            proj_x = ax + t_param * dx
            proj_z = az + t_param * dz
            d2 = (px - proj_x) ** 2 + (pz - proj_z) ** 2
        if d2 < min_d2:
            min_d2 = d2
    return min_d2


# Tolerance for floor checks: objects within this distance of a floor
# triangle are considered "on floor" (game uses 3D collision which is
# more forgiving than exact 2D point-in-triangle).
FLOOR_TOLERANCE = 3.5


def is_on_floor(x: float, z: float, triangles: list[tuple]) -> bool:
    """Check if a point is on (or near) any floor triangle."""
    tol_sq = FLOOR_TOLERANCE * FLOOR_TOLERANCE
    for t in triangles:
        if _point_to_triangle_dist_sq(x, z, t) <= tol_sq:
            return True
    return False


def triangle_area_2d(t: tuple) -> float:
    """Compute area of a 2D triangle using the shoelace formula."""
    (x1, z1), (x2, z2), (x3, z3) = t
    return abs((x1 * (z2 - z3) + x2 * (z3 - z1) + x3 * (z1 - z2)) / 2.0)


def total_floor_area(triangles: list[tuple]) -> float:
    """Compute total floor area from filtered triangles."""
    return sum(triangle_area_2d(t) for t in triangles)


# ---------------------------------------------------------------------------
# Nav grid and A* pathfinding (Layer 3)
# ---------------------------------------------------------------------------

def build_nav_grid(
    triangles: list[tuple],
    obstacles: list[dict],
    resolution: float = 1.0,
) -> tuple[list[list[bool]], float, float, float]:
    """Build a 2D boolean grid where True = walkable.

    Returns (grid, min_x, min_z, resolution).
    """
    if not triangles:
        return [], 0.0, 0.0, resolution

    all_x = [p[0] for t in triangles for p in t]
    all_z = [p[1] for t in triangles for p in t]
    min_x, max_x = min(all_x) - 1, max(all_x) + 1
    min_z, max_z = min(all_z) - 1, max(all_z) + 1

    cols = int((max_x - min_x) / resolution) + 1
    rows = int((max_z - min_z) / resolution) + 1
    grid = [[False] * cols for _ in range(rows)]

    # Precompute obstacle info for faster checking
    obs_list = []
    for obs in obstacles:
        pos = obs.get('position', [0, 0, 0])
        ox, oz = pos[0], pos[2]
        if obs.get('type') == 'box':
            w = obs.get('width', 2.0)
            d = obs.get('depth', 2.0)
            radius = max(w, d) / 2.0
        else:
            radius = obs.get('radius', 1.5)
        obs_list.append((ox, oz, radius))

    for r in range(rows):
        for c in range(cols):
            wx = min_x + c * resolution
            wz = min_z + r * resolution
            if is_on_floor(wx, wz, triangles):
                blocked = False
                for ox, oz, radius in obs_list:
                    if (wx - ox) ** 2 + (wz - oz) ** 2 < (radius + 0.5) ** 2:
                        blocked = True
                        break
                if not blocked:
                    grid[r][c] = True

    return grid, min_x, min_z, resolution


def world_to_grid(
    wx: float,
    wz: float,
    min_x: float,
    min_z: float,
    resolution: float,
) -> tuple[int, int]:
    """Convert world coordinates to grid row, col."""
    c = int((wx - min_x) / resolution)
    r = int((wz - min_z) / resolution)
    return r, c


def astar(
    grid: list[list[bool]],
    start_rc: tuple[int, int],
    end_rc: tuple[int, int],
) -> int:
    """A* pathfinding on 2D grid. Returns path length or -1 if unreachable."""
    if not grid:
        return -1

    rows = len(grid)
    cols = len(grid[0]) if rows > 0 else 0

    sr, sc = start_rc
    er, ec = end_rc

    # Clamp to grid bounds
    sr = max(0, min(sr, rows - 1))
    sc = max(0, min(sc, cols - 1))
    er = max(0, min(er, rows - 1))
    ec = max(0, min(ec, cols - 1))

    if not grid[sr][sc] or not grid[er][ec]:
        return -1

    if (sr, sc) == (er, ec):
        return 0

    open_set = [(0.0, sr, sc)]
    g_score = {(sr, sc): 0.0}

    while open_set:
        f, r, c = heapq.heappop(open_set)

        if (r, c) == (er, ec):
            return int(g_score[(r, c)])

        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1),
                        (-1, -1), (-1, 1), (1, -1), (1, 1)]:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc]:
                cost = 1.414 if (dr != 0 and dc != 0) else 1.0
                ng = g_score[(r, c)] + cost
                if (nr, nc) not in g_score or ng < g_score[(nr, nc)]:
                    g_score[(nr, nc)] = ng
                    h = ((nr - er) ** 2 + (nc - ec) ** 2) ** 0.5
                    heapq.heappush(open_set, (ng + h, nr, nc))

    return -1


def find_nearest_walkable(
    grid: list[list[bool]],
    r: int,
    c: int,
    max_search: int = 5,
) -> Optional[tuple[int, int]]:
    """Find the nearest walkable grid cell within max_search radius."""
    rows = len(grid)
    cols = len(grid[0]) if rows > 0 else 0
    for dist in range(0, max_search + 1):
        for dr in range(-dist, dist + 1):
            for dc in range(-dist, dist + 1):
                if abs(dr) + abs(dc) != dist:
                    continue
                nr, nc = r + dr, c + dc
                if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc]:
                    return (nr, nc)
    return None


# ---------------------------------------------------------------------------
# Stage config helpers
# ---------------------------------------------------------------------------

def load_stage_configs() -> dict:
    """Load unified stage configs."""
    with open(STAGE_CONFIG_PATH) as f:
        return json.load(f)


def get_portal_position(
    stage_config: dict,
    portal_id: str,
) -> Optional[tuple[float, float, float]]:
    """Get portal position [x, y, z] by portal ID."""
    for portal in stage_config.get('portals', []):
        if portal.get('id') == portal_id:
            pos = portal.get('position', [0, 0, 0])
            return (pos[0], pos[1], pos[2])
    return None


def get_default_spawn(stage_config: dict) -> Optional[tuple[float, float, float]]:
    """Get default spawn position."""
    ds = stage_config.get('defaultSpawn')
    if ds and 'position' in ds:
        pos = ds['position']
        return (pos[0], pos[1], pos[2])
    return None


# ---------------------------------------------------------------------------
# Layer 1: Static Analysis
# ---------------------------------------------------------------------------

def layer1_static_analysis(
    section: dict,
    stage_configs: dict,
) -> list[str]:
    """Run static analysis on a quest section.

    Returns list of error/info strings (prefixed with check/cross mark).
    """
    results = []
    cells = section.get('cells', [])
    if not cells:
        results.append('  (i) No cells in section')
        return results

    cell_by_pos = {c['pos']: c for c in cells}
    start_pos = section.get('start_pos', '')
    end_pos = section.get('end_pos', '')

    # --- BFS reachability from start ---
    if start_pos not in cell_by_pos:
        results.append(f'  \u2717 Start cell {start_pos} not found in section')
        return results

    visited = set()
    queue = deque([start_pos])
    visited.add(start_pos)
    while queue:
        pos = queue.popleft()
        cell = cell_by_pos.get(pos)
        if not cell:
            continue
        for direction, target in cell.get('connections', {}).items():
            if target not in visited and target in cell_by_pos:
                visited.add(target)
                queue.append(target)

    all_positions = set(cell_by_pos.keys())
    unreachable = all_positions - visited
    if unreachable:
        results.append(
            f'  \u2717 {len(unreachable)} cell(s) unreachable from start: '
            f'{sorted(unreachable)}'
        )
    else:
        results.append(f'  \u2713 All {len(cells)} cells reachable from start')

    # --- End cell reachable ---
    if end_pos in visited:
        results.append(f'  \u2713 End cell {end_pos} reachable')
    elif end_pos:
        results.append(f'  \u2717 End cell {end_pos} NOT reachable from start')

    # --- Key ordering ---
    key_cells = [c for c in cells if c.get('has_key')]
    gate_cells = [c for c in cells if c.get('is_key_gate')]

    if not key_cells and not gate_cells:
        results.append('  \u2713 No key gates (no ordering issues)')
    else:
        # Check each key is reachable before its gate
        # BFS layer by layer, tracking which keys are available
        key_order_errors = _check_key_ordering(cell_by_pos, start_pos, key_cells, gate_cells)
        if key_order_errors:
            for err in key_order_errors:
                results.append(f'  \u2717 {err}')
        else:
            results.append(
                f'  \u2713 Key ordering valid ({len(key_cells)} key(s), '
                f'{len(gate_cells)} gate(s))'
            )

    # --- Floor checks ---
    enemy_count = 0
    box_count = 0
    floor_errors = []

    for cell in cells:
        stage_id = cell.get('stage_id', '')
        sc = stage_configs.get(stage_id, {})
        fc = sc.get('floorCollision', {})

        glb_path = get_floor_glb_path(stage_id)
        if not glb_path:
            # No floor GLB -- skip floor checks for this cell
            continue

        all_tris = load_floor_triangles(glb_path)
        floor_tris = filter_floor_triangles(all_tris, fc)

        # Check room area for cells with enemies
        cell_enemies = [o for o in cell.get('objects', []) if o.get('type') == 'enemy']
        cell_boxes = [
            o for o in cell.get('objects', [])
            if o.get('type') in ('box', 'rare_box')
        ]
        cell_keys_obj = [o for o in cell.get('objects', []) if o.get('type') == 'key']

        enemy_count += len(cell_enemies)
        box_count += len(cell_boxes)

        if cell_enemies and floor_tris:
            area = total_floor_area(floor_tris)
            if area < MIN_FLOOR_AREA_WITH_ENEMIES:
                floor_errors.append(
                    f'Cell {cell["pos"]} ({stage_id}): floor area {area:.1f} sq units '
                    f'< minimum {MIN_FLOOR_AREA_WITH_ENEMIES} for room with enemies'
                )

        # Check objects on floor
        for obj in cell.get('objects', []):
            obj_type = obj.get('type', '')
            if obj_type not in FLOOR_OBJECT_TYPES:
                continue
            pos = obj.get('position', [0, 0, 0])
            x, z = pos[0], pos[2]
            if floor_tris and not is_on_floor(x, z, floor_tris):
                floor_errors.append(
                    f'{obj_type.capitalize()} at ({x}, {pos[1]}, {z}) in cell '
                    f'{cell["pos"]} NOT on floor'
                )

    if floor_errors:
        for err in floor_errors:
            results.append(f'  \u2717 {err}')
    else:
        items = []
        if enemy_count:
            items.append(f'{enemy_count} enemies')
        if box_count:
            items.append(f'{box_count} boxes')
        if items:
            results.append(f'  \u2713 {", ".join(items)} on walkable floor')
        else:
            results.append('  \u2713 No placeable objects to check')

    return results


def _check_key_ordering(
    cell_by_pos: dict,
    start_pos: str,
    key_cells: list[dict],
    gate_cells: list[dict],
) -> list[str]:
    """Check that every key is reachable before its gate.

    Returns a list of error strings (empty if valid).
    """
    errors = []

    # Build a mapping: key_for_cell -> cell pos that has the key
    key_providers = {}
    for kc in key_cells:
        target = kc.get('key_for_cell', '')
        if target:
            key_providers[target] = kc['pos']

    # BFS respecting key gates
    # A key gate requires having the key first
    keys_held: set[str] = set()
    visited: set[str] = set()
    queue = deque([start_pos])
    visited.add(start_pos)

    # Track which gate cells we couldn't pass through
    blocked_gates: dict[str, str] = {}  # gate_pos -> required key_for_cell

    for gc in gate_cells:
        gate_dir = gc.get('key_gate_direction', '')
        # The gate blocks entry from the key_gate_direction
        blocked_gates[gc['pos']] = gc['pos']

    progress = True
    while progress:
        progress = False
        frontier = deque(list(visited))
        while frontier:
            pos = frontier.popleft()
            cell = cell_by_pos.get(pos)
            if not cell:
                continue

            # Pick up keys in this cell
            if cell.get('has_key'):
                key_target = cell.get('key_for_cell', '')
                if key_target and key_target not in keys_held:
                    keys_held.add(key_target)
                    progress = True

            for direction, target in cell.get('connections', {}).items():
                if target in visited:
                    continue
                target_cell = cell_by_pos.get(target)
                if not target_cell:
                    continue

                # Check if target is a key gate
                if target_cell.get('is_key_gate'):
                    gate_dir = target_cell.get('key_gate_direction', '')
                    # The gate blocks from a specific direction
                    if gate_dir == direction and target not in keys_held:
                        continue  # Blocked

                visited.add(target)
                frontier.append(target)
                progress = True

    # After full BFS with key collection, check if any gate cell is unreachable
    for gc in gate_cells:
        if gc['pos'] not in visited:
            errors.append(
                f'Key gate at {gc["pos"]} unreachable (need key from '
                f'{key_providers.get(gc["pos"], "unknown")})'
            )

    return errors


# ---------------------------------------------------------------------------
# Layer 2: State Machine Simulation
# ---------------------------------------------------------------------------

def layer2_simulation(
    section: dict,
    stage_configs: dict,
) -> list[str]:
    """Simulate a player walking through the quest.

    Returns list of result strings.
    """
    results = []
    cells = section.get('cells', [])
    if not cells:
        results.append('  (i) No cells to simulate')
        return results

    cell_by_pos = {c['pos']: c for c in cells}
    start_pos = section.get('start_pos', '')
    end_pos = section.get('end_pos', '')

    if start_pos not in cell_by_pos:
        results.append(f'  \u2717 Cannot simulate: start cell {start_pos} not found')
        return results

    state = {
        'current_cell': start_pos,
        'keys_held': [],
        'rooms_visited': set(),
        'rooms_cleared': set(),
        'enemies_killed': 0,
        'total_steps': 0,
        'visit_order': [],
        'keys_used': 0,
    }

    # Count total enemies
    total_enemies = 0
    for cell in cells:
        for obj in cell.get('objects', []):
            if obj.get('type') == 'enemy':
                total_enemies += 1

    # DFS-based exploration that visits ALL cells, tracks when end is reached
    backtrack_stack = []  # stack of (pos, [remaining_unvisited_exits])
    reached_end = False
    end_step = -1
    max_steps = len(cells) * 6  # Safety limit

    while state['total_steps'] < max_steps:
        pos = state['current_cell']
        cell = cell_by_pos[pos]

        # Enter room
        if pos not in state['rooms_visited']:
            state['rooms_visited'].add(pos)
            state['visit_order'].append(pos)

            # Kill enemies
            cell_enemies = sum(
                1 for o in cell.get('objects', []) if o.get('type') == 'enemy'
            )
            state['enemies_killed'] += cell_enemies
            state['rooms_cleared'].add(pos)

            # Pick up keys
            if cell.get('has_key'):
                key_target = cell.get('key_for_cell', '')
                if key_target:
                    state['keys_held'].append(key_target)

        # Note when end is reached (but keep exploring)
        if pos == end_pos and not reached_end:
            reached_end = True
            end_step = state['total_steps']

        # Find all unvisited reachable exits from current room
        connections = cell.get('connections', {})
        unvisited_exits = []

        # Sort connections to prefer critical path (lower path_order)
        sorted_conns = sorted(
            connections.items(),
            key=lambda x: cell_by_pos.get(x[1], {}).get('path_order', 999),
        )

        for direction, target in sorted_conns:
            if target not in cell_by_pos:
                continue
            target_cell = cell_by_pos[target]

            if not _can_pass_gate(cell, target_cell, direction, state):
                continue

            if target not in state['rooms_visited']:
                unvisited_exits.append(target)

        if unvisited_exits:
            next_cell = unvisited_exits[0]
            # Push remaining exits onto backtrack stack
            if len(unvisited_exits) > 1:
                backtrack_stack.append((pos, unvisited_exits[1:]))
        else:
            # Try to backtrack to a room with unexplored exits
            next_cell = None
            while backtrack_stack:
                bt_pos, bt_remaining = backtrack_stack.pop()
                # Filter to still-unvisited targets
                bt_remaining = [
                    t for t in bt_remaining
                    if t not in state['rooms_visited']
                ]
                if bt_remaining:
                    next_cell = bt_remaining[0]
                    if len(bt_remaining) > 1:
                        backtrack_stack.append((bt_pos, bt_remaining[1:]))
                    state['visit_order'].append(f'(backtrack via {bt_pos})')
                    state['total_steps'] += 1
                    break

            if next_cell is None:
                break  # Fully explored or stuck

        # Check if passing through a key gate
        target_cell = cell_by_pos.get(next_cell)
        if target_cell and target_cell.get('is_key_gate'):
            gate_key = next_cell
            if gate_key in state['keys_held']:
                state['keys_held'].remove(gate_key)
                state['keys_used'] += 1

        state['current_cell'] = next_cell
        state['total_steps'] += 1

    # Results
    if reached_end:
        results.append(
            f'  \u2713 Quest completable in {end_step} steps '
            f'({state["total_steps"]} total exploring all branches)'
        )
    else:
        results.append(
            f'  \u2717 Quest NOT completable (stuck after {state["total_steps"]} steps '
            f'at cell {state["current_cell"]})'
        )

    results.append(f'  \u2713 {state["enemies_killed"]} enemies killed')
    results.append(f'  \u2713 {state["keys_used"]} keys used')

    visited_count = len(state['rooms_visited'])
    total_count = len(cells)
    if visited_count == total_count:
        results.append(f'  \u2713 All {total_count}/{total_count} cells visited')
    else:
        unvisited = set(cell_by_pos.keys()) - state['rooms_visited']
        results.append(
            f'  \u2717 Only {visited_count}/{total_count} cells visited '
            f'(missed: {sorted(unvisited)})'
        )

    # Visit order (abbreviated if long)
    order = state['visit_order']
    if len(order) <= 20:
        order_str = ' -> '.join(str(v) for v in order)
    else:
        order_str = ' -> '.join(str(v) for v in order[:10])
        order_str += f' -> ... -> {order[-1]}'
    results.append(f'  Visit order: {order_str}')

    return results


def _can_pass_gate(
    current_cell: dict,
    target_cell: dict,
    direction: str,
    state: dict,
) -> bool:
    """Check if the player can pass from current to target cell.

    Gates unlock when current room is cleared. Key gates require the key.
    """
    # Room must be cleared (enemies killed) to open regular gates
    if current_cell['pos'] not in state['rooms_cleared']:
        return False

    # Check key gates
    if target_cell.get('is_key_gate'):
        gate_dir = target_cell.get('key_gate_direction', '')
        if gate_dir == direction:
            # Need key for this cell
            if target_cell['pos'] not in state['keys_held']:
                return False

    return True


# ---------------------------------------------------------------------------
# Layer 3: Pathfinding within rooms
# ---------------------------------------------------------------------------

def layer3_pathfinding(
    section: dict,
    stage_configs: dict,
) -> list[str]:
    """Verify player can physically reach all objects in each room.

    Returns list of result strings.
    """
    results = []
    cells = section.get('cells', [])

    for cell in cells:
        stage_id = cell.get('stage_id', '')
        rotation = cell.get('rotation', 0)
        pos_label = cell['pos']
        sc = stage_configs.get(stage_id, {})
        fc = sc.get('floorCollision', {})

        glb_path = get_floor_glb_path(stage_id)
        if not glb_path:
            results.append(
                f'  Cell {pos_label} ({stage_id} rot={rotation}): '
                f'(skip) no floor GLB found'
            )
            continue

        all_tris = load_floor_triangles(glb_path)
        floor_tris = filter_floor_triangles(all_tris, fc)
        if not floor_tris:
            results.append(
                f'  Cell {pos_label} ({stage_id} rot={rotation}): '
                f'(skip) no floor triangles after filtering'
            )
            continue

        obstacles = sc.get('obstacles', [])
        grid, min_x, min_z, resolution = build_nav_grid(
            floor_tris, obstacles, resolution=1.0
        )

        if not grid:
            results.append(
                f'  Cell {pos_label} ({stage_id} rot={rotation}): '
                f'(skip) empty nav grid'
            )
            continue

        # Determine spawn point for this room
        spawn_pos = _get_room_spawn(cell, sc)
        if spawn_pos is None:
            # Fallback: use center of floor
            all_x = [p[0] for t in floor_tris for p in t]
            all_z = [p[1] for t in floor_tris for p in t]
            spawn_pos = (
                (min(all_x) + max(all_x)) / 2,
                0,
                (min(all_z) + max(all_z)) / 2,
            )

        spawn_r, spawn_c = world_to_grid(
            spawn_pos[0], spawn_pos[2], min_x, min_z, resolution
        )

        # If spawn is not on walkable cell, find nearest walkable
        rows = len(grid)
        cols = len(grid[0]) if rows > 0 else 0
        spawn_r = max(0, min(spawn_r, rows - 1))
        spawn_c = max(0, min(spawn_c, cols - 1))

        if not grid[spawn_r][spawn_c]:
            nearest = find_nearest_walkable(grid, spawn_r, spawn_c, max_search=5)
            if nearest:
                spawn_r, spawn_c = nearest
            else:
                results.append(
                    f'  Cell {pos_label} ({stage_id} rot={rotation}): '
                    f'\u2717 spawn at ({spawn_pos[0]:.1f}, {spawn_pos[2]:.1f}) '
                    f'not on walkable floor'
                )
                continue

        # Check pathfinding to each object
        cell_errors = []
        objects_checked = 0

        for obj in cell.get('objects', []):
            obj_type = obj.get('type', '')
            if obj_type not in FLOOR_OBJECT_TYPES:
                continue

            obj_pos = obj.get('position', [0, 0, 0])
            obj_x, obj_z = obj_pos[0], obj_pos[2]
            obj_r, obj_c = world_to_grid(obj_x, obj_z, min_x, min_z, resolution)

            obj_r = max(0, min(obj_r, rows - 1))
            obj_c = max(0, min(obj_c, cols - 1))

            # If target not walkable, find nearest
            if not grid[obj_r][obj_c]:
                nearest = find_nearest_walkable(grid, obj_r, obj_c, max_search=3)
                if nearest:
                    obj_r, obj_c = nearest
                else:
                    cell_errors.append(
                        f'{obj_type} at ({obj_x:.1f}, {obj_z:.1f}) not on nav grid'
                    )
                    continue

            dist = astar(grid, (spawn_r, spawn_c), (obj_r, obj_c))
            if dist < 0:
                cell_errors.append(
                    f'{obj_type} at ({obj_x:.1f}, {obj_z:.1f}) unreachable from spawn'
                )
            objects_checked += 1

        # Check pathfinding to exit portals
        connections = cell.get('connections', {})
        portals = cell.get('portals', {})

        for direction, target_pos in connections.items():
            portal_id = portals.get(direction)
            if not portal_id or portal_id == 'default':
                continue
            portal_pos = get_portal_position(sc, portal_id)
            if portal_pos is None:
                continue

            pr, pc = world_to_grid(
                portal_pos[0], portal_pos[2], min_x, min_z, resolution
            )
            pr = max(0, min(pr, rows - 1))
            pc = max(0, min(pc, cols - 1))

            if not grid[pr][pc]:
                nearest = find_nearest_walkable(grid, pr, pc, max_search=5)
                if nearest:
                    pr, pc = nearest

            dist = astar(grid, (spawn_r, spawn_c), (pr, pc))
            if dist < 0:
                cell_errors.append(
                    f'{direction} portal unreachable from spawn'
                )

        if cell_errors:
            for err in cell_errors:
                results.append(
                    f'  Cell {pos_label} ({stage_id} rot={rotation}): \u2717 {err}'
                )
        else:
            # Determine spawn description
            spawn_desc = _get_spawn_description(cell, sc)
            results.append(
                f'  Cell {pos_label} ({stage_id} rot={rotation}): '
                f'\u2713 all objects reachable from {spawn_desc}'
            )

    return results


def _get_room_spawn(
    cell: dict,
    stage_config: dict,
) -> Optional[tuple[float, float, float]]:
    """Determine where the player spawns in this room.

    For start cells: use defaultSpawn or first portal.
    For other cells: use the first portal that connects back to a visited room.
    """
    # If cell is start and has defaultSpawn
    if cell.get('is_start'):
        ds = get_default_spawn(stage_config)
        if ds:
            return ds

    # Use first available portal position
    portals = cell.get('portals', {})
    connections = cell.get('connections', {})

    # Prefer portal from a connection direction
    for direction in connections:
        portal_id = portals.get(direction)
        if portal_id and portal_id != 'default':
            pos = get_portal_position(stage_config, portal_id)
            if pos:
                return pos

    # Fallback: any portal
    for direction, portal_id in portals.items():
        if portal_id and portal_id != 'default':
            pos = get_portal_position(stage_config, portal_id)
            if pos:
                return pos

    return None


def _get_spawn_description(cell: dict, stage_config: dict) -> str:
    """Get a human-readable description of the spawn point."""
    if cell.get('is_start'):
        ds = get_default_spawn(stage_config)
        if ds:
            return 'spawn'

    connections = cell.get('connections', {})
    if connections:
        first_dir = list(connections.keys())[0]
        return f'{first_dir.upper()} portal'
    return 'portal'


# ---------------------------------------------------------------------------
# Main quest simulation
# ---------------------------------------------------------------------------

def simulate_quest(
    quest_path: str,
    stage_configs: dict,
    max_layer: int = 3,
) -> tuple[int, list[str]]:
    """Simulate a single quest file through all layers.

    Returns (error_count, output_lines).
    """
    with open(quest_path) as f:
        quest = json.load(f)

    quest_id = quest.get('id', os.path.basename(quest_path))
    output = [f'=== {quest_id} ===']
    error_count = 0

    for si, section in enumerate(quest.get('sections', [])):
        sec_type = section.get('type', 'grid')
        sec_area = section.get('area', '?')
        sec_label = f'Section {si} (type={sec_type}, area={sec_area})'
        output.append(f'  --- {sec_label} ---')

        # Layer 1
        output.append('  [Layer 1] Static Analysis')
        l1_results = layer1_static_analysis(section, stage_configs)
        for line in l1_results:
            output.append(f'  {line}')
            if '\u2717' in line:
                error_count += 1

        if max_layer < 2:
            continue

        # Layer 2
        output.append('  [Layer 2] Simulation')
        l2_results = layer2_simulation(section, stage_configs)
        for line in l2_results:
            output.append(f'  {line}')
            if '\u2717' in line:
                error_count += 1

        if max_layer < 3:
            continue

        # Layer 3
        output.append('  [Layer 3] Pathfinding')
        l3_results = layer3_pathfinding(section, stage_configs)
        for line in l3_results:
            output.append(f'  {line}')
            if '\u2717' in line:
                error_count += 1

    return error_count, output


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Simulate field quests to validate completability.'
    )
    parser.add_argument(
        '--quest',
        type=str,
        default=None,
        help='Simulate a specific quest by ID (e.g., valley_field_01)',
    )
    parser.add_argument(
        '--layer',
        type=int,
        default=3,
        choices=[1, 2, 3],
        help='Maximum layer to run (1=static, 2=+simulation, 3=+pathfinding)',
    )
    parser.add_argument(
        '--dir',
        type=str,
        default=None,
        help='Quest directory to scan (default: data/field_quests)',
    )
    args = parser.parse_args()

    quest_dir = os.path.join(PROJECT_ROOT, args.dir) if args.dir else FIELD_QUEST_DIR
    quest_dir = os.path.normpath(quest_dir)

    if not os.path.isdir(quest_dir):
        print(f'ERROR: Quest directory not found: {quest_dir}', file=sys.stderr)
        sys.exit(1)

    stage_configs = load_stage_configs()

    # Determine which quests to run
    if args.quest:
        quest_ids = [args.quest]
    else:
        manifest_path = os.path.join(quest_dir, 'manifest.json')
        if os.path.exists(manifest_path):
            with open(manifest_path) as f:
                quest_ids = json.load(f)
        else:
            quest_ids = [
                f.replace('.json', '')
                for f in sorted(os.listdir(quest_dir))
                if f.endswith('.json') and f != 'manifest.json'
            ]

    total_errors = 0
    total_quests = 0

    for qid in quest_ids:
        fname = qid if qid.endswith('.json') else qid + '.json'
        fpath = os.path.join(quest_dir, fname)

        if not os.path.exists(fpath):
            print(f'WARNING: Quest file not found: {fpath}', file=sys.stderr)
            continue

        total_quests += 1
        errors, output = simulate_quest(fpath, stage_configs, max_layer=args.layer)
        total_errors += errors

        for line in output:
            print(line)
        print()

    # Summary
    print(f'{"=" * 40}')
    if total_errors == 0:
        print(f'RESULT: All {total_quests} quest(s) passed with 0 errors')
    else:
        print(f'RESULT: {total_errors} error(s) found across {total_quests} quest(s)')
    sys.exit(1 if total_errors > 0 else 0)


if __name__ == '__main__':
    main()
