#!/usr/bin/env python3
"""Baseline-debt guard (Beta working agreement).

The code_graph ratchet blocks NEW debt unless the baseline is regenerated —
which makes accepting debt possible but silent. This guard makes it LOUD:
if a PR *increases* any accepted-debt count (dup pairs, dead code, complexity,
coupling), the PR's commits must carry an explicit `Debt-Accepted: <reason>`
trailer acknowledging it. Decreases are wins and pass silently.

Per the Beta agreement, deliberate one-off debt belongs at the END of beta;
a mid-beta increase should prompt "why are we doing this now?".

Usage (CI):  BASE_REF=origin/main python3 scripts/tools/check_baseline_debt.py
Usage (dev): python3 scripts/tools/check_baseline_debt.py [base-ref]
"""
import json
import os
import subprocess
import sys

BASELINES = {
    "dup pairs": ("scripts/tools/code_dup_baseline.json", "accepted_pairs"),
    "dead code": ("scripts/tools/code_dead_baseline.json", "accepted_dead"),
    "complexity": ("scripts/tools/code_complexity_baseline.json", "accepted_complex"),
    "coupling": ("scripts/tools/code_coupling_baseline.json", "accepted_coupling"),
}


def count_at(ref: str, path: str, key: str) -> int:
    if ref is None:
        data = json.load(open(path))
    else:
        out = subprocess.run(
            ["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
        if out.returncode != 0:
            return -1  # file absent at base — treat as no-baseline, skip
        data = json.loads(out.stdout)
    return len(data.get(key, []))


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("BASE_REF", "origin/main")
    increases = []
    for name, (path, key) in BASELINES.items():
        base_n = count_at(base, path, key)
        head_n = count_at(None, path, key)
        if base_n < 0:
            continue
        if head_n > base_n:
            increases.append((name, base_n, head_n))
        elif head_n < base_n:
            print(f"[baseline-debt] {name}: {base_n} -> {head_n} (improvement)")

    if not increases:
        print("[baseline-debt] no accepted-debt increases vs", base, "✓")
        return 0

    log = subprocess.run(
        ["git", "log", f"{base}..HEAD", "--format=%B"],
        capture_output=True, text=True).stdout
    acknowledged = "Debt-Accepted:" in log

    for name, b, h in increases:
        print(f"[baseline-debt] {name}: {b} -> {h} (INCREASE)")

    if acknowledged:
        for line in log.splitlines():
            if line.strip().startswith("Debt-Accepted:"):
                print(f"[baseline-debt] acknowledged: {line.strip()}")
        print("[baseline-debt] debt increase explicitly acknowledged ✓")
        return 0

    print("::error::Baseline debt increased without acknowledgment.")
    print("This PR grows an accepted-debt baseline. Per the Beta working")
    print("agreement, deliberate debt belongs at the END of beta — if this")
    print("increase is intentional, ask yourselves why it's needed now, then")
    print("add a commit-message trailer:  Debt-Accepted: <one-line reason>")
    return 1


if __name__ == "__main__":
    sys.exit(main())
