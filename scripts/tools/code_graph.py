#!/usr/bin/env python3
"""Self-contained GDScript code-health graph + ratchets.

Builds a lightweight *function-level graph* from scripts/**/*.gd using only the
stdlib — so it rebuilds deterministically in CI every PR (never goes stale) and
needs no MCP and no `pip install`. The codebase-memory MCP stays the rich
dev-time explorer; this is the CI gate. EPIC #295.

Checks (each ratcheted against a committed baseline — fail on NEW only, so the
existing backlog never blocks a PR):
  • DUPLICATION (#294): near-duplicate functions via normalized-token Jaccard.
  • DEAD CODE: functions whose name is referenced nowhere else across all
    .gd + .tscn (scenes wire signal handlers by name), minus engine virtuals.

Usage:
  code_graph.py --check             # CI: exit 1 on NEW duplication OR dead code
  code_graph.py --update-baseline   # rewrite both baselines (after cleanup/accept)
  code_graph.py --report            # near-duplicate pairs
  code_graph.py --report-dead       # dead-code candidates
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_GLOB = "scripts/**/*.gd"
TOOLS = Path(__file__).resolve().parent
DUP_BASELINE = TOOLS / "code_dup_baseline.json"
DEAD_BASELINE = TOOLS / "code_dead_baseline.json"

# Duplication tuning. JACCARD_MIN matches the MCP SIMILAR_TO threshold that
# produced #294; MIN_TOKENS skips trivial functions; SIZE_RATIO prunes pairs of
# very different length cheaply.
JACCARD_MIN = 0.85
MIN_TOKENS = 20
SIZE_RATIO = 0.6

# Engine-invoked callbacks: never referenced by name in source, but NOT dead.
GODOT_VIRTUALS = {
    "_ready", "_enter_tree", "_exit_tree", "_process", "_physics_process",
    "_input", "_unhandled_input", "_unhandled_key_input", "_shortcut_input",
    "_gui_input", "_draw", "_init", "_notification", "_to_string", "_get",
    "_set", "_get_property_list", "_property_can_revert", "_property_get_revert",
    "_validate_property", "_get_configuration_warnings", "_input_event",
    "_can_drop_data", "_drop_data", "_get_drag_data", "_make_custom_tooltip",
    "_integrate_forces", "_iter_init", "_iter_next", "_iter_get",
}

_FUNC_RE = re.compile(r"^([ \t]*)(?:static\s+)?func\s+([A-Za-z_]\w*)")
_INDENT_RE = re.compile(r"^[ \t]*")
# identifiers OR single non-space symbols — coarse but stable token stream
_TOKEN_RE = re.compile(r"[A-Za-z_]\w*|[^\sA-Za-z_]")
_WORD_RE = re.compile(r"[A-Za-z_]\w*")


def _indent_width(line: str) -> int:
    return len(_INDENT_RE.match(line).group(0).expandtabs())


def _strip_strings_and_comments(src: str) -> str:
    # strings FIRST — a `#` inside a literal (e.g. SVG color "#2a2a4e") is NOT a
    # comment. Triple-quoted before single so the inner quotes don't mis-split.
    src = re.sub(r'"""[\s\S]*?"""', '""', src)
    src = re.sub(r"'''[\s\S]*?'''", "''", src)
    src = re.sub(r'"[^"\n]*"', '""', src)
    src = re.sub(r"'[^'\n]*'", "''", src)
    src = re.sub(r"#.*", "", src)
    return src


def _tokenize(src: str) -> set[str]:
    return set(_TOKEN_RE.findall(_strip_strings_and_comments(src)))


def extract_functions(path: Path) -> list[dict]:
    """Return [{name, qn, file, line, tokens}] per func, body by indentation."""
    rel = path.relative_to(ROOT).as_posix()
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    out: list[dict] = []
    name_seen: dict[str, int] = {}  # per-file occurrence index for same-named funcs
    i, n = 0, len(lines)
    while i < n:
        m = _FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        head_indent = _indent_width(m.group(1))
        name = m.group(2)
        occ = name_seen.get(name, 0)
        name_seen[name] = occ + 1
        body = [lines[i]]
        j = i + 1
        while j < n:
            ln = lines[j]
            if ln.strip() == "":
                body.append(ln)
                j += 1
                continue
            if _indent_width(ln) <= head_indent:
                break
            body.append(ln)
            j += 1
        out.append({
            "name": name,
            # Occurrence-indexed (NOT line-numbered): this both disambiguates
            # same-named funcs in one file AND keeps the id stable when unrelated
            # lines shift above the function (line numbers would not).
            "qn": f"{rel}:{name}#{occ}",
            "file": rel,
            "line": i + 1,  # metadata for reporting only
            "tokens": _tokenize("\n".join(body)),
        })
        i = j
    return out


def build_graph() -> list[dict]:
    funcs: list[dict] = []
    for p in sorted(ROOT.glob(SRC_GLOB)):
        funcs.extend(extract_functions(p))
    return funcs


# ── duplication ────────────────────────────────────────────────────────────

def find_duplicate_pairs(funcs: list[dict]) -> list[dict]:
    big = [f for f in funcs if len(f["tokens"]) >= MIN_TOKENS]
    pairs: list[dict] = []
    for a, b in combinations(big, 2):
        ta, tb = a["tokens"], b["tokens"]
        if min(len(ta), len(tb)) < SIZE_RATIO * max(len(ta), len(tb)):
            continue
        inter = len(ta & tb)
        if inter == 0:
            continue
        jac = inter / len(ta | tb)
        if jac >= JACCARD_MIN:
            pairs.append({
                "a": a["qn"], "b": b["qn"], "jaccard": round(jac, 3),
                "sig": "||".join(sorted((a["qn"], b["qn"]))),
            })
    pairs.sort(key=lambda p: (-p["jaccard"], p["sig"]))
    return pairs


# ── dead code ────────────────────────────────────────────────────────────────

def _iter_ref_files():
    """All .gd + .tscn that may *reference* a function by name (calls, Callables,
    string invokes, and scene [connection] method="…"). Skip generated/vendored."""
    for ext in ("gd", "tscn"):
        for p in ROOT.glob(f"**/*.{ext}"):
            rel = p.relative_to(ROOT).as_posix()
            if rel.startswith((".godot/", "archive/", "addons/")):
                continue
            yield p


def build_reference_counts() -> Counter:
    """Count every identifier occurrence across source + scenes (incl. strings
    and comments — conservative: a name mentioned anywhere counts as 'used')."""
    counts: Counter = Counter()
    for p in _iter_ref_files():
        try:
            counts.update(_WORD_RE.findall(p.read_text(encoding="utf-8", errors="replace")))
        except OSError:
            continue
    return counts


def find_dead_functions(funcs: list[dict]) -> list[dict]:
    ref_counts = build_reference_counts()
    def_counts = Counter(f["name"] for f in funcs)
    dead: list[dict] = []
    for f in funcs:
        name = f["name"]
        # virtuals are engine-invoked; test_* are run by the test_runner via reflection
        if name in GODOT_VIRTUALS or name.startswith("test_"):
            continue
        # uses beyond the definition lines themselves
        uses = ref_counts.get(name, 0) - def_counts.get(name, 0)
        if uses <= 0:
            dead.append({"qn": f["qn"], "name": name, "file": f["file"], "line": f["line"]})
    dead.sort(key=lambda d: d["qn"])
    return dead


# ── baselines ────────────────────────────────────────────────────────────────

def _load_sigs(path: Path, key: str) -> set[str]:
    if not path.exists():
        return set()
    return {e if isinstance(e, str) else e["sig"]
            for e in json.loads(path.read_text()).get(key, [])}


def write_baselines(pairs: list[dict], dead: list[dict]) -> None:
    DUP_BASELINE.write_text(json.dumps({
        "_comment": ("Accepted near-duplicate function pairs (EPIC #295). "
                     "code_graph.py --check fails on any pair NOT here. Run "
                     "--update-baseline to regenerate this — both after deduping "
                     "(#294) AND to consciously accept a new intentional pair."),
        "jaccard_min": JACCARD_MIN,
        "accepted_pairs": [{"sig": p["sig"], "jaccard": p["jaccard"]} for p in pairs],
    }, indent=2) + "\n")
    DEAD_BASELINE.write_text(json.dumps({
        "_comment": ("Accepted dead-code candidates — functions referenced "
                     "nowhere else across .gd + .tscn (EPIC #295). Conservative "
                     "(name-based), so triage before deleting. --check fails on "
                     "any candidate NOT here; --update-baseline after cleanup."),
        "accepted_dead": [d["qn"] for d in dead],
    }, indent=2) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true",
                   help="CI gate: exit 1 on NEW duplication or dead code")
    g.add_argument("--update-baseline", action="store_true",
                   help="rewrite both baselines (after cleanup, or to accept new findings)")
    g.add_argument("--report", action="store_true",
                   help="list all near-duplicate function pairs")
    g.add_argument("--report-dead", action="store_true",
                   help="list all dead-code candidates")
    args = ap.parse_args()

    funcs = build_graph()

    if args.report:
        pairs = find_duplicate_pairs(funcs)
        print(f"[code-graph] {len(funcs)} functions, {len(pairs)} near-dup pairs "
              f"(jaccard >= {JACCARD_MIN}):")
        for p in pairs:
            print(f"  {p['jaccard']:.2f}  {p['a']}  ~  {p['b']}")
        return 0

    if args.report_dead:
        dead = find_dead_functions(funcs)
        print(f"[code-graph] {len(funcs)} functions, {len(dead)} dead-code "
              f"candidates (referenced nowhere else in .gd/.tscn):")
        for d in dead:
            print(f"  {d['file']}:{d['line']}  {d['name']}()")
        return 0

    if args.update_baseline:
        pairs = find_duplicate_pairs(funcs)
        dead = find_dead_functions(funcs)
        write_baselines(pairs, dead)
        print(f"[code-graph] baselines written: {len(pairs)} dup pairs, "
              f"{len(dead)} dead candidates.")
        return 0

    # --check (ratchet both)
    pairs = find_duplicate_pairs(funcs)
    dead = find_dead_functions(funcs)
    dup_base = _load_sigs(DUP_BASELINE, "accepted_pairs")
    dead_base = _load_sigs(DEAD_BASELINE, "accepted_dead")
    new_dup = [p for p in pairs if p["sig"] not in dup_base]
    new_dead = [d for d in dead if d["qn"] not in dead_base]

    print(f"[code-graph] {len(funcs)} functions | dup: {len(pairs)} pairs "
          f"({len(new_dup)} new) | dead: {len(dead)} candidates ({len(new_dead)} new)")
    rc = 0
    if new_dup:
        print("::error::new duplicate function pair(s) — extract a shared helper "
              "or accept with --update-baseline (EPIC #295 / #294):")
        for p in new_dup:
            print(f"  jaccard={p['jaccard']:.2f}  {p['a']}  ~  {p['b']}")
        rc = 1
    if new_dead:
        print("::error::new dead-code — function referenced nowhere else "
              "(.gd/.tscn). Remove it, or accept with --update-baseline:")
        for d in new_dead:
            print(f"  {d['file']}:{d['line']}  {d['name']}()")
        rc = 1
    if rc == 0:
        print("[code-graph] no new duplication or dead code ✓")
    return rc


if __name__ == "__main__":
    sys.exit(main())
