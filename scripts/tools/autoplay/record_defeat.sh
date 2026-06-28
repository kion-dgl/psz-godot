#!/usr/bin/env bash
#
# record_defeat — drive the player to HP-zero DEFEAT in the first field cell and
# verify the return-to-city flow (spec /states/player-death).
#
# Reuses the first-mission drive (title → char select → office → accept Search
# and Rescue → warp → valley_field) but flips PSZ_AUTOPILOT_DEFEAT=1: on the
# first field cell the autopilot gives the player 100 meseta, deals lethal
# damage, confirms "Yes" on the defeat screen, and asserts the player lands back
# in the city with 50 meseta and full HP. Success oracle is the same DONE ok.
#
# Assumes record_boot.sh has already produced a save with a character in slot 0
# (same prerequisite as record_first_mission.sh). Does NOT wipe save state.
#
# Output: $OUTDIR/defeat_<timestamp>.mp4 (default spec/public/recordings/).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/defeat_$STAMP.avi"
MP4="$OUTDIR/defeat_$STAMP.mp4"
FPS="${FPS:-30}"
RES="${RES:-640x360}"
# Short run: boot → accept → field → kill → return. ~3-4 min real, well under
# the quest run. 600s ceiling is generous.
TIMEOUT="${REC_TIMEOUT:-600}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record-defeat] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

if [ ! -f "$USERDIR/save_data.json" ]; then
	echo "[record-defeat] ERROR: $USERDIR/save_data.json missing — run record_boot.sh first" >&2
	exit 1
fi
echo "[record-defeat] resuming save state at $USERDIR/save_data.json"

# Offline manifest pointing at the local pack.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

echo "[record-defeat] rendering → $AVI (phase=first-mission + DEFEAT, $RES @ ${FPS}fps, timeout=${TIMEOUT}s)"
START_TS="$(date -u +%s)"
DBUS_WRAP=""
if command -v dbus-run-session >/dev/null 2>&1; then
	DBUS_WRAP="dbus-run-session --"
else
	echo "[record-defeat] WARN: dbus-run-session not found — running without a private DBus session; godot may SIGABRT if no ambient a11y bus is present." >&2
fi
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_PHASE=first-mission PSZ_AUTOPILOT_DEFEAT=1 LIBGL_ALWAYS_SOFTWARE=1 \
	$DBUS_WRAP \
	xvfb-run -a -s "-screen 0 ${RES}x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$LOG" 2>&1
RC=$?
END_TS="$(date -u +%s)"
echo "[record-defeat] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record-defeat] ERROR: no AVI frames produced" >&2; exit 1; }

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
JSON="$OUTDIR/defeat_$STAMP.json"
cat > "$JSON" <<EOF
{
  "phase": "defeat",
  "status": "$STATUS",
  "godot_exit": $RC,
  "captured_at": "$(date -u -d "@$START_TS" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((END_TS - START_TS)),
  "fail_reason": "$FAIL_REASON_JSON",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$LOG" || echo 0)
}
EOF

echo "[record-defeat] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" || {
	echo "[record-defeat] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4" "$JSON"
echo "[record-defeat] $STATUS — $MP4"
if [ "$STATUS" = "fail" ]; then
	echo "[record-defeat] WARNING: $FAIL_REASON — last 12 [sanity] lines:" >&2
	grep '^\[sanity\]' "$LOG" | tail -12 >&2
fi
