#!/usr/bin/env bash
#
# record_the_paru_pact — record the THE-PARU-PACT phase as its own mp4.
#
# Assumes record_first_mission.sh already completed Search and Rescue and
# left a save with that quest reported (which unlocks The Paru Pact at the
# guild counter). Drives the save state through: title → char select →
# counter → accept The Paru Pact → office briefing → warp pad → paru field
# → cells → SessionManager.complete_quest() → return to city → save → quit.
#
# Same flow as record_first_mission.sh, just a different quest selection.
# The autopilot's `first-mission` phase actually means "any single-quest
# resume-from-save run" — the specific quest is chosen via
# PSZ_AUTOPILOT_QUEST. The 'first-mission' name predates having more than
# one quest.
#
# NO_OBSTACLES + NO_BOXES are set so the autopilot doesn't wedge against
# physical room contents the spec doesn't yet route around. Drop these
# once the gates/warps mechanics spec lets the solver address them.
#
# Output: $OUTDIR/the_paru_pact_<timestamp>.mp4 (default spec/public/recordings/).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/the_paru_pact_$STAMP.avi"
MP4="$OUTDIR/the_paru_pact_$STAMP.mp4"
FPS="${FPS:-30}"
RES="${RES:-640x360}"
# Quest phase is the long one — paru pact is ~20 cells, similar length to SR.
TIMEOUT="${REC_TIMEOUT:-1500}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record-paru-pact] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

if [ ! -f "$USERDIR/save_data.json" ]; then
	echo "[record-paru-pact] ERROR: $USERDIR/save_data.json missing — run record_first_mission.sh first" >&2
	exit 1
fi
echo "[record-paru-pact] resuming save state at $USERDIR/save_data.json"

PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

echo "[record-paru-pact] rendering → $AVI (phase=first-mission, quest=the_paru_pact, $RES @ ${FPS}fps, timeout=${TIMEOUT}s)"
START_TS="$(date -u +%s)"
PSZ_AUTOPILOT=1 \
	PSZ_AUTOPILOT_PHASE=first-mission \
	PSZ_AUTOPILOT_QUEST=the_paru_pact \
	PSZ_AUTOPILOT_NO_OBSTACLES=1 \
	PSZ_AUTOPILOT_NO_BOXES=1 \
	LIBGL_ALWAYS_SOFTWARE=1 \
	xvfb-run -a -s "-screen 0 ${RES}x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$LOG" 2>&1
RC=$?
END_TS="$(date -u +%s)"
echo "[record-paru-pact] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record-paru-pact] ERROR: no AVI frames produced" >&2; exit 1; }

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
FAIL_REASON_JSON="$(printf '%s' "$FAIL_REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')"
JSON="$OUTDIR/the_paru_pact_$STAMP.json"
cat > "$JSON" <<EOF
{
  "phase": "the-paru-pact",
  "status": "$STATUS",
  "godot_exit": $RC,
  "captured_at": "$(date -u -d "@$START_TS" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((END_TS - START_TS)),
  "fail_reason": "$FAIL_REASON_JSON",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$LOG" || echo 0)
}
EOF

echo "[record-paru-pact] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" || {
	echo "[record-paru-pact] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4" "$JSON"
echo "[record-paru-pact] $STATUS — $MP4"
if [ "$STATUS" = "fail" ]; then
	echo "[record-paru-pact] WARNING: $FAIL_REASON — last 10 [sanity] lines:" >&2
	grep '^\[sanity\]' "$LOG" | tail -10 >&2
fi
