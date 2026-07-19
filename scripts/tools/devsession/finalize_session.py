#!/usr/bin/env python3
"""Finalize a dev-session capture.

Given a session directory containing:
  - session.log            (Godot stdout, every line prefixed with a wall clock)
  - narration.json         (whisper-cli JSON with millisecond offsets)
and the wall-clock epoch that corresponds to t=0 of the audio recording,
produce:
  - narration.aligned.txt  (each narration segment stamped with wall-clock time)
  - timeline.txt           (session.log + narration merged in chronological order)

The two inputs share one wall clock, so timeline.txt is what makes the
"what I said" vs "what the game logged" comparison trivial to read.

Usage: finalize_session.py <session_dir> <audio_start_epoch>
"""
import json
import os
import sys
from datetime import datetime


def wall(epoch: float) -> str:
    lt = datetime.fromtimestamp(epoch)
    return lt.strftime("[%H:%M:%S.") + f"{int((epoch - int(epoch)) * 1000):03d}]"


def ts_key(bracketed: str) -> str:
    """Sort key from a leading '[HH:MM:SS.mmm]' prefix (empty -> sorts first)."""
    if bracketed.startswith("[") and "]" in bracketed[:16]:
        return bracketed[1:bracketed.index("]")]
    return ""


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: finalize_session.py <session_dir> <audio_start_epoch>", file=sys.stderr)
        return 2
    session_dir = sys.argv[1]
    audio_start = float(sys.argv[2])

    narr_json = os.path.join(session_dir, "narration.json")
    aligned_path = os.path.join(session_dir, "narration.aligned.txt")
    log_path = os.path.join(session_dir, "session.log")
    timeline_path = os.path.join(session_dir, "timeline.txt")

    # --- 1. align narration segments to wall clock -------------------------
    narration = []  # (wall_str, text)
    if os.path.exists(narr_json):
        with open(narr_json, encoding="utf-8", errors="replace") as fh:
            data = json.load(fh)
        for seg in data.get("transcription", []):
            text = (seg.get("text") or "").strip()
            if not text:
                continue
            off_ms = (seg.get("offsets") or {}).get("from", 0)
            narration.append((wall(audio_start + off_ms / 1000.0), text))

    with open(aligned_path, "w", encoding="utf-8") as fh:
        for stamp, text in narration:
            fh.write(f"{stamp} {text}\n")

    # --- 2. merge log + narration into one chronological timeline ----------
    entries = []  # (sort_key, line)
    if os.path.exists(log_path):
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                entries.append((ts_key(line), line))
    for stamp, text in narration:
        entries.append((ts_key(stamp), f"{stamp} >>> SAID: {text}"))

    # Stable sort keeps same-timestamp log lines in emission order.
    entries.sort(key=lambda e: e[0])

    with open(timeline_path, "w", encoding="utf-8") as fh:
        for _, line in entries:
            fh.write(line + "\n")

    print(f"[finalize] {len(narration)} narration segment(s) -> {aligned_path}")
    print(f"[finalize] merged timeline -> {timeline_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
