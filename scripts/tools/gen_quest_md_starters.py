#!/usr/bin/env python3
"""Generate starter docs/quests/<id>.md files from data/quests/<id>.json.

For the 6 alpha quests we're designing right now. The output is a workspace
template — fills in everything the JSON already knows (briefing, companions,
office NPCs, objectives, section layout) and leaves TODO placeholders for
the parts the human still has to design (per-section dialog, lore beats,
boss-fight specifics).

Not a CI tool; run once when seeding a new quest doc.
"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
QUESTS_DIR = REPO / "data" / "quests"
DOCS_DIR = REPO / "docs" / "quests"

QUEST_IDS = [
    "finding_ogi",
    "investigate_tower",
    "heretic",
    "control_system",
    "the_broken_seal",
    "dark_castle",
]


def format_section(idx: int, sec: dict) -> str:
    area = sec.get("area", "?")
    stype = sec.get("type", "?")
    cells = sec.get("cells", [])
    start = sec.get("start_pos", "-")
    end = sec.get("end_pos", "-")
    entry = sec.get("entry_direction", "")
    exit_d = sec.get("exit_direction", "")
    stages = sorted({c.get("stage_id", "") for c in cells if c.get("stage_id")})
    parts = [
        f"### Section {idx} — `{area}` ({stype})",
        "",
        f"- **Cells:** {len(cells)} · start `{start}` → end `{end}`",
    ]
    if entry or exit_d:
        parts.append(f"- **Entry/exit:** {entry or '-'} / {exit_d or '-'}")
    if stages:
        parts.append(f"- **Stages used:** {', '.join(f'`{s}`' for s in stages)}")
    parts.append("")
    parts.append("**TODO** — design notes for this section: enemy mix, key gates,"
                 " pickup/log placements, companion banter beats.")
    return "\n".join(parts)


def build_md(q: dict) -> str:
    qid = q["id"]
    name = q["name"]
    desc = q.get("description", "")
    area_id = q.get("area_id", "?")
    sections = q.get("sections", [])
    companions = q.get("companions", []) or []
    office = q.get("office_npcs", []) or []
    objectives = q.get("objectives", []) or []
    briefing = q.get("briefing_dialog", []) or []

    section_summary = " → ".join(f"{s.get('area','?').upper()}({s.get('type','?')})" for s in sections)
    office_str = ", ".join(f"{n['npc_name']} ({n['office_position']})" for n in office) or "—"
    companion_str = ", ".join(f"`{c}`" for c in companions) or "_none_"

    is_boss_kill = any("Defeat" in (o.get("label") or "") for o in objectives)
    is_pickup = not is_boss_kill and bool(objectives)
    is_reach = not objectives

    lines = []
    lines.append(f"# {name} — Quest Flow")
    lines.append("")
    lines.append("## Overview")
    lines.append("")
    lines.append(f"**Location:** {area_id} | **Sections:** {len(sections)} ({section_summary})  ")
    lines.append(f"**Companion:** {companion_str} | **Office NPCs:** {office_str}")
    lines.append("")
    lines.append(f"_{desc}_")
    lines.append("")
    lines.append("**TODO** — one-paragraph concept: what is the player here for, why does it matter,"
                 " what does the player learn or feel by the end.")
    lines.append("")

    # Objective
    lines.append("## Objective")
    lines.append("")
    if is_pickup:
        lines.append(f"Collect {len(objectives)} quest item{'s' if len(objectives)!=1 else ''}:")
        lines.append("")
        lines.append("| # | item_id | Label | Target |")
        lines.append("|---|---|---|---|")
        for i, o in enumerate(objectives, 1):
            lines.append(f"| {i} | `{o['item_id']}` | {o['label']} | {o['target']} |")
        lines.append("")
        lines.append("**TODO** — pickup placements (section, cell), per-item reaction dialog from the"
                     " companion, and remaining-count banter pattern.")
    elif is_boss_kill:
        o = objectives[0]
        lines.append(f"Defeat the boss: `{o['item_id']}` ({o['label']}, target {o['target']}).")
        lines.append("")
        lines.append("**TODO** — boss-fight beats: HP/behavior placeholder vs. real AI, boss intro line,"
                     " death line, on-clear telepipe/warp behavior. Note: boss `.tres` may still need to"
                     " be authored if this is a placeholder ID.")
    elif is_reach:
        lines.append("Reach the boss room (no enemy kill required). Section Z's start cell is the goal.")
        lines.append("")
        lines.append("**TODO** — what happens when the player arrives — cutscene, dialog, "
                     "transition to a follow-up quest, etc.")
    lines.append("")

    # Briefing
    lines.append("## Briefing (Office)")
    lines.append("")
    lines.append(f"Office NPCs: {office_str}.")
    lines.append("")
    if briefing:
        for line in briefing:
            speaker = line.get("speaker", "?")
            text = line.get("text", "")
            lines.append(f"> **{speaker}:** {text}")
            lines.append(">")
        # strip trailing empty quote
        while lines and lines[-1] == ">":
            lines.pop()
    else:
        lines.append("_no briefing dialog yet_")
    lines.append("")
    lines.append("**TODO** — confirm the opening dialog is right, or rewrite. Each line corresponds to"
                 " one `briefing_dialog` entry in the JSON.")
    lines.append("")

    # Companion notes
    lines.append("## Companion")
    lines.append("")
    if companions:
        lines.append(f"Companion: {companion_str}.")
    else:
        lines.append("No companion.")
    lines.append("")
    lines.append("**TODO** — companion's voice/role for this quest: what do they comment on, when, why."
                 " Specific lines for: entering each section, mid-section beats, objective-progress callouts,"
                 " final reaction on clear.")
    lines.append("")

    # Sections
    lines.append("## Sections")
    lines.append("")
    if sections:
        for i, s in enumerate(sections):
            lines.append(format_section(i, s))
            lines.append("")
    else:
        lines.append("_no sections yet_")
        lines.append("")

    # Flow mermaid stub
    lines.append("## Quest Flow")
    lines.append("")
    lines.append("**TODO** — flesh out into a mermaid diagram once dialog beats are set."
                 " See `apothecary_supply.md` for the convention.")
    lines.append("")
    lines.append("```mermaid")
    lines.append("flowchart TD")
    lines.append("    BRIEF[Briefing] --> START[Enter quest area]")
    nodes = ["START"]
    for i, s in enumerate(sections):
        node = f"SEC{i}"
        label = f"Section {i} ({s.get('area','?').upper()})"
        lines.append(f"    {nodes[-1]} --> {node}[{label}]")
        nodes.append(node)
    lines.append(f"    {nodes[-1]} --> END[Quest complete]")
    lines.append("```")
    lines.append("")

    return "\n".join(lines)


def main():
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    for qid in QUEST_IDS:
        src = QUESTS_DIR / f"{qid}.json"
        if not src.exists():
            print(f"  skip {qid}: no JSON")
            continue
        out = DOCS_DIR / f"{qid}.md"
        if out.exists():
            print(f"  skip {qid}: {out} already exists")
            continue
        q = json.loads(src.read_text())
        out.write_text(build_md(q))
        print(f"  wrote {out.relative_to(REPO)}")


if __name__ == "__main__":
    main()
