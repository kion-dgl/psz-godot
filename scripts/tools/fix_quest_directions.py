#!/usr/bin/env python3
"""
Fix entry_direction / exit_direction on all quest JSON sections.

For each section:
- entry_direction: the direction of the start cell's unconnected portal
  that faces the previous section (i.e. the portal with no connection
  on the start cell, excluding the warp_edge)
- exit_direction: the warp_edge of the end cell, or the end cell's
  unconnected portal that faces the next section

Writes updated JSON back to disk.
"""

import json
import sys
from pathlib import Path

OPPOSITE = {"north": "south", "south": "north", "east": "west", "west": "east"}
QUEST_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "quests"


def get_unconnected_portals(cell: dict) -> list[str]:
    """Return portal directions that have no connection."""
    connections = cell.get("connections", {})
    portals = cell.get("portals", {})
    return [d for d in portals if d != "default" and d not in connections]


def compute_entry_direction(section: dict, prev_section: dict | None) -> str:
    """Compute entry_direction for a section."""
    # Already set
    existing = section.get("entry_direction", "")
    if existing:
        return existing

    # First section has no entry
    if prev_section is None:
        return ""

    cells = section.get("cells", [])
    start_pos = section.get("start_pos", "")
    start_cell = next((c for c in cells if c.get("pos") == start_pos), None)
    if not start_cell:
        return ""

    unconnected = get_unconnected_portals(start_cell)
    warp_edge = start_cell.get("warp_edge", "")

    # If there's only one unconnected portal (excluding warp_edge), that's the entry
    candidates = [d for d in unconnected if d != warp_edge]
    if len(candidates) == 1:
        return candidates[0]

    # Multiple candidates — use opposite of previous section's exit
    prev_exit = prev_section.get("exit_direction", "")
    if prev_exit and OPPOSITE.get(prev_exit) in candidates:
        return OPPOSITE[prev_exit]

    # Fall back: opposite of previous section's end cell warp_edge
    prev_cells = prev_section.get("cells", [])
    prev_end_pos = prev_section.get("end_pos", "")
    prev_end_cell = next((c for c in prev_cells if c.get("pos") == prev_end_pos), None)
    if prev_end_cell:
        prev_warp = prev_end_cell.get("warp_edge", "")
        if prev_warp and OPPOSITE.get(prev_warp) in candidates:
            return OPPOSITE[prev_warp]

    # Still ambiguous — pick first candidate
    return candidates[0] if candidates else ""


def compute_exit_direction(section: dict, next_section: dict | None) -> str:
    """Compute exit_direction for a section."""
    existing = section.get("exit_direction", "")
    if existing:
        return existing

    # Last section has no exit (returns to city)
    if next_section is None:
        return ""

    cells = section.get("cells", [])
    end_pos = section.get("end_pos", "")
    end_cell = next((c for c in cells if c.get("pos") == end_pos), None)
    if not end_cell:
        return ""

    # warp_edge is the primary source
    warp_edge = end_cell.get("warp_edge", "")
    if warp_edge:
        return warp_edge

    # Fall back to unconnected portals
    unconnected = get_unconnected_portals(end_cell)
    entry_dir = section.get("entry_direction", "")
    candidates = [d for d in unconnected if d != entry_dir]

    if len(candidates) == 1:
        return candidates[0]

    # Use opposite of next section's entry
    next_entry = next_section.get("entry_direction", "")
    if next_entry and OPPOSITE.get(next_entry) in candidates:
        return OPPOSITE[next_entry]

    return candidates[0] if candidates else ""


def fix_quest(path: Path) -> bool:
    """Fix entry/exit directions in a quest file. Returns True if modified."""
    with open(path) as f:
        quest = json.load(f)

    sections = quest.get("sections", [])
    if not sections:
        return False

    modified = False

    # Two passes: first compute exits (which depend on warp_edge),
    # then entries (which can use previous section's exit)
    for i, sec in enumerate(sections):
        next_sec = sections[i + 1] if i + 1 < len(sections) else None
        exit_dir = compute_exit_direction(sec, next_sec)
        if exit_dir and sec.get("exit_direction", "") != exit_dir:
            sec["exit_direction"] = exit_dir
            modified = True

    for i, sec in enumerate(sections):
        prev_sec = sections[i - 1] if i > 0 else None
        entry_dir = compute_entry_direction(sec, prev_sec)
        if entry_dir and sec.get("entry_direction", "") != entry_dir:
            sec["entry_direction"] = entry_dir
            modified = True

    if modified:
        with open(path, "w") as f:
            json.dump(quest, f, indent=2, ensure_ascii=False)
            f.write("\n")
        return True
    return False


def main():
    quest_files = sorted(QUEST_DIR.glob("*.json"))
    quest_files = [f for f in quest_files if f.name != "manifest.json"]

    total = 0
    fixed = 0
    for qf in quest_files:
        total += 1
        try:
            if fix_quest(qf):
                fixed += 1
                print(f"  FIXED: {qf.name}")
                # Print the directions
                with open(qf) as f:
                    q = json.load(f)
                for i, sec in enumerate(q.get("sections", [])):
                    entry = sec.get("entry_direction", "")
                    exit_ = sec.get("exit_direction", "")
                    area = sec.get("area", "?")
                    stype = sec.get("type", "?")
                    if entry or exit_:
                        print(f"    section {i} ({stype}, {area}): entry={entry or '-'} exit={exit_ or '-'}")
            else:
                print(f"  OK:    {qf.name}")
        except Exception as e:
            print(f"  ERROR: {qf.name}: {e}")

    print(f"\n{fixed}/{total} quest files updated.")


if __name__ == "__main__":
    main()
