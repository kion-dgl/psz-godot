#!/usr/bin/env python3
"""Build clip sound cues from the retained psz-re action/event tables.

Run from any directory. Ambiguous action-to-clip mappings are deliberately
excluded: the Godot FSM plays clips and does not yet expose ROM action IDs.
"""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def build():
    source = json.loads((ROOT / "data/re_reference/enemy_sound_events.json").read_text())
    export = json.loads((ROOT / "data/re_reference/enemy_sound_export.json").read_text())
    sounds = {}
    for row in export["entries"]:
        if row["status"] not in ("ok", "loop"):
            continue
        path = ROOT / "assets/sfx" / row["wav"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row["sha256"], path
        points = row["loop_samples_end_exclusive"]
        sounds[row["name"]] = {
            "path": "res://" + path.relative_to(ROOT).as_posix(),
            "loop_begin": points[0] if points else -1,
            "loop_end": points[1] if points else -1,
            "mix_rate": export["rate"],
        }
    models, skipped = {}, []
    for model, archive in source["archives"].items():
        candidates = defaultdict(list)
        for action in archive["event_table"]:
            for stage in action["animation_stages"]:
                if not stage["member"]:
                    continue
                clip = Path(stage["member"]).stem
                events = []
                for event in action["events"]:
                    if event["start_stage"] != stage["stage"]:
                        continue
                    sound = event["sound"]
                    reason = ""
                    if event["window_flag"]:
                        reason = "window event"
                    elif sound["symbol"] not in sounds:
                        reason = "no rendered WAV"
                    if reason:
                        skipped.append({"model": model, "action": action["index"], "clip": clip, "reason": reason})
                        continue
                    events.append({"frame": event["frame"], "sound": sound["symbol"]})
                candidates[clip].append(sorted(events, key=lambda e: (e["frame"], e["sound"])))
        clips = {}
        for clip, variants in candidates.items():
            if any(v != variants[0] for v in variants[1:]):
                skipped.append({"model": model, "clip": clip, "reason": "action-dependent cues"})
            elif variants[0]:
                clips[clip] = variants[0]
        if clips:
            models[model] = clips
    return {
        "source": "data/re_reference/enemy_sound_events.json",
        "timing": "ROM clip-local frames / 60, matching the imported GLB timebase; not original AI parity.",
        "volume": "Rendered WAVs already include sequence volume. Do not apply entry_volume again.",
        "loop_policy": "Looping WAVs are owned by the enemy and stop on clip change, pause, dormancy, or removal.",
        "sounds": sounds, "models": models, "skipped": skipped,
    }


if __name__ == "__main__":
    result = build()
    (ROOT / "data/enemy_sounds.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f'{len(result["models"])} models, {sum(len(c) for c in result["models"].values())} clips, {len(result["skipped"])} exclusions')
