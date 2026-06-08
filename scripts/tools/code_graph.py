#!/usr/bin/env python3
"""Self-contained GDScript code-health graph + duplication ratchet.

Builds a lightweight *function-level graph* from scripts/**/*.gd using only the
stdlib — so it rebuilds deterministically in CI every PR (never goes stale) and
needs no MCP and no `pip install`. The codebase-memory MCP stays the rich
dev-time explorer; this is the CI gate.

Increment 1 (EPIC #295): DUPLICATION. Near-duplicate functions are detected via
normalized-token Jaccard and ratcheted against a committed baseline — the PR
fails only on *new* duplication, so the existing backlog (#294) never blocks.
Dead-code (CALLS edges) and coupling extend the same graph in later increments.

Usage:
  code_graph.py --check             # CI: exit 1 on NEW duplicate clusters
  code_graph.py --update-baseline   # rewrite the baseline (after cleanup/accept)
  code_graph.py --report            # human-readable cluster list (no exit code)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_GLOB = "scripts/**/*.gd"
BASELINE = Path(__file__).resolve().parent / "code_dup_baseline.json"

# Tuning. JACCARD_MIN matches the MCP's SIMILAR_TO threshold that produced #294;
# MIN_TOKENS skips trivial functions (getters, one-liners) where shared vocab
# trivially overlaps; SIZE_RATIO prunes pairs of very different length cheaply.
JACCARD_MIN = 0.85
MIN_TOKENS = 20
SIZE_RATIO = 0.6

_FUNC_RE = re.compile(r"^([ \t]*)(?:static\s+)?func\s+([A-Za-z_]\w*)")
_INDENT_RE = re.compile(r"^[ \t]*")
# identifiers OR single non-space symbols — a coarse but stable token stream
_TOKEN_RE = re.compile(r"[A-Za-z_]\w*|[^\sA-Za-z_]")


def _indent_width(line: str) -> int:
    return len(_INDENT_RE.match(line).group(0).expandtabs())


def _tokenize(src: str) -> set[str]:
    src = re.sub(r"#.*", "", src)            # comments
    src = re.sub(r'"[^"\n]*"', '""', src)    # string contents → placeholder
    src = re.sub(r"'[^'\n]*'", "''", src)
    return set(_TOKEN_RE.findall(src))


def extract_functions(path: Path) -> list[dict]:
    """Return [{name, qn, file, line, tokens}] for each func, body by indentation."""
    rel = path.relative_to(ROOT).as_posix()
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    out: list[dict] = []
    i, n = 0, len(lines)
    while i < n:
        m = _FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        head_indent = _indent_width(m.group(1))
        name = m.group(2)
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
            "qn": f"{rel}:{name}",
            "file": rel,
            "line": i + 1,
            "tokens": _tokenize("\n".join(body)),
        })
        i = j
    return out


def build_graph() -> list[dict]:
    funcs: list[dict] = []
    for p in sorted(ROOT.glob(SRC_GLOB)):
        funcs.extend(extract_functions(p))
    return [f for f in funcs if len(f["tokens"]) >= MIN_TOKENS]


def find_duplicate_pairs(funcs: list[dict]) -> list[dict]:
    """Near-duplicate function pairs (normalized-token Jaccard >= JACCARD_MIN)."""
    pairs: list[dict] = []
    for a, b in combinations(funcs, 2):
        ta, tb = a["tokens"], b["tokens"]
        # cheap size prune before the set ops
        if min(len(ta), len(tb)) < SIZE_RATIO * max(len(ta), len(tb)):
            continue
        inter = len(ta & tb)
        if inter == 0:
            continue
        jac = inter / len(ta | tb)
        if jac >= JACCARD_MIN:
            pairs.append({
                "a": a["qn"], "b": b["qn"],
                "jaccard": round(jac, 3),
                "sig": _sig(a["qn"], b["qn"]),
            })
    pairs.sort(key=lambda p: (-p["jaccard"], p["sig"]))
    return pairs


def _sig(qn_a: str, qn_b: str) -> str:
    """Order-independent stable signature for a pair (survives a/b swap)."""
    return "||".join(sorted((qn_a, qn_b)))


def load_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    data = json.loads(BASELINE.read_text())
    return {e["sig"] for e in data.get("accepted_pairs", [])}


def write_baseline(pairs: list[dict]) -> None:
    payload = {
        "_comment": (
            "Accepted near-duplicate function pairs (EPIC #295, increment 1). "
            "code_graph.py --check fails on any pair NOT listed here. Regenerate "
            "with `python3 scripts/tools/code_graph.py --update-baseline` after "
            "deduping (#294) or after consciously accepting a new pair."
        ),
        "jaccard_min": JACCARD_MIN,
        "accepted_pairs": [
            {"sig": p["sig"], "jaccard": p["jaccard"]} for p in pairs
        ],
    }
    BASELINE.write_text(json.dumps(payload, indent=2) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true", help="fail on new dup clusters")
    g.add_argument("--update-baseline", action="store_true", help="rewrite baseline")
    g.add_argument("--report", action="store_true", help="list all dup pairs")
    args = ap.parse_args()

    funcs = build_graph()
    pairs = find_duplicate_pairs(funcs)

    if args.report:
        print(f"[code-graph] {len(funcs)} functions (>= {MIN_TOKENS} tokens), "
              f"{len(pairs)} near-duplicate pairs (jaccard >= {JACCARD_MIN}):")
        for p in pairs:
            print(f"  {p['jaccard']:.2f}  {p['a']}  ~  {p['b']}")
        return 0

    if args.update_baseline:
        write_baseline(pairs)
        print(f"[code-graph] baseline written: {len(pairs)} accepted pairs → "
              f"{BASELINE.relative_to(ROOT)}")
        return 0

    # --check (ratchet)
    baseline = load_baseline()
    new = [p for p in pairs if p["sig"] not in baseline]
    stale = baseline - {p["sig"] for p in pairs}
    print(f"[code-graph] {len(funcs)} functions, {len(pairs)} dup pairs "
          f"({len(baseline)} baselined, {len(new)} new)")
    if stale:
        print(f"[code-graph] note: {len(stale)} baselined pair(s) no longer "
              f"duplicate (dedup progress — run --update-baseline to prune).")
    if new:
        print("::error::new duplicate function pair(s) — extract a shared "
              "helper, or accept with --update-baseline (see EPIC #295 / #294):")
        for p in new:
            print(f"  jaccard={p['jaccard']:.2f}  {p['a']}  ~  {p['b']}")
        return 1
    print("[code-graph] no new duplication ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
