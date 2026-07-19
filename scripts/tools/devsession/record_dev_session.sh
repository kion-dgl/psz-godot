#!/usr/bin/env bash
#
# record_dev_session.sh — capture a narrated dev play-test on the Mac.
#
# You launch this instead of `godot --path .`. It:
#   1. records your microphone while you play           -> narration.wav
#   2. runs the game, stamping every stdout line with a
#      wall clock                                        -> session.log
#   3. when you QUIT THE GAME, transcribes the narration
#      (whisper-cli) and merges it with the log by time  -> timeline.txt
#
# session.log and narration share one wall clock, so timeline.txt lines up
# "what you said" against "what the game logged" — hand the whole session
# folder to Claude and it can diff narration vs logs to surface bugs / drift.
#
# Usage:
#   scripts/tools/devsession/record_dev_session.sh [--note "focus of this run"]
#   scripts/tools/devsession/record_dev_session.sh --audio 2
#   scripts/tools/devsession/record_dev_session.sh --list-audio
#
# Env overrides:
#   GODOT_BIN          godot binary            (default: godot)
#   WHISPER_MODEL      ggml model path         (default: ~/.cache/whisper-cpp/ggml-small.en.bin)
#   PSZ_AUDIO_DEVICE   avfoundation audio idx  (default: auto-detect MacBook Pro Microphone)
#   PSZ_PTY            1 = give Godot a pty (default 0; Godot already flushes
#                          per-print on a pipe, so this is only an escape hatch)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$REPO_ROOT/scripts/tools/devsession"

GODOT_BIN="${GODOT_BIN:-godot}"
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.cache/whisper-cpp/ggml-small.en.bin}"
AUDIO_DEVICE="${PSZ_AUDIO_DEVICE:-}"
USE_PTY="${PSZ_PTY:-0}"
NOTE=""

# ---- audio device discovery ------------------------------------------------
list_audio() {
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | sed -n '/AVFoundation audio devices/,$p' \
    | grep -oE '\[[0-9]+\] .*' || true
}
default_audio() {
  local lines idx
  lines="$(list_audio)"
  idx="$(printf '%s\n' "$lines" | grep -i 'MacBook Pro Microphone' | grep -oE '^\[[0-9]+\]' | tr -dc '0-9' | head -1)"
  [ -z "$idx" ] && idx="$(printf '%s\n' "$lines" | head -1 | grep -oE '^\[[0-9]+\]' | tr -dc '0-9')"
  echo "$idx"
}

# ---- args ------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --list-audio) list_audio; exit 0 ;;
    --audio) AUDIO_DEVICE="$2"; shift 2 ;;
    --model) WHISPER_MODEL="$2"; shift 2 ;;
    --note)  NOTE="$2"; shift 2 ;;
    --pty) USE_PTY=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---- preflight -------------------------------------------------------------
command -v ffmpeg     >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }
command -v whisper-cli >/dev/null || { echo "whisper-cli not found (brew install whisper-cpp)" >&2; exit 1; }
command -v "$GODOT_BIN" >/dev/null || { echo "godot not found on PATH (set GODOT_BIN)" >&2; exit 1; }
[ -f "$WHISPER_MODEL" ] || { echo "whisper model missing: $WHISPER_MODEL" >&2; exit 1; }

[ -z "$AUDIO_DEVICE" ] && AUDIO_DEVICE="$(default_audio)"
[ -z "$AUDIO_DEVICE" ] && { echo "no audio input device found (see --list-audio)" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
SESSION="$REPO_ROOT/dev-sessions/$STAMP"
mkdir -p "$SESSION"

BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"

echo "==> dev session   $SESSION"
echo "    branch $BRANCH @ $SHA   audio device [$AUDIO_DEVICE]   model $(basename "$WHISPER_MODEL")"
[ -n "$NOTE" ] && echo "    note: $NOTE"
echo "    Play the game window that opens. QUIT THE GAME to end + transcribe."
echo

# ---- start audio -----------------------------------------------------------
# Stamp the wall clock that maps to t=0 of the wav (ffmpeg has ~0.5s startup
# latency; second-level alignment against the log is unaffected).
AUDIO_START="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
ffmpeg -hide_banner -loglevel warning -nostdin \
  -f avfoundation -i ":$AUDIO_DEVICE" -ac 1 -ar 16000 -y \
  "$SESSION/narration.wav" >"$SESSION/ffmpeg.log" 2>&1 &
FFMPEG_PID=$!

cleanup_audio() {
  if [ -n "${FFMPEG_PID:-}" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    kill -INT "$FFMPEG_PID" 2>/dev/null || true   # SIGINT lets ffmpeg finalize the wav
    wait "$FFMPEG_PID" 2>/dev/null || true
  fi
}
trap cleanup_audio EXIT

# ---- run the game, stamping stdout -----------------------------------------
STAMP_PL='use Time::HiRes qw(time); use POSIX qw(strftime); $|=1;
while (my $l=<STDIN>) { $l =~ s/\r//g; my $t=time;
  print strftime("[%H:%M:%S", localtime $t) . sprintf(".%03d] ", int(($t-int $t)*1000)) . $l; }'

set +e
if [ "$USE_PTY" = 1 ]; then
  # `script` hands Godot a pty so its libc stdout stays line-buffered when piped.
  script -q /dev/null "$GODOT_BIN" --path "$REPO_ROOT" 2>&1 \
    | perl -e "$STAMP_PL" | tee "$SESSION/session.log"
else
  "$GODOT_BIN" --path "$REPO_ROOT" 2>&1 \
    | perl -e "$STAMP_PL" | tee "$SESSION/session.log"
fi
set -e

# ---- stop audio ------------------------------------------------------------
cleanup_audio
trap - EXIT
AUDIO_END="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"

# ---- transcribe ------------------------------------------------------------
echo
echo "==> transcribing narration (whisper: $(basename "$WHISPER_MODEL"))…"
if ! whisper-cli -m "$WHISPER_MODEL" -f "$SESSION/narration.wav" \
      -l en -oj -otxt -of "$SESSION/narration" >"$SESSION/whisper.log" 2>&1; then
  echo "    whisper-cli failed — see $SESSION/whisper.log" >&2
fi

# ---- align + merge into one timeline ---------------------------------------
python3 "$HERE/finalize_session.py" "$SESSION" "$AUDIO_START" || true

# ---- session metadata ------------------------------------------------------
python3 - "$SESSION" "$BRANCH" "$SHA" "$AUDIO_START" "$AUDIO_END" "$AUDIO_DEVICE" \
         "$WHISPER_MODEL" "$NOTE" <<'PY'
import json, sys
d, branch, sha, a0, a1, dev, model, note = sys.argv[1:9]
from datetime import datetime
meta = {
    "branch": branch, "sha": sha, "note": note,
    "audio_device": dev, "whisper_model": model.rsplit("/", 1)[-1],
    "audio_start_epoch": float(a0), "audio_end_epoch": float(a1),
    "started_at": datetime.fromtimestamp(float(a0)).isoformat(timespec="seconds"),
    "ended_at": datetime.fromtimestamp(float(a1)).isoformat(timespec="seconds"),
    "duration_sec": round(float(a1) - float(a0), 1),
}
with open(f"{d}/meta.json", "w") as f:
    json.dump(meta, f, indent=2)
PY

echo
echo "==> done.  $SESSION"
echo "    timeline.txt          merged log + narration (read this)"
echo "    narration.aligned.txt narration with wall-clock times"
echo "    session.log           timestamped Godot output"
echo "    meta.json             branch / sha / timing"
