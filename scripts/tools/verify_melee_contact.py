#!/usr/bin/env python3
"""Verify #554 in Godot, with disposable saves and machine-readable results.

Requires locally imported game assets for the live Coliseum layer. Unit tests
remain registered in test_runner for asset-independent CI. --calibrate also
proves the live oracle rejects the old single-sample bug and repeated contacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run_probe(godot, project, scene, output, name, env):
    command = [godot, "--headless", "--fixed-fps", "60", "--path", str(project), scene]
    log = output / f"{name}.log"
    timed_out = False
    with log.open("w") as stream:
        try:
            proc = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code, timed_out = -1, True
    text = log.read_text(errors="replace")
    rows = [json.loads(line.split("RESULT ", 1)[1]) for line in text.splitlines()
            if line.startswith("[melee-live] RESULT ")]
    errors = "SCRIPT ERROR" in text or "Warning treated as error" in text
    if name == "unit":
        match = re.search(r"RESULTS: (\d+) passed, (\d+) failed", text)
        complete = bool(match and int(match[2]) == 0)
    else:
        expected = {(w, m) for w in ("saber", "sword", "daggers")
                    for m in ("early_only", "late_entry", "after_close", "interrupt", "combo")}
        complete = (len(rows) == 15 and {(r["weapon"], r["mode"]) for r in rows} == expected
                    and all(r["passed"] for r in rows) and "[coliseum] DONE ok" in text)
    return {"passed": code == 0 and not errors and complete, "exit_code": code,
            "script_errors": errors, "timed_out": timed_out, "log": str(log), "cases": rows}


def prepare_project(project):
    # Shared imports/assets, private scripts for mutation calibration; no source edits.
    for child in ROOT.iterdir():
        if child.name in {".git", "scripts", "project.godot", "node_modules"}:
            continue
        (project / child.name).symlink_to(child, target_is_directory=child.is_dir())
    shutil.copytree(ROOT / "scripts", project / "scripts",
                    ignore=shutil.ignore_patterns("node_modules", "__pycache__"))
    config = (ROOT / "project.godot").read_text()
    # Godot can use an absolute custom user directory; it is removed with the project.
    config = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir)=.*\n', '', config, flags=re.M)
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
                            + 'config/custom_user_dir=' + json.dumps(str(project / 'user-data')))
    (project / "project.godot").write_text(config)


def check_references(args):
    evidence = json.loads((ROOT / "data/re_reference/melee_contact_evidence.json").read_text())
    results = {}
    for name in ("psz_re", "pszm_decomp"):
        path = getattr(args, name)
        if path is None:
            results[name] = {"checked": False, "reason": "checkout not supplied; pinned evidence retained"}
            continue
        source = evidence["sources"][name]
        actual = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
        files_ok = all((path / file).is_file() and hashlib.sha256((path / file).read_bytes()).hexdigest() == digest
                       for file, digest in source["files"].items())
        results[name] = {"checked": True, "revision": actual, "passed": actual == source["revision"] and files_ok}
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--psz-re", type=Path)
    parser.add_argument("--pszm-decomp", type=Path)
    parser.add_argument("--calibrate", action="store_true")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "scope": "Godot behavior contract, not original-game parity", "seed": 554,
              "godot_version": subprocess.check_output([args.godot, "--version"], text=True).strip(),
              "fixed_fps": 60,
              "input_sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                  "scripts/3d/player/player.gd", "scripts/autoloads/combat_manager.gd",
                  "scripts/tools/melee_live_check.gd", "scripts/tools/melee_window_tests.gd",
                  "scripts/tools/verify_melee_contact.py", "data/re_reference/melee_contact_evidence.json")},
              "references": check_references(args), "checks": {}}
    env = {key: value for key, value in os.environ.items() if not key.startswith("PSZ_")}
    env.update(PSZ_MELEE_LIVE_CHECK="1", PSZ_COLISEUM_ENEMY="helion")
    with tempfile.TemporaryDirectory(prefix="psz-melee-") as folder:
        project = Path(folder)
        prepare_project(project)
        for name, scene in (("unit", "test_runner"), ("live", "coliseum_probe")):
            report["checks"][name] = run_probe(args.godot, project, f"res://scripts/tools/{scene}.tscn", args.output, name, env)
        if args.calibrate:
            player = project / "scripts/3d/player/player.gd"
            original = player.read_text()
            mutants = {
                "single_sample": ('if _attack_anim_elapsed < closing or previous_elapsed < opening:', 'if previous_elapsed < opening:'),
                "duplicate_contacts": ('if _attack_hit_targets.has(target_id):', 'if false and _attack_hit_targets.has(target_id):'),
            }
            # Duplicate mutant also disables the cap; otherwise single-target weapons stop immediately.
            for name, (old, new) in mutants.items():
                assert original.count(old) == 1, f"mutation anchor drift: {name}"
                changed = original.replace(old, new)
                if name == "duplicate_contacts":
                    changed = changed.replace('if _attack_hit_targets.size() >= target_cap:', 'if false and _attack_hit_targets.size() >= target_cap:')
                player.write_text(changed)
                result = run_probe(args.godot, project, "res://scripts/tools/coliseum_probe.tscn", args.output, name, env)
                late = [row for row in result["cases"] if row["mode"] == "late_entry"]
                signature = (len(late) == 3 and all(
                    row["actual"][0] == 0 if name == "single_sample" else row["actual"][0] > row["expected"][0]
                    for row in late))
                result["rejected"] = (not result["passed"] and not result["script_errors"] and not result["timed_out"]
                                      and len(result["cases"]) == 15 and signature)
                report["checks"][name] = result
            player.write_text(original)
    report["passed"] = (all(r.get("passed", True) for r in report["references"].values())
                        and report["checks"]["unit"]["passed"] and report["checks"]["live"]["passed"]
                        and all(r["rejected"] for r in report["checks"].values() if "rejected" in r))
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "report": str(args.output / "results.json")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
