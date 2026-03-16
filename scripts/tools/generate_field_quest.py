#!/usr/bin/env python3
"""Procedurally generate field quest JSON files.

Reads stage configs from unified-stage-configs.json, picks a grid template,
assigns stages with correct rotations, places enemies/boxes in walkable zones,
validates clearability, and writes v1 quest JSON.

Usage:
    python scripts/tools/generate_field_quest.py --area gurhacia --name "Valley Patrol" \
        --output data/field_quests/valley_field_02.json [--seed 42]
"""

import argparse
import json
import math
import os
import random
import re
import struct
import sys
import time
from typing import Any

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, "..", "..")
STAGE_CONFIG_PATH = os.path.join(
    PROJECT_ROOT, "data", "stage_configs", "unified-stage-configs.json"
)

# ---------------------------------------------------------------------------
# Direction helpers
# ---------------------------------------------------------------------------

DIRECTIONS = ("north", "east", "south", "west")

OPPOSITE_DIR = {"north": "south", "south": "north", "east": "west", "west": "east"}

# 90-degree CW rotation steps: north->east->south->west->north
DIR_INDEX = {d: i for i, d in enumerate(DIRECTIONS)}

ROTATION_MAP = {
    0: {d: d for d in DIRECTIONS},
    90: {d: DIRECTIONS[(DIR_INDEX[d] + 1) % 4] for d in DIRECTIONS},
    180: {d: DIRECTIONS[(DIR_INDEX[d] + 2) % 4] for d in DIRECTIONS},
    270: {d: DIRECTIONS[(DIR_INDEX[d] + 3) % 4] for d in DIRECTIONS},
}

REVERSE_ROTATION = {0: 0, 90: 270, 180: 180, 270: 90}

# Grid movement: direction -> (row_delta, col_delta)
DIR_DELTA = {"north": (-1, 0), "south": (1, 0), "east": (0, 1), "west": (0, -1)}

# ---------------------------------------------------------------------------
# Area / enemy configuration
# ---------------------------------------------------------------------------

AREA_CONFIG = {
    "gurhacia": {"prefix": "s01"},
    "ozette": {"prefix": "s02"},
    "rioh": {"prefix": "s03"},
    "makara": {"prefix": "s04"},
    "paru": {"prefix": "s05"},
    "arca": {"prefix": "s06"},
    "dark": {"prefix": "s07"},
    "tower": {"prefix": "s08"},
}

# Maps area prefix -> folder basename in assets/stages/
# Full subfolder is "{folder}_{area_letter}", e.g. "valley_a", "wetlands_b"
AREA_FOLDERS = {
    "s00": "city",
    "s01": "valley",
    "s02": "wetlands",
    "s03": "snowfield",
    "s04": "makara",
    "s05": "paru",
    "s06": "arca",
    "s07": "shrine",
    "s08": "tower",
}

STAGES_DIR = os.path.join(PROJECT_ROOT, "assets", "stages")

ENEMY_POOLS = {
    "gurhacia": {
        "common": ["ghowl", "vulkure", "garapython"],
        "uncommon": ["garahadan", "grimble", "tormatible"],
        "bosses": ["reyburn"],
    },
    "ozette": {
        "common": ["porel", "pomarr", "hypao"],
        "uncommon": ["vespao", "pelcatraz"],
        "bosses": ["octo-diablo"],
    },
    "rioh": {
        "common": ["usanny", "usanimere", "reyhound"],
        "uncommon": ["stagg", "hildeghana"],
        "bosses": ["hildegao"],
    },
    "makara": {
        "common": ["batt", "bullbatt", "rumole"],
        "uncommon": ["kapantha", "rohjade"],
        "bosses": ["rohcrysta"],
    },
    "paru": {
        "common": ["pobomma", "bolix", "izhirak-s6"],
        "uncommon": ["goldix", "froutang"],
        "bosses": ["frunaked"],
    },
    "arca": {
        "common": ["korse", "akorse", "finjer-r"],
        "uncommon": ["finjer-g", "finjer-b"],
        "bosses": ["blade-mother"],
    },
    "dark": {
        "common": ["eulid", "eulidveil", "eulada"],
        "uncommon": ["euladaveil", "arkzein"],
        "bosses": ["dark-falz"],
    },
    "tower": {
        "common": ["ghowl", "korse", "eulid"],
        "uncommon": ["arkzein", "garahadan"],
        "bosses": ["dark-falz"],
    },
}

# ---------------------------------------------------------------------------
# Stage catalog
# ---------------------------------------------------------------------------

# Portal topology categories based on the set of portal directions.
# After reading the actual config, each stage is assigned to one of these.
TOPOLOGY_NAMES = {
    frozenset(["south"]): "N",  # dead-end (config south only)
    frozenset(["east"]): "N",  # dead-end (config east only, e.g. s01b_na1)
    frozenset(["north", "south"]): "I",  # inline corridor
    frozenset(["east", "north"]): "L",  # L-bend
    frozenset(["east", "south", "west"]): "T",  # T-junction
    frozenset(["east", "north", "south", "west"]): "X",  # crossroads
    frozenset(["north", "south", "west"]): "T",  # T-junction variant
}


def _portal_dir_set(portals: list[dict]) -> frozenset:
    return frozenset(p["direction"] for p in portals if "direction" in p)


class StageCatalog:
    """Indexes stage configs by area prefix + variant and topology."""

    def __init__(self, config_path: str):
        with open(config_path) as f:
            self.raw = json.load(f)

        # stage_id -> {portals: [...], obstacles: [...], defaultSpawn: ...}
        self.configs: dict[str, dict] = {}
        # (prefix, variant) -> topology -> [stage_id, ...]
        self.by_topology: dict[tuple[str, str], dict[str, list[str]]] = {}

        for stage_id, cfg in self.raw.items():
            portals = cfg.get("portals", [])
            obstacles = cfg.get("obstacles", [])
            default_spawn = cfg.get("defaultSpawn", None)
            self.configs[stage_id] = {
                "portals": portals,
                "obstacles": obstacles,
                "defaultSpawn": default_spawn,
            }

            dir_set = _portal_dir_set(portals)
            topo = TOPOLOGY_NAMES.get(dir_set)

            # Classify special stages
            prefix, variant, base_name = self._parse_stage_id(stage_id)
            if prefix is None:
                continue

            # Mark start stages (sa1, sa0) specially
            if base_name.startswith("sa"):
                if len(dir_set) == 1:
                    topo = "S"  # start with single portal
                elif len(dir_set) == 2 and dir_set == frozenset(["north", "south"]):
                    topo = "S2"  # b-variant sa1 with north+south
                else:
                    topo = "S"

            # ga1 is a gate/inline -- but some b-variants only have south
            if base_name == "ga1":
                if len(dir_set) == 2:
                    topo = "I"  # north+south
                elif len(dir_set) == 1:
                    topo = "N"  # dead-end (b-variant ga1 with south only)
                else:
                    topo = TOPOLOGY_NAMES.get(dir_set)

            # ia1 is a transition
            if base_name == "ia1":
                topo = "TRANS"

            if topo is None:
                # Stages with no portals (z-variant boss rooms, etc)
                if len(dir_set) == 0:
                    topo = "BOSS"
                else:
                    continue  # skip unknown topologies

            key = (prefix, variant)
            if key not in self.by_topology:
                self.by_topology[key] = {}
            self.by_topology[key].setdefault(topo, []).append(stage_id)

    @staticmethod
    def _parse_stage_id(stage_id: str):
        """Parse 's01a_lb1' -> ('s01', 'a', 'lb1'). Returns (None,...) for tower etc."""
        parts = stage_id.split("_", 1)
        if len(parts) != 2:
            return None, None, None
        prefix_variant = parts[0]
        base_name = parts[1]

        # Tower: s080_sa0, s081_ga1, etc.
        if len(prefix_variant) == 4 and prefix_variant[:3] == "s08":
            # floor digit is the variant
            return "s08", prefix_variant[3], base_name

        if len(prefix_variant) < 4:
            return None, None, None

        prefix = prefix_variant[:3]
        variant = prefix_variant[3]
        return prefix, variant, base_name

    def get_stages(self, prefix: str, variant: str, topo: str) -> list[str]:
        """Get stage IDs matching prefix+variant+topology."""
        key = (prefix, variant)
        return list(self.by_topology.get(key, {}).get(topo, []))

    def get_portal_by_config_dir(
        self, stage_id: str, config_dir: str
    ) -> dict | None:
        """Get the portal object for a given config-space direction."""
        cfg = self.configs.get(stage_id)
        if not cfg:
            return None
        for p in cfg["portals"]:
            if p.get("direction") == config_dir:
                return p
        return None

    def get_config_directions(self, stage_id: str) -> set[str]:
        """Return the set of config-space portal directions for a stage."""
        cfg = self.configs.get(stage_id)
        if not cfg:
            return set()
        return {p["direction"] for p in cfg["portals"]}

    def get_obstacles(self, stage_id: str) -> list[dict]:
        cfg = self.configs.get(stage_id)
        return cfg["obstacles"] if cfg else []

    def get_default_spawn(self, stage_id: str) -> dict | None:
        cfg = self.configs.get(stage_id)
        return cfg["defaultSpawn"] if cfg else None


# ---------------------------------------------------------------------------
# Walkable zone estimation
# ---------------------------------------------------------------------------


def compute_walkable_bounds(
    portals: list[dict], obstacles: list[dict]
) -> tuple[float, float, float, float]:
    """Compute (min_x, max_x, min_z, max_z) safe zone for a stage.

    Based on portal positions + origin, shrunk by 4 units, with minimum 8-unit span.
    """
    points_x = [0.0]
    points_z = [0.0]
    for p in portals:
        pos = p.get("position", [0, 0, 0])
        points_x.append(pos[0])
        points_z.append(pos[2])

    min_x = min(points_x)
    max_x = max(points_x)
    min_z = min(points_z)
    max_z = max(points_z)

    # Shrink inward by 4 units
    margin = 4.0
    min_x += margin
    max_x -= margin
    min_z += margin
    max_z -= margin

    # Ensure minimum 8-unit span
    min_span = 8.0
    for attr in [("x", "min_x", "max_x"), ("z", "min_z", "max_z")]:
        lo_name, hi_name = attr[1], attr[2]
        lo = locals()[lo_name]
        hi = locals()[hi_name]
        if hi - lo < min_span:
            center = (lo + hi) / 2.0
            lo = center - min_span / 2.0
            hi = center + min_span / 2.0
        if lo_name == "min_x":
            min_x, max_x = lo, hi
        else:
            min_z, max_z = lo, hi

    return min_x, max_x, min_z, max_z


def is_clear_of_obstacles(
    x: float, z: float, obstacles: list[dict], clearance: float = 2.0
) -> bool:
    """Check if position (x, z) is clear of all obstacles."""
    for obs in obstacles:
        ox, _, oz = obs.get("position", [0, 0, 0])
        if obs.get("type") == "cylinder":
            radius = obs.get("radius", 1.0) + clearance
            dist = math.sqrt((x - ox) ** 2 + (z - oz) ** 2)
            if dist < radius:
                return False
        elif obs.get("type") == "box":
            half_w = obs.get("width", 2.0) / 2.0 + clearance
            half_d = obs.get("depth", 2.0) / 2.0 + clearance
            # Simplified AABB check (ignoring rotation for safety margin)
            if abs(x - ox) < max(half_w, half_d) and abs(z - oz) < max(half_w, half_d):
                return False
    return True


def sample_positions(
    count: int,
    portals: list[dict],
    obstacles: list[dict],
    min_spacing: float = 3.0,
    rng: random.Random | None = None,
) -> list[list[float]]:
    """Sample `count` positions within walkable zone, spaced apart."""
    if rng is None:
        rng = random.Random()

    min_x, max_x, min_z, max_z = compute_walkable_bounds(portals, obstacles)
    placed: list[list[float]] = []
    attempts = 0
    max_attempts = count * 80

    while len(placed) < count and attempts < max_attempts:
        attempts += 1
        x = round(rng.uniform(min_x, max_x), 1)
        z = round(rng.uniform(min_z, max_z), 1)

        if not is_clear_of_obstacles(x, z, obstacles):
            continue

        # Check spacing from already-placed objects
        too_close = False
        for px, _, pz in placed:
            if math.sqrt((x - px) ** 2 + (z - pz) ** 2) < min_spacing:
                too_close = True
                break
        if too_close:
            continue

        placed.append([x, 0, z])

    return placed


# ---------------------------------------------------------------------------
# Portal ID generation
# ---------------------------------------------------------------------------

_portal_counter = 0


def make_portal_id() -> str:
    """Generate a unique portal ID similar to the quest editor format."""
    global _portal_counter
    _portal_counter += 1
    ts = int(time.time() * 1000) + _portal_counter
    suffix = "".join(
        random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(9)
    )
    return f"portal_{ts}_{suffix}"


def reset_portal_ids():
    global _portal_counter
    _portal_counter = 0


# ---------------------------------------------------------------------------
# Grid templates
# ---------------------------------------------------------------------------
# Each template is a list of cell descriptors:
#   (row, col, role, needed_game_dirs)
# role: S=start, I=inline, L=L-bend, T=T-junction, X=crossroads, N=dead-end, E=end(warp)
# needed_game_dirs: directions the cell needs in game space (after rotation)
# connections are inferred from adjacency + matching directions

TemplateCell = tuple[int, int, str, set[str]]


def _template_t_branch() -> list[TemplateCell]:
    """Template 1 -- T-Branch (8 cells)."""
    return [
        (0, 2, "S", {"south"}),
        (1, 2, "X", {"north", "south", "east", "west"}),
        (1, 1, "N", {"east"}),
        (1, 3, "N", {"west"}),
        (2, 2, "I", {"north", "south"}),
        (3, 2, "T", {"north", "east", "west"}),
        (3, 1, "N", {"east"}),
        (3, 3, "E", {"west"}),
    ]


def _template_zigzag() -> list[TemplateCell]:
    """Template 2 -- Zigzag (6 cells)."""
    return [
        (0, 0, "S", {"south"}),
        (1, 0, "L", {"north", "east"}),
        (1, 1, "I", {"west", "east"}),
        (1, 2, "L", {"west", "south"}),
        (2, 2, "I", {"north", "south"}),
        (3, 2, "N", {"north"}),
    ]


def _template_linear() -> list[TemplateCell]:
    """Template 3 -- Linear (5 cells)."""
    return [
        (0, 0, "S", {"south"}),
        (1, 0, "I", {"north", "south"}),
        (2, 0, "I", {"north", "south"}),
        (3, 0, "I", {"north", "south"}),
        (4, 0, "E", {"north", "south"}),
    ]


def _template_hub() -> list[TemplateCell]:
    """Template 4 -- Hub (7 cells).

    The center T-junction connects north (to start), south (to continuation),
    east (to corridor), and west (to dead-end). This requires an X (crossroads)
    stage since it needs 4 directions.
    """
    return [
        (0, 1, "S", {"south"}),
        (1, 1, "X", {"north", "south", "east", "west"}),
        (1, 0, "N", {"east"}),
        (1, 2, "I", {"west", "east"}),
        (1, 3, "N", {"west"}),
        (2, 1, "I", {"north", "south"}),
        (3, 1, "N", {"north"}),
    ]


def _template_tower_linear() -> list[TemplateCell]:
    """Tower-specific linear template (4 cells per floor)."""
    return [
        (0, 0, "S", {"south"}),
        (1, 0, "I", {"north", "south"}),
        (2, 0, "I", {"north", "south"}),
        (3, 0, "I", {"north", "south"}),
        (4, 0, "E", {"north", "south"}),
    ]


def _template_tower_l() -> list[TemplateCell]:
    """Tower-specific L-shaped template (5 cells)."""
    return [
        (0, 0, "S", {"south"}),
        (1, 0, "L", {"north", "east"}),
        (1, 1, "I", {"west", "east"}),
        (1, 2, "I", {"west", "east"}),
        (1, 3, "E", {"west"}),
    ]


ALL_TEMPLATES = [_template_t_branch, _template_zigzag, _template_linear, _template_hub]
TOWER_TEMPLATES = [_template_tower_linear, _template_tower_l]

# ---------------------------------------------------------------------------
# Rotation solver
# ---------------------------------------------------------------------------


def find_rotation_for_stage(
    config_dirs: set[str], needed_game_dirs: set[str]
) -> int | None:
    """Find a rotation (0/90/180/270) that maps config_dirs to needed_game_dirs.

    Returns None if no rotation works.
    """
    for rot in (0, 90, 180, 270):
        rmap = ROTATION_MAP[rot]
        rotated = {rmap[d] for d in config_dirs}
        if needed_game_dirs.issubset(rotated):
            return rot
    return None


def game_dir_to_config_dir(game_dir: str, rotation: int) -> str:
    """Reverse-rotate a game direction to find the config direction."""
    rev = REVERSE_ROTATION[rotation]
    return ROTATION_MAP[rev][game_dir]


# ---------------------------------------------------------------------------
# Stage assignment
# ---------------------------------------------------------------------------


def _topology_for_role(role: str) -> list[str]:
    """Map a template role to acceptable topology categories."""
    if role == "S":
        # S2 covers b-variant sa1 with north+south (superset of south-only)
        return ["S", "S2"]
    elif role == "I":
        return ["I"]
    elif role == "L":
        return ["L"]
    elif role == "T":
        return ["T"]
    elif role == "X":
        return ["X"]
    elif role == "N":
        return ["N"]
    elif role == "E":
        # End cells can use inline stages (ga1) or dead-ends
        return ["I", "N"]
    return ["I"]


def assign_stages(
    template: list[TemplateCell],
    catalog: StageCatalog,
    prefix: str,
    variant: str,
    rng: random.Random,
) -> list[dict] | None:
    """Assign concrete stage IDs and rotations to template cells.

    Returns list of cell dicts or None if assignment fails.
    """
    cells = []
    used_stages: set[str] = set()

    for row, col, role, needed_dirs in template:
        topos = _topology_for_role(role)
        assigned = False

        for topo in topos:
            candidates = catalog.get_stages(prefix, variant, topo)
            rng.shuffle(candidates)

            for stage_id in candidates:
                config_dirs = catalog.get_config_directions(stage_id)
                rot = find_rotation_for_stage(config_dirs, needed_dirs)
                if rot is not None:
                    cells.append(
                        {
                            "row": row,
                            "col": col,
                            "role": role,
                            "stage_id": stage_id,
                            "rotation": rot,
                            "needed_dirs": needed_dirs,
                            "config_dirs": config_dirs,
                        }
                    )
                    assigned = True
                    break

            if assigned:
                break

        if not assigned:
            return None

    return cells


def assign_stages_for_b_start(
    catalog: StageCatalog, prefix: str
) -> dict | None:
    """Assign the b-grid start cell (b-variant sa1 with north+south)."""
    # b-variant sa1 has north+south
    candidates = catalog.get_stages(prefix, "b", "S2")
    if not candidates:
        # fall back to regular start
        candidates = catalog.get_stages(prefix, "b", "S")
    if not candidates:
        return None
    stage_id = candidates[0]
    config_dirs = catalog.get_config_directions(stage_id)
    rot = find_rotation_for_stage(config_dirs, {"south"})
    if rot is None:
        rot = find_rotation_for_stage(config_dirs, {"north", "south"})
    if rot is None:
        return None
    return {
        "stage_id": stage_id,
        "rotation": rot,
        "config_dirs": config_dirs,
    }


# ---------------------------------------------------------------------------
# Cell builder (JSON output)
# ---------------------------------------------------------------------------


def build_cell_json(
    cell: dict,
    catalog: StageCatalog,
    connections: dict[str, str],
    path_order: int,
    is_start: bool = False,
    is_end: bool = False,
    is_branch: bool = False,
    warp_edge: str = "",
    objects: list[dict] | None = None,
) -> dict:
    """Build a single cell dict matching the v1 quest schema."""
    stage_id = cell["stage_id"]
    rotation = cell["rotation"]

    # Build portals dict: game_dir -> portal_id
    portals = {}
    for game_dir in connections:
        config_dir = game_dir_to_config_dir(game_dir, rotation)
        portal_obj = catalog.get_portal_by_config_dir(stage_id, config_dir)
        if portal_obj:
            portals[game_dir] = portal_obj["id"]
        else:
            portals[game_dir] = make_portal_id()

    # Add warp_edge portal if present
    if warp_edge and warp_edge not in portals:
        config_dir = game_dir_to_config_dir(warp_edge, rotation)
        portal_obj = catalog.get_portal_by_config_dir(stage_id, config_dir)
        if portal_obj:
            portals[warp_edge] = portal_obj["id"]
        else:
            portals[warp_edge] = make_portal_id()

    # Add default spawn for start cells
    if is_start:
        spawn = catalog.get_default_spawn(stage_id)
        if spawn:
            portals["default"] = "default"

    pos_str = f"{cell['row']},{cell['col']}"

    return {
        "pos": pos_str,
        "stage_id": stage_id,
        "rotation": rotation,
        "connections": connections,
        "portals": portals,
        "is_start": is_start,
        "is_end": is_end,
        "is_branch": is_branch,
        "has_key": False,
        "key_for_cell": "",
        "is_key_gate": False,
        "key_gate_direction": "",
        "key_drop": "",
        "required_keys": 0,
        "warp_edge": warp_edge,
        "path_order": path_order,
        "objects": objects or [],
    }


# ---------------------------------------------------------------------------
# Connection inference
# ---------------------------------------------------------------------------


def infer_connections(
    cells: list[dict],
) -> dict[tuple[int, int], dict[str, str]]:
    """From assigned cells with positions and needed_dirs, compute connections.

    Returns {(row, col): {dir: "row,col", ...}}.
    """
    pos_set = {(c["row"], c["col"]) for c in cells}
    connections: dict[tuple[int, int], dict[str, str]] = {
        (c["row"], c["col"]): {} for c in cells
    }
    cell_lookup = {(c["row"], c["col"]): c for c in cells}

    for c in cells:
        r, col = c["row"], c["col"]
        for d in c["needed_dirs"]:
            dr, dc = DIR_DELTA[d]
            nr, nc = r + dr, col + dc
            if (nr, nc) in pos_set:
                opp = OPPOSITE_DIR[d]
                neighbor = cell_lookup[(nr, nc)]
                if opp in neighbor["needed_dirs"]:
                    connections[(r, col)][d] = f"{nr},{nc}"

    return connections


# ---------------------------------------------------------------------------
# Enemy / object placement
# ---------------------------------------------------------------------------


def place_objects_for_cell(
    cell: dict,
    catalog: StageCatalog,
    pool: dict,
    path_order: int,
    total_cells: int,
    is_branch_end: bool,
    is_boss: bool,
    rare_box_placed: list[bool],
    rng: random.Random,
) -> list[dict]:
    """Place enemies and boxes for a single cell."""
    stage_id = cell["stage_id"]
    portals_cfg = catalog.configs.get(stage_id, {}).get("portals", [])
    obstacles = catalog.get_obstacles(stage_id)
    objects: list[dict] = []

    # Start cells: no enemies
    if cell.get("role") == "S":
        return []

    if is_boss:
        # Boss cell: 1 boss + 2 common support
        enemy_ids = [rng.choice(pool["bosses"])]
        enemy_ids.extend(rng.choices(pool["common"], k=2))
        positions = sample_positions(len(enemy_ids), portals_cfg, obstacles, rng=rng)
        for eid, pos in zip(enemy_ids, positions):
            objects.append({"type": "enemy", "position": pos, "enemy_id": eid})
        return objects

    # Determine enemy count and mix based on position
    late_threshold = total_cells * 0.6
    if is_branch_end:
        # Dead-end branches: 1-2 enemies + 2-3 boxes
        enemy_count = rng.randint(1, 2)
        box_count = rng.randint(2, 3)
        enemy_ids = []
        for _ in range(enemy_count):
            if rng.random() < 0.4:
                enemy_ids.append(rng.choice(pool["uncommon"]))
            else:
                enemy_ids.append(rng.choice(pool["common"]))
    elif path_order >= late_threshold:
        # Late cells: 2-3 with mix of common + uncommon
        enemy_count = rng.randint(2, 3)
        box_count = 0
        enemy_ids = []
        for _ in range(enemy_count):
            if rng.random() < 0.5:
                enemy_ids.append(rng.choice(pool["uncommon"]))
            else:
                enemy_ids.append(rng.choice(pool["common"]))
    else:
        # Corridor/junction cells: 2-3 common enemies
        enemy_count = rng.randint(2, 3)
        box_count = 0
        enemy_ids = rng.choices(pool["common"], k=enemy_count)

    total_needed = enemy_count + (box_count if is_branch_end else 0)
    positions = sample_positions(
        total_needed, portals_cfg, obstacles, rng=rng
    )

    idx = 0
    for eid in enemy_ids:
        if idx < len(positions):
            objects.append(
                {"type": "enemy", "position": positions[idx], "enemy_id": eid}
            )
            idx += 1

    if is_branch_end:
        for i in range(box_count):
            if idx < len(positions):
                if not rare_box_placed[0] and i == box_count - 1:
                    objects.append({"type": "rare_box", "position": positions[idx]})
                    rare_box_placed[0] = True
                else:
                    objects.append({"type": "box", "position": positions[idx]})
                idx += 1

    return objects


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------


def build_grid_section(
    template_cells: list[dict],
    catalog: StageCatalog,
    pool: dict,
    variant: str,
    rng: random.Random,
    rare_box_placed: list[bool],
) -> dict:
    """Build a complete grid section from assigned template cells."""
    connections = infer_connections(template_cells)
    total_cells = len(template_cells)

    # Compute path_order via BFS from start
    start_cell = None
    for c in template_cells:
        if c["role"] == "S":
            start_cell = c
            break
    if start_cell is None:
        start_cell = template_cells[0]

    visited_order = bfs_order(template_cells, connections, start_cell)

    # Identify branch ends (dead-ends that aren't start or warp_edge end)
    branch_ends = set()
    for c in template_cells:
        pos = (c["row"], c["col"])
        conn = connections.get(pos, {})
        if len(conn) == 1 and c["role"] not in ("S", "E"):
            branch_ends.add(pos)

    # Build JSON cells
    json_cells = []
    end_cell = None
    for c in template_cells:
        if c["role"] == "E":
            end_cell = c
            break
    # If no explicit end, use the cell with highest path_order
    if end_cell is None:
        end_cell = max(template_cells, key=lambda x: visited_order.get((x["row"], x["col"]), 0))

    for c in template_cells:
        pos = (c["row"], c["col"])
        conn = connections.get(pos, {})
        path_order = visited_order.get(pos, 0)
        is_start = c["role"] == "S"
        is_end = c is end_cell
        is_branch = len(conn) > 2
        is_branch_end = pos in branch_ends

        # Determine warp_edge for end cells
        warp_edge = ""
        if is_end and c["role"] == "E":
            # Compute actual game-space directions from the stage's config dirs + rotation
            rmap = ROTATION_MAP[c["rotation"]]
            rotated_dirs = {rmap[d] for d in c["config_dirs"]}
            # warp_edge is a rotated direction that is NOT used as a connection
            for d in rotated_dirs:
                if d not in conn:
                    warp_edge = d
                    break
            # Fallback: check needed_dirs too
            if not warp_edge:
                for d in c["needed_dirs"]:
                    if d not in conn:
                        warp_edge = d
                        break

        objects = place_objects_for_cell(
            c, catalog, pool, path_order, total_cells,
            is_branch_end, False, rare_box_placed, rng,
        )

        json_cells.append(
            build_cell_json(
                c, catalog, conn, path_order,
                is_start=is_start, is_end=is_end,
                is_branch=is_branch, warp_edge=warp_edge,
                objects=objects,
            )
        )

    # Sort by path_order
    json_cells.sort(key=lambda x: x["path_order"])

    start_pos = f"{start_cell['row']},{start_cell['col']}"
    end_pos = f"{end_cell['row']},{end_cell['col']}"

    return {
        "type": "grid",
        "area": variant,
        "start_pos": start_pos,
        "end_pos": end_pos,
        "cells": json_cells,
    }


def build_transition_section(
    catalog: StageCatalog,
    prefix: str,
    pool: dict,
    rng: random.Random,
) -> dict:
    """Build a transition section (single ia1 cell)."""
    stage_id = f"{prefix}e_ia1"
    if stage_id not in catalog.configs:
        # fallback
        stage_id = f"{prefix}a_ia1"
    if stage_id not in catalog.configs:
        # Use any available ia1
        for sid in catalog.configs:
            if "_ia1" in sid:
                stage_id = sid
                break

    config_dirs = catalog.get_config_directions(stage_id)
    rotation = find_rotation_for_stage(config_dirs, {"north", "south"}) or 0
    portals_cfg = catalog.configs.get(stage_id, {}).get("portals", [])
    obstacles = catalog.get_obstacles(stage_id)

    # Place 2-3 enemies
    enemy_count = rng.randint(2, 3)
    enemy_ids = []
    for _ in range(enemy_count):
        if rng.random() < 0.3:
            enemy_ids.append(rng.choice(pool["uncommon"]))
        else:
            enemy_ids.append(rng.choice(pool["common"]))

    positions = sample_positions(enemy_count + 1, portals_cfg, obstacles, rng=rng)
    objects: list[dict] = []
    for i, eid in enumerate(enemy_ids):
        if i < len(positions):
            objects.append({"type": "enemy", "position": positions[i], "enemy_id": eid})

    # Maybe add a box
    if len(positions) > len(enemy_ids):
        objects.append({"type": "box", "position": positions[len(enemy_ids)]})

    cell_data = {
        "row": 0,
        "col": 0,
        "role": "TRANS",
        "stage_id": stage_id,
        "rotation": rotation,
        "needed_dirs": {"north", "south"},
        "config_dirs": config_dirs,
    }

    # Portals
    portals = {}
    for game_dir in ("north", "south"):
        config_dir = game_dir_to_config_dir(game_dir, rotation)
        portal_obj = catalog.get_portal_by_config_dir(stage_id, config_dir)
        if portal_obj:
            portals[game_dir] = portal_obj["id"]
        else:
            portals[game_dir] = make_portal_id()

    cell_json = {
        "pos": "0,0",
        "stage_id": stage_id,
        "rotation": rotation,
        "connections": {},
        "portals": portals,
        "is_start": True,
        "is_end": True,
        "is_branch": False,
        "has_key": False,
        "key_for_cell": "",
        "is_key_gate": False,
        "key_gate_direction": "",
        "key_drop": "",
        "required_keys": 0,
        "warp_edge": "north",
        "path_order": 0,
        "objects": objects,
    }

    return {
        "type": "transition",
        "area": "e",
        "start_pos": "0,0",
        "end_pos": "0,0",
        "entry_direction": "south",
        "exit_direction": "north",
        "cells": [cell_json],
    }


def build_boss_section(
    catalog: StageCatalog,
    prefix: str,
    pool: dict,
    rng: random.Random,
) -> dict:
    """Build a boss section (single na1 cell with boss + support)."""
    # Prefer z-variant na1, fall back to a-variant
    stage_id = f"{prefix}z_na1"
    if stage_id not in catalog.configs or not catalog.get_config_directions(stage_id):
        stage_id = f"{prefix}a_na1"
    if stage_id not in catalog.configs:
        # Use any na1 we can find for this prefix
        for sid in catalog.configs:
            if sid.startswith(prefix) and "_na1" in sid:
                stage_id = sid
                break

    config_dirs = catalog.get_config_directions(stage_id)
    # Boss room uses rotation 180 of na1 (so south portal -> north in game)
    rotation = find_rotation_for_stage(config_dirs, {"north"})
    if rotation is None:
        # If na1 has no portals (z-variant), just use 180
        rotation = 180

    portals_cfg = catalog.configs.get(stage_id, {}).get("portals", [])
    obstacles = catalog.get_obstacles(stage_id)

    # Place boss + 2 support
    enemy_ids = [rng.choice(pool["bosses"])]
    enemy_ids.extend(rng.choices(pool["common"], k=2))
    positions = sample_positions(3, portals_cfg, obstacles, rng=rng)

    objects: list[dict] = []
    for i, eid in enumerate(enemy_ids):
        if i < len(positions):
            objects.append({"type": "enemy", "position": positions[i], "enemy_id": eid})

    # Portal for entry
    portals = {}
    if config_dirs:
        for game_dir in ("north",):
            config_dir = game_dir_to_config_dir(game_dir, rotation)
            portal_obj = catalog.get_portal_by_config_dir(stage_id, config_dir)
            if portal_obj:
                portals[game_dir] = portal_obj["id"]
            else:
                portals[game_dir] = make_portal_id()

    cell_json = {
        "pos": "0,0",
        "stage_id": stage_id,
        "rotation": rotation,
        "connections": {},
        "portals": portals,
        "is_start": True,
        "is_end": True,
        "is_branch": False,
        "has_key": False,
        "key_for_cell": "",
        "is_key_gate": False,
        "key_gate_direction": "",
        "key_drop": "",
        "required_keys": 0,
        "warp_edge": "north",
        "path_order": 0,
        "objects": objects,
    }

    return {
        "type": "boss",
        "area": "z",
        "start_pos": "0,0",
        "end_pos": "0,0",
        "cells": [cell_json],
    }


# ---------------------------------------------------------------------------
# Tower section builder
# ---------------------------------------------------------------------------


def build_tower_sections(
    catalog: StageCatalog,
    pool: dict,
    rng: random.Random,
) -> list[dict]:
    """Build all sections for a tower quest (floors s080-s087)."""
    sections: list[dict] = []
    rare_box_placed = [False]

    # Grid A: floors s080 (entrance) through s083
    # Use entrance s080_sa0 + floors s081-s083
    a_cells: list[TemplateCell] = [(0, 0, "S", {"south"})]
    row = 1
    for floor in ["s081", "s082", "s083"]:
        a_cells.append((row, 0, "I", {"north", "south"}))
        row += 1

    # Assign stages manually for tower
    a_assigned = []
    # Entrance
    a_assigned.append({
        "row": 0, "col": 0, "role": "S",
        "stage_id": "s080_sa0", "rotation": 0,
        "needed_dirs": {"south"}, "config_dirs": catalog.get_config_directions("s080_sa0"),
    })
    for i, floor in enumerate(["s081", "s082", "s083"]):
        stage_ids = catalog.get_stages("s08", floor[-1], "I")
        if not stage_ids:
            stage_ids = [f"{floor}_ga1"]
        sid = rng.choice(stage_ids) if stage_ids else f"{floor}_ib1"
        if sid not in catalog.configs:
            sid = f"{floor}_ga1"
        config_dirs = catalog.get_config_directions(sid)
        rot = find_rotation_for_stage(config_dirs, {"north", "south"}) or 0
        a_assigned.append({
            "row": i + 1, "col": 0, "role": "I" if i < 2 else "E",
            "stage_id": sid, "rotation": rot,
            "needed_dirs": {"north", "south"}, "config_dirs": config_dirs,
        })

    # Mark last as end
    a_assigned[-1]["role"] = "E"

    grid_a = build_grid_section(a_assigned, catalog, pool, "a", rng, rare_box_placed)
    sections.append(grid_a)

    # Transition
    trans_stage = "s08e_ib1"
    if trans_stage not in catalog.configs:
        # fallback
        for sid in catalog.configs:
            if sid.startswith("s08") and "_ib1" in sid:
                trans_stage = sid
                break

    config_dirs = catalog.get_config_directions(trans_stage)
    rot = find_rotation_for_stage(config_dirs, {"north", "south"}) or 0
    portals_cfg = catalog.configs.get(trans_stage, {}).get("portals", [])
    obstacles = catalog.get_obstacles(trans_stage)

    enemy_count = rng.randint(2, 3)
    enemy_ids = rng.choices(pool["common"], k=enemy_count)
    positions = sample_positions(enemy_count, portals_cfg, obstacles, rng=rng)
    objects = []
    for eid, pos in zip(enemy_ids, positions):
        objects.append({"type": "enemy", "position": pos, "enemy_id": eid})

    t_portals = {}
    for game_dir in ("north", "south"):
        cfg_dir = game_dir_to_config_dir(game_dir, rot)
        portal_obj = catalog.get_portal_by_config_dir(trans_stage, cfg_dir)
        if portal_obj:
            t_portals[game_dir] = portal_obj["id"]
        else:
            t_portals[game_dir] = make_portal_id()

    trans_section = {
        "type": "transition",
        "area": "e",
        "start_pos": "0,0",
        "end_pos": "0,0",
        "entry_direction": "south",
        "exit_direction": "north",
        "cells": [{
            "pos": "0,0",
            "stage_id": trans_stage,
            "rotation": rot,
            "connections": {},
            "portals": t_portals,
            "is_start": True,
            "is_end": True,
            "is_branch": False,
            "has_key": False,
            "key_for_cell": "",
            "is_key_gate": False,
            "key_gate_direction": "",
            "key_drop": "",
            "required_keys": 0,
            "warp_edge": "north",
            "path_order": 0,
            "objects": objects,
        }],
    }
    sections.append(trans_section)

    # Grid B: floors s084-s086
    b_assigned = []
    for i, floor in enumerate(["s084", "s085", "s086"]):
        stage_ids = catalog.get_stages("s08", floor[-1], "I")
        if not stage_ids:
            stage_ids = [f"{floor}_ga1"]
        sid = rng.choice(stage_ids) if stage_ids else f"{floor}_ib1"
        if sid not in catalog.configs:
            sid = f"{floor}_ga1"
        config_dirs_b = catalog.get_config_directions(sid)
        rot_b = find_rotation_for_stage(config_dirs_b, {"north", "south"}) or 0
        role = "I"
        if i == 0:
            role = "S"
        elif i == len(["s084", "s085", "s086"]) - 1:
            role = "E"
        b_assigned.append({
            "row": i, "col": 0, "role": role,
            "stage_id": sid, "rotation": rot_b,
            "needed_dirs": {"north", "south"} if role != "S" else {"south"},
            "config_dirs": config_dirs_b,
        })

    # Fix: first cell of B-grid needs south only if it's start
    # Actually tower B-start uses sa1 with north+south
    b_first_floor = "s084"
    sa1_id = f"{b_first_floor}_sa1"
    if sa1_id in catalog.configs:
        b_assigned[0]["stage_id"] = sa1_id
        b_assigned[0]["config_dirs"] = catalog.get_config_directions(sa1_id)
        b_assigned[0]["needed_dirs"] = {"south"}
        rot_s = find_rotation_for_stage(b_assigned[0]["config_dirs"], {"south"})
        if rot_s is not None:
            b_assigned[0]["rotation"] = rot_s

    grid_b = build_grid_section(b_assigned, catalog, pool, "b", rng, rare_box_placed)
    # Override area label for tower B
    grid_b["area"] = "b"
    sections.append(grid_b)

    # Boss: s087_na1
    boss_section = {
        "type": "boss",
        "area": "z",
        "start_pos": "0,0",
        "end_pos": "0,0",
        "cells": [],
    }
    boss_stage = "s087_na1"
    if boss_stage not in catalog.configs:
        boss_stage = "s086_ga1"  # fallback

    b_config_dirs = catalog.get_config_directions(boss_stage)
    b_rot = 180 if not b_config_dirs else (find_rotation_for_stage(b_config_dirs, {"north"}) or 180)

    boss_portals_cfg = catalog.configs.get(boss_stage, {}).get("portals", [])
    boss_obstacles = catalog.get_obstacles(boss_stage)
    boss_enemy_ids = [rng.choice(pool["bosses"])] + rng.choices(pool["common"], k=2)
    boss_positions = sample_positions(3, boss_portals_cfg, boss_obstacles, rng=rng)
    boss_objects = []
    for eid, pos in zip(boss_enemy_ids, boss_positions):
        boss_objects.append({"type": "enemy", "position": pos, "enemy_id": eid})

    boss_portals = {}
    if b_config_dirs:
        for gd in ("north",):
            cd = game_dir_to_config_dir(gd, b_rot)
            po = catalog.get_portal_by_config_dir(boss_stage, cd)
            if po:
                boss_portals[gd] = po["id"]
            else:
                boss_portals[gd] = make_portal_id()

    boss_section["cells"].append({
        "pos": "0,0",
        "stage_id": boss_stage,
        "rotation": b_rot,
        "connections": {},
        "portals": boss_portals,
        "is_start": True,
        "is_end": True,
        "is_branch": False,
        "has_key": False,
        "key_for_cell": "",
        "is_key_gate": False,
        "key_gate_direction": "",
        "key_drop": "",
        "required_keys": 0,
        "warp_edge": "north",
        "path_order": 0,
        "objects": boss_objects,
    })
    sections.append(boss_section)

    return sections


# ---------------------------------------------------------------------------
# BFS / clearability
# ---------------------------------------------------------------------------


def bfs_order(
    cells: list[dict],
    connections: dict[tuple[int, int], dict[str, str]],
    start: dict,
) -> dict[tuple[int, int], int]:
    """BFS from start cell, return {(row,col): path_order}."""
    from collections import deque

    visited: dict[tuple[int, int], int] = {}
    queue: deque[tuple[int, int, int]] = deque()
    start_pos = (start["row"], start["col"])
    queue.append((*start_pos, 0))
    visited[start_pos] = 0

    while queue:
        r, c, order = queue.popleft()
        conn = connections.get((r, c), {})
        for d, target_str in conn.items():
            tr, tc = map(int, target_str.split(","))
            if (tr, tc) not in visited:
                visited[(tr, tc)] = order + 1
                queue.append((tr, tc, order + 1))

    return visited


def validate_clearability(sections: list[dict]) -> bool:
    """Verify all cells within each grid section are reachable from start."""
    for section in sections:
        if section["type"] not in ("grid",):
            continue
        cells = section["cells"]
        if not cells:
            continue

        # Build adjacency from connections
        pos_to_cell = {c["pos"]: c for c in cells}
        start_pos = section["start_pos"]
        if start_pos not in pos_to_cell:
            print(f"  WARNING: start_pos {start_pos} not found in section", file=sys.stderr)
            return False

        visited = {start_pos}
        queue = [start_pos]
        while queue:
            current = queue.pop(0)
            cell = pos_to_cell[current]
            for d, target in cell["connections"].items():
                if target not in visited and target in pos_to_cell:
                    visited.add(target)
                    queue.append(target)

        if len(visited) != len(cells):
            unreachable = set(pos_to_cell.keys()) - visited
            print(
                f"  WARNING: {len(unreachable)} unreachable cells: {unreachable}",
                file=sys.stderr,
            )
            return False

    return True


# ---------------------------------------------------------------------------
# Main generation
# ---------------------------------------------------------------------------


def generate_quest(
    area: str,
    name: str,
    output_path: str,
    seed: int | None = None,
    description: str | None = None,
) -> dict:
    """Generate a complete field quest JSON."""
    rng = random.Random(seed)
    reset_portal_ids()

    if area not in AREA_CONFIG:
        print(f"ERROR: Unknown area '{area}'. Valid: {list(AREA_CONFIG.keys())}", file=sys.stderr)
        sys.exit(1)

    prefix = AREA_CONFIG[area]["prefix"]
    pool = ENEMY_POOLS[area]
    catalog = StageCatalog(STAGE_CONFIG_PATH)

    quest_id = os.path.splitext(os.path.basename(output_path))[0]
    if description is None:
        description = f"Explore the wilds of {area.title()}. Danger lurks around every corner."

    today = time.strftime("%Y-%m-%d")

    if area == "tower":
        sections = build_tower_sections(catalog, pool, rng)
    else:
        sections = _generate_standard_sections(catalog, prefix, pool, rng)

    quest = {
        "version": 1,
        "last_updated": today,
        "id": quest_id,
        "name": name,
        "description": description,
        "area_id": area,
        "sections": sections,
    }

    # Validate clearability
    if not validate_clearability(sections):
        print("WARNING: Quest may have unreachable cells!", file=sys.stderr)

    return quest


def _generate_standard_sections(
    catalog: StageCatalog,
    prefix: str,
    pool: dict,
    rng: random.Random,
) -> list[dict]:
    """Generate sections for non-tower areas: Grid A + Transition E + Grid B + Boss Z."""
    sections: list[dict] = []
    rare_box_placed = [False]

    # --- Grid A ---
    templates = list(ALL_TEMPLATES)
    rng.shuffle(templates)
    grid_a_cells = None
    template_name = ""

    for template_fn in templates:
        template = template_fn()
        cells = assign_stages(template, catalog, prefix, "a", rng)
        if cells is not None:
            grid_a_cells = cells
            template_name = template_fn.__name__
            break

    if grid_a_cells is None:
        # Fallback to linear
        template = _template_linear()
        grid_a_cells = assign_stages(template, catalog, prefix, "a", rng)
        template_name = "_template_linear"
        if grid_a_cells is None:
            print("ERROR: Could not assign stages for Grid A", file=sys.stderr)
            sys.exit(1)

    grid_a = build_grid_section(grid_a_cells, catalog, pool, "a", rng, rare_box_placed)
    sections.append(grid_a)

    # --- Transition E ---
    trans = build_transition_section(catalog, prefix, pool, rng)
    sections.append(trans)

    # --- Grid B ---
    # Use a different (usually smaller) template for B
    b_templates = [_template_zigzag, _template_linear, _template_hub]
    rng.shuffle(b_templates)
    grid_b_cells = None

    for template_fn in b_templates:
        template = template_fn()
        cells = assign_stages(template, catalog, prefix, "b", rng)
        if cells is not None:
            grid_b_cells = cells
            break

    if grid_b_cells is None:
        # Fallback: try linear with a-variant stages
        template = _template_linear()
        grid_b_cells = assign_stages(template, catalog, prefix, "b", rng)
        if grid_b_cells is None:
            grid_b_cells = assign_stages(template, catalog, prefix, "a", rng)

    if grid_b_cells is None:
        print("ERROR: Could not assign stages for Grid B", file=sys.stderr)
        sys.exit(1)

    grid_b = build_grid_section(grid_b_cells, catalog, pool, "b", rng, rare_box_placed)
    sections.append(grid_b)

    # --- Boss Z ---
    boss = build_boss_section(catalog, prefix, pool, rng)
    sections.append(boss)

    return sections


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate a field quest JSON file."
    )
    parser.add_argument(
        "--area", required=True,
        choices=list(AREA_CONFIG.keys()),
        help="Area name (gurhacia, ozette, rioh, makara, paru, arca, dark, tower)",
    )
    parser.add_argument(
        "--name", required=True,
        help="Quest display name (e.g. 'Valley Patrol')",
    )
    parser.add_argument(
        "--output", required=True,
        help="Output JSON file path (e.g. data/field_quests/valley_field_02.json)",
    )
    parser.add_argument(
        "--seed", type=int, default=None,
        help="Random seed for reproducible generation",
    )
    parser.add_argument(
        "--description", type=str, default=None,
        help="Quest description text (optional)",
    )
    args = parser.parse_args()

    # Resolve output path relative to project root if not absolute
    output_path = args.output
    if not os.path.isabs(output_path):
        output_path = os.path.join(PROJECT_ROOT, output_path)

    quest = generate_quest(
        area=args.area,
        name=args.name,
        output_path=output_path,
        seed=args.seed,
        description=args.description,
    )

    # Ensure output directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w") as f:
        json.dump(quest, f, indent=2)
        f.write("\n")

    # Print summary
    total_cells = 0
    total_enemies = 0
    total_boxes = 0
    section_info = []
    for section in quest["sections"]:
        cells = section.get("cells", [])
        total_cells += len(cells)
        for cell in cells:
            for obj in cell.get("objects", []):
                if obj["type"] == "enemy":
                    total_enemies += 1
                elif obj["type"] in ("box", "rare_box"):
                    total_boxes += 1
        section_info.append(
            f"  {section['type']}({section['area']}): {len(cells)} cells"
        )

    print(f"Generated: {output_path}")
    print(f"  Quest: {quest['name']} ({quest['id']})")
    print(f"  Area: {quest['area_id']}")
    print(f"  Total cells: {total_cells}")
    print(f"  Total enemies: {total_enemies}")
    print(f"  Total boxes: {total_boxes}")
    print("  Sections:")
    for info in section_info:
        print(f"    {info}")


if __name__ == "__main__":
    main()
