#!/usr/bin/env python3
"""Extract the original dodge action's per-frame root-motion curve from the
pszm-decomp ROM replay evidence.

The decomp's `native/evidence/player-dodge-frame-rom.json` replays the full
local-player frame loop (02086e40 + controller + camera + root draws) after a
direct dodge-core admission, with the original full-rate motion resources
loaded. Its `output` hex carries 80 words per frame; words 6/8 are the drawn
root x/z. The `idle-heading-0` sequence admits at trace frame 20 with heading
0 (+z), so motion frame N = trace frame 20+N, and the deltas between
consecutive root samples are the dodge's displacement curve in Q12
(4096 = 1 unit) in the dodge-local frame.

Emits the motion-frame table (duration, per-frame deltas, totals) with
provenance hashes so the JSON can be re-derived and audited. The run-admission
variant travels one extra run-speed step (835 Q12 at the replay's run speed)
on the admission frame — the motion integrate applies the carried run speed in
the dodge direction once before clearing it; that step is NOT part of this
table.
"""
import argparse
import json
import struct
from pathlib import Path

WORDS_PER_FRAME = 80
ROOT_X_WORD = 6
ROOT_Z_WORD = 8
ADMISSION_FRAME = 20  # idle-heading-0 sequence in the replay
MOTION_FRAMES = 41  # action animation motion 3 length at 30 fps
Q12 = 4096.0
DEFAULT_EVIDENCE = "/Users/kion/Projects/pszm-decomp/native/evidence/player-dodge-frame-rom.json"


def dodge_motion(evidence: Path):
    data = json.loads(evidence.read_text())
    record = data["records"][0]
    words = struct.unpack("<%dI" % (len(record["output"]) // 2 // 4), bytes.fromhex(record["output"]))

    def s32(w):
        return w - (1 << 32) if w >= (1 << 31) else w

    roots = []
    for trace in range(ADMISSION_FRAME, ADMISSION_FRAME + MOTION_FRAMES):
        base = trace * WORDS_PER_FRAME
        roots.append((s32(words[base + ROOT_X_WORD]), s32(words[base + ROOT_Z_WORD])))
    deltas = [
        [roots[i][0] - roots[i - 1][0], roots[i][1] - roots[i - 1][1]]
        for i in range(1, len(roots))
    ]
    total = [sum(d[0] for d in deltas), sum(d[1] for d in deltas)]
    return {
        "source": (
            "pszm-decomp ROM replay native/evidence/player-dodge-frame-rom.json "
            "(records[0] idle-heading-0; drawn root words 6/8 of the 80-word frame); "
            "replayed against the original full-rate motion resources"
        ),
        "arm9_sha256": record["arm9_sha256"],
        "resource_sha256": record["resource_sha256"],
        "units": "Q12 fixed point (4096 = 1 unit), dodge-local frame (+z = dodge heading, +x = right)",
        "duration_frames": MOTION_FRAMES,
        "tick_fps": 30,
        "delta_per_frame": deltas,
        "total_q12": total,
        "total_units": [round(total[0] / Q12, 4), round(total[1] / Q12, 4)],
        "notes": [
            "Motion frame 0 is static (admission frame); the curve covers frames 1..40, frame 41 completes the action.",
            "Displacement profile: burst (frames 2-5), plateau ~1085 Q12/frame (frames 6-13), decay (14-25), settle-back to the final root (26-40).",
            "The +x/-x wobble is the roll arc baked in the original motion; keep it for 1:1 travel.",
            "Admission while RUNNING adds one run-speed step in the dodge direction on the admission frame (not part of this table).",
            "duration differs from the extracted _esc_f clip (20 frames): the original action is roll + get-up, weapon-independent.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--evidence", type=Path, default=Path(DEFAULT_EVIDENCE),
                        help="path to player-dodge-frame-rom.json (pszm-decomp checkout)")
    parser.add_argument("--out", type=Path, default=Path("data/re_reference/player_dodge_motion.json"))
    args = parser.parse_args()
    motion = dodge_motion(args.evidence)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(motion, indent=1) + "\n")
    print(f"wrote {args.out}: {motion['duration_frames']} frames, total {motion['total_units']} units")


if __name__ == "__main__":
    main()
