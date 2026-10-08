#!/usr/bin/env python3
"""Check the /states/combat-roster contract without assets or network access."""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def check(root=ROOT):
    errors, warnings = [], []

    def read(name):
        return json.loads((root / f"data/{name}.json").read_text())

    def index(rows, key, label):
        result = {}
        for row in rows:
            value = row[key]
            if value in result:
                errors.append(f"duplicate {label}: {value}")
            result[value] = row
        return result

    def coverage(actual, recorded, label):
        for key in sorted(actual - recorded):
            errors.append(f"uncovered {label}: {key}")
        for key in sorted(recorded - actual):
            errors.append(f"stale {label}: {key}")

    audit = read("combat_roster")
    if audit.get("schema_version") != 1:
        errors.append("unsupported roster schema")
    resources = []
    for path in sorted((root / "data/enemies").glob("*.tres")):
        text = path.read_text()
        row = dict(re.findall(r'^(id|name|model_id|animation_model_id) = "([^"]*)"', text, re.M))
        if not all(row.get(k) for k in ("id", "name", "model_id")):
            errors.append(f"incomplete resource: {path.name}")
            continue
        if row["id"] != path.stem:
            errors.append(f"resource filename mismatch: {path.name}")
        row["animation_model_id"] = row.get("animation_model_id") or row["model_id"]
        row["is_boss"] = bool(re.search(r'^is_boss = true$', text, re.M))
        resources.append(row)
    resources = index(resources, "id", "resource")
    roster = index(audit["enemies"], "id", "crosswalk")
    coverage(set(resources), set(roster), "resource")
    source = read("re_reference/enemy_ids")["ids"]
    viewer = {x["model"] for x in read("re_reference/enemy_viewer_audit")["models"]}
    for id in resources.keys() & roster.keys():
        row, recorded = resources[id], roster[id]
        for field, value in row.items():
            if recorded.get(field) != value:
                errors.append(f"resource drift: {id}.{field}")
        if not isinstance(recorded.get("issue"), int) or not 684 <= recorded["issue"] <= 721:
            errors.append(f"invalid family issue: {id}")
        if not recorded.get("identity_status"):
            errors.append(f"missing identity status: {id}")
        expected_ids = [int(k) for k, v in source.items() if v == row["model_id"]]
        expected_id = expected_ids[0] if len(expected_ids) == 1 else None
        if recorded.get("source_id") != expected_id:
            errors.append(f"source identity drift: {id}")
        if row["model_id"] not in viewer:
            warnings.append(f"no saved viewer model: {id} ({row['model_id']})")

    attacks = set(read("enemy_attacks")["enemies"])
    exceptions = index(audit["attack_exceptions"], "id", "attack exception")
    for id in sorted(set(resources) - attacks):
        errors.append(f"missing attack: {id}")
    orphans = attacks - set(resources)
    for id in sorted(orphans - set(exceptions)):
        errors.append(f"unexplained attack orphan: {id}")
    for id in sorted(set(exceptions) - orphans):
        errors.append(f"stale attack exception: {id}")
    for id in sorted(orphans & set(exceptions)):
        warnings.append(f"known attack orphan: {id}: {exceptions[id]['reason']}")

    exclusions = index(audit["source_exceptions"], "source_id", "source exception")
    models = {r["model_id"] for r in resources.values()}
    for key, model in source.items():
        slot = int(key)
        if model in models:
            if slot in exclusions:
                errors.append(f"stale source exception: {slot}")
        elif slot not in exclusions:
            errors.append(f"uncovered source slot: {slot} ({model})")
        elif exclusions[slot]["model_id"] != model:
            errors.append(f"source exception drift: {slot}")
        else:
            warnings.append(f"source exclusion: {slot} {model}: {exclusions[slot]['reason']}")
    for slot in exclusions:
        if str(slot) not in source:
            errors.append(f"stale source exception: {slot}")

    boss_data = read("boss_arenas")
    bosses = boss_data["bosses"]
    encounters = index(audit["encounters"], "id", "encounter")
    coverage(set(bosses), set(encounters), "encounter")
    for id in bosses.keys() & encounters.keys():
        for field in ("model_id", "arena"):
            if bosses[id].get(field) != encounters[id].get(field):
                errors.append(f"encounter drift: {id}.{field}")
        if bosses[id].get("arena") not in boss_data["arenas"]:
            errors.append(f"missing encounter arena: {id}")
        for form in bosses[id].get("forms", []):
            resource = resources.get(form["roster_id"], {})
            if resource.get("model_id") != form["model_id"]:
                errors.append(f"encounter form drift: {id}/{form['roster_id']}")

    metadata = index(read("enemies"), "id", "metadata")
    drift = {}
    for id in resources.keys() | metadata.keys():
        if id not in resources or id not in metadata:
            drift[f"{id}.presence"] = "metadata-only" if id in metadata else "resource-only"
            continue
        for field in ("name", "model_id", "is_boss"):
            if resources[id][field] != metadata[id].get(field):
                drift[f"{id}.{field}"] = metadata[id].get(field)
    known = index(audit["metadata_exceptions"], "key", "metadata exception")
    for key, value in drift.items():
        if key not in known or known[key]["value"] != value:
            errors.append(f"unexplained metadata drift: {key} = {value}")
        else:
            warnings.append(f"known metadata drift: {key}: {known[key]['reason']}")
    for key in known.keys() - drift.keys():
        errors.append(f"stale metadata exception: {key}")
    for group in ("attack_exceptions", "source_exceptions", "metadata_exceptions", "encounters"):
        for row in audit[group]:
            if not isinstance(row.get("issue"), int) or not 683 <= row["issue"] <= 721:
                errors.append(f"invalid issue in {group}: {row}")
            if not row.get("reason", row.get("note")):
                errors.append(f"missing explanation in {group}: {row}")
    return errors, warnings


def main():
    try:
        errors, warnings = check()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: invalid roster input: {exc}")
        return 1
    for message in warnings:
        print(f"KNOWN: {message}")
    for message in errors:
        print(f"FAIL: {message}")
    print(f"Combat roster: {len(errors)} errors; {len(warnings)} known gaps (not fidelity approval).")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
