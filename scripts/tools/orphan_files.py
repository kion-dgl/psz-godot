#!/usr/bin/env python3
"""orphan_files.py — flag committed .gd / .tscn files that nothing references.

Complements the existing checks:
  • check-asset-refs verifies the FORWARD direction — that res:// paths named
    in source actually exist.
  • code_graph.py finds dead FUNCTIONS.
This catches the REVERSE direction at FILE granularity: a committed script or
scene that no other file points to — an orphan that should move to /archive/
(see CLAUDE.md) rather than linger.

A candidate (.gd or .tscn) is an ORPHAN when NOTHING references it:
  • its res:// path appears in no OTHER committed text file (no .tscn
    ext_resource, no preload/load/change_scene_to_file, not project.godot's
    main_scene / [autoload], not a CI yml / shell script), AND
  • if it is a .gd declaring `class_name X`, the identifier X is used in no
    OTHER .gd file, AND
  • it is not a hard entry-point root (main scene, an autoload, the test
    runner) — those are "referenced" only by the engine.

Scope: .tres data resources are NOT candidates — registries load them by
directory scan (no explicit path), so they'd all false-positive. We DO read
.tres for references, so a script used as a custom Resource isn't flagged.

Usage:
  orphan_files.py                 # human report of current orphans
  orphan_files.py --check         # CI gate: exit 1 on NEW orphans vs baseline
  orphan_files.py --update-baseline
"""
from __future__ import annotations
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).resolve().parent / "orphan_baseline.json"

# Directories excluded from BOTH candidate and reference scanning.
EXCLUDE_PREFIXES = ("addons/", "archive/", "web/dist/")

# Candidate file types — reliably referenced by explicit path / class_name.
CANDIDATE_EXTS = (".gd", ".tscn")

# Extensions worth reading for references (text formats that can name a res://
# path or, for .gd, use a class_name identifier).
TEXT_EXTS = (
    ".gd", ".tscn", ".tres", ".godot", ".cfg", ".import", ".uid",
    ".sh", ".yml", ".yaml", ".md", ".ts", ".tsx", ".js", ".json", ".txt",
)

RES_PATH_RE = re.compile(r"res://[A-Za-z0-9_./\-]+")
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_]\w*)", re.MULTILINE)
WORD_RE = re.compile(r"[A-Za-z_]\w*")


def git_files() -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [p for p in out.splitlines() if not p.startswith(EXCLUDE_PREFIXES)]


def read(rel: str) -> str:
    try:
        return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
    except (OSError, UnicodeError):
        return ""


def autoload_paths(project_godot: str) -> set[str]:
    """res:// script paths registered as autoloads (engine-referenced roots)."""
    roots: set[str] = set()
    in_section = False
    for line in project_godot.splitlines():
        if line.strip() == "[autoload]":
            in_section = True
            continue
        if line.startswith("[") and line.strip() != "[autoload]":
            in_section = False
        if in_section:
            m = re.search(r'res://[A-Za-z0-9_./\-]+', line)
            if m:
                roots.add(m.group(0))
    return roots


def main_scene(project_godot: str) -> set[str]:
    m = re.search(r'run/main_scene="(res://[^"]+)"', project_godot)
    return {m.group(1)} if m else set()


def analyze() -> list[dict]:
    files = git_files()
    text: dict[str, str] = {f: read(f) for f in files if f.endswith(TEXT_EXTS)}

    project = text.get("project.godot", "")
    # Engine-referenced roots: never named by another file's preload/instance.
    roots = autoload_paths(project) | main_scene(project) | {
        "res://scripts/tools/test_runner.tscn",
        "res://scripts/tools/test_runner.gd",
    }

    # path -> set of files that mention it (any text file).
    path_mentions: dict[str, set[str]] = {}
    for f, body in text.items():
        for p in RES_PATH_RE.findall(body):
            path_mentions.setdefault(p, set()).add(f)

    # class_name -> file that declares it; and per-.gd word sets for usage.
    gd_files = [f for f in text if f.endswith(".gd")]
    gd_words: dict[str, set[str]] = {f: set(WORD_RE.findall(text[f])) for f in gd_files}
    declares: dict[str, str] = {}  # file -> class_name
    for f in gd_files:
        m = CLASS_NAME_RE.search(text[f])
        if m:
            declares[f] = m.group(1)

    candidates = sorted(
        f for f in files
        if f.endswith(CANDIDATE_EXTS) and not f.startswith(EXCLUDE_PREFIXES)
    )

    orphans: list[dict] = []
    for f in candidates:
        res = "res://" + f
        if res in roots:
            continue
        # Referenced by path from any OTHER file?
        if path_mentions.get(res, set()) - {f}:
            continue
        # If it exports a class_name, is that name used in any OTHER .gd?
        cn = declares.get(f)
        if cn and any(cn in gd_words[o] for o in gd_files if o != f):
            continue
        orphans.append({"file": f, "class_name": cn or ""})

    orphans.sort(key=lambda d: d["file"])
    return orphans


def load_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    return set(json.loads(BASELINE.read_text()).get("accepted_orphans", []))


def main() -> int:
    args = sys.argv[1:]
    orphans = analyze()
    names = [o["file"] for o in orphans]

    if "--update-baseline" in args:
        BASELINE.write_text(json.dumps({
            "_comment": (
                "Accepted orphan files — committed .gd/.tscn referenced nowhere "
                "(by path, class_name, autoload, or main scene). Triage before "
                "deleting; move true orphans to /archive/ (CLAUDE.md). --check "
                "fails on any orphan NOT listed here. Regenerate after cleanup."
            ),
            "accepted_orphans": names,
        }, indent=2) + "\n")
        print(f"[orphan-files] baseline written: {len(names)} accepted orphan(s).")
        return 0

    if "--check" in args:
        baseline = load_baseline()
        new = [n for n in names if n not in baseline]
        stale = [n for n in baseline if n not in names]
        if stale:
            print(f"[orphan-files] note: {len(stale)} baselined file(s) no longer "
                  f"orphan (cleaned up?) — run --update-baseline to shrink:")
            for n in stale:
                print(f"    {n}")
        if new:
            print("::error::new orphan file(s) — referenced by no .gd/.tscn/.tres/"
                  "autoload/main-scene. Move to /archive/ (CLAUDE.md), wire it up, "
                  "or accept with --update-baseline:")
            for n in new:
                print(f"    {n}")
            return 1
        print(f"[orphan-files] {len(names)} orphan(s), all baselined — no new ✓")
        return 0

    # Default: human report.
    print(f"[orphan-files] {len(orphans)} orphan candidate(s) "
          f"(.gd/.tscn referenced nowhere):")
    for o in orphans:
        tag = f"  [class_name {o['class_name']}]" if o["class_name"] else ""
        print(f"    {o['file']}{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
