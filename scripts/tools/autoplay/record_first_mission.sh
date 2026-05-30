#!/usr/bin/env bash
#
# record_first_mission — record the FIRST-MISSION phase as its own mp4.
#
# Assumes record_boot.sh has already produced a save with character "humar" in
# slot 0. Does NOT wipe save_data.json or input_config.json — bootstrap skips
# input_select (config present) and the autopilot's character_select handler
# loads slot 0 directly. Drives: title → char select → city office (no intro
# this time) → counter (Guild) → accept Search and Rescue → office briefing →
# warp pad → valley_field → 24 cells → SessionManager.complete_quest() →
# return to city → SaveManager.save_game() → quit.
#
# Renders at 640x360 (see record_boot.sh's rationale).
#
# Output: $OUTDIR/first_mission_<timestamp>.mp4 (default spec/public/recordings/).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/first_mission_$STAMP.avi"
MP4="$OUTDIR/first_mission_$STAMP.mp4"
FPS="${FPS:-30}"
RES="${RES:-640x360}"
# Quest phase is the long one: ~5 min real-time, ~15-20 min under --write-movie
# per frame at 360p. 25min ceiling.
TIMEOUT="${REC_TIMEOUT:-1500}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record-first-mission] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

# 1) DO NOT wipe save state. The boot phase left a character; this phase
#    resumes that save. Fail loud if the save is missing.
if [ ! -f "$USERDIR/save_data.json" ]; then
	echo "[record-first-mission] ERROR: $USERDIR/save_data.json missing — run record_boot.sh first" >&2
	exit 1
fi
echo "[record-first-mission] resuming save state at $USERDIR/save_data.json"

# 2) Offline manifest pointing at the local pack.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

# 3) Render under Xvfb, capturing the autopilot's stdout for pass/fail.
echo "[record-first-mission] rendering → $AVI (phase=first-mission, $RES @ ${FPS}fps, timeout=${TIMEOUT}s)"
START_TS="$(date -u +%s)"
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_PHASE=first-mission LIBGL_ALWAYS_SOFTWARE=1 \
	xvfb-run -a -s "-screen 0 ${RES}x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$LOG" 2>&1
RC=$?
END_TS="$(date -u +%s)"
echo "[record-first-mission] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record-first-mission] ERROR: no AVI frames produced" >&2; exit 1; }

# 4) Determine pass/fail and write the sidecar JSON the /autopilot run-matrix
# UI reads. Pass = clean exit AND the autopilot's terminator fired. The
# autopilot fails the run on stuck walks with "[sanity] FAIL: ..." so capture
# that line verbatim if present — it points the reader at the stage that
# needs waypoint authoring.
STATUS="fail"
FAIL_REASON=""
FAIL_LINE="$(grep -m1 '^\[sanity\] FAIL:' "$LOG" | sed 's/^\[sanity\] FAIL: //')"
if [ "$RC" -eq 0 ] && grep -qF '[sanity] DONE ok' "$LOG"; then
	STATUS="pass"
elif [ -n "$FAIL_LINE" ]; then
	FAIL_REASON="$FAIL_LINE"
elif [ "$RC" -ne 0 ]; then
	FAIL_REASON="godot exit $RC"
else
	FAIL_REASON="autopilot did not reach DONE checkpoint"
fi
# Escape the reason for JSON (double quotes + backslashes).
FAIL_REASON_JSON="$(printf '%s' "$FAIL_REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')"
JSON="$OUTDIR/first_mission_$STAMP.json"
cat > "$JSON" <<EOF
{
  "phase": "first-mission",
  "status": "$STATUS",
  "godot_exit": $RC,
  "captured_at": "$(date -u -d "@$START_TS" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((END_TS - START_TS)),
  "fail_reason": "$FAIL_REASON_JSON",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$LOG" || echo 0)
}
EOF

# 5) Transcode AVI → mp4.
echo "[record-first-mission] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" || {
	echo "[record-first-mission] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4" "$JSON"
echo "[record-first-mission] $STATUS — $MP4"
if [ "$STATUS" = "fail" ]; then
	echo "[record-first-mission] WARNING: $FAIL_REASON — last 10 [sanity] lines:" >&2
	grep '^\[sanity\]' "$LOG" | tail -10 >&2
fi
