#!/usr/bin/env bash
#
# record_boot — record the BOOT phase of the autopilot as its own mp4.
#
# Wipes save_data.json + input_config.json (fresh first-run state), then drives
# splash → controls → title → character select → character create ("humar") →
# Principal's Office (intro dialog dismissed) → SaveManager.save_game() →
# quit. The resulting save is the starting point for record_first_mission.sh.
#
# Renders at 640x360 under Xvfb (the autopilot is a moving dot at this zoom,
# which is all we need to spot where it got stuck — and ~4x less memory
# pressure than 720p, so the AVI buffer doesn't get OOM-killed mid-run).
#
# Output: $OUTDIR/boot_<timestamp>.mp4 (default spec/public/recordings/).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/boot_$STAMP.avi"
MP4="$OUTDIR/boot_$STAMP.mp4"
FPS="${FPS:-30}"
RES="${RES:-640x360}"
# Boot phase is short (boot → title → create → office intro), ~30s real-time
# under headless. Wall-clock under --write-movie is ~3-4× slower per frame,
# so 180s is plenty of headroom.
TIMEOUT="${REC_TIMEOUT:-180}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record-boot] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

# 1) Fresh first-run player state — wipe save_data.json AND input_config.json
#    so the autopilot drives controls setup + character creation.
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"
echo "[record-boot] wiped save_data.json + input_config.json"

# 2) Offline manifest pointing at the local pack.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

# 3) Render under Xvfb, capturing the autopilot's stdout for pass/fail.
echo "[record-boot] rendering → $AVI (phase=boot, $RES @ ${FPS}fps, timeout=${TIMEOUT}s)"
START_TS="$(date -u +%s)"
# dbus-run-session gives godot a private session bus. Without it, godot's
# AccessKit (accessibility) layer SIGABRTs at startup when the ambient a11y
# bus is missing/disconnected (headless boxes), crashing the run with exit 134.
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_PHASE=boot LIBGL_ALWAYS_SOFTWARE=1 \
	dbus-run-session -- \
	xvfb-run -a -s "-screen 0 ${RES}x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$LOG" 2>&1
RC=$?
END_TS="$(date -u +%s)"
echo "[record-boot] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record-boot] ERROR: no AVI frames produced" >&2; exit 1; }

# 4) Determine pass/fail and write the sidecar JSON the /autopilot run-matrix
# UI reads. Pass = clean exit AND the autopilot's terminator fired. Surfaces
# the "[sanity] FAIL: …" line verbatim when present.
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
JSON="$OUTDIR/boot_$STAMP.json"
cat > "$JSON" <<EOF
{
  "phase": "boot",
  "status": "$STATUS",
  "godot_exit": $RC,
  "captured_at": "$(date -u -d "@$START_TS" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((END_TS - START_TS)),
  "fail_reason": "$FAIL_REASON_JSON",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$LOG" || echo 0)
}
EOF

# 5) Transcode AVI → mp4.
echo "[record-boot] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" || {
	echo "[record-boot] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4" "$JSON"
echo "[record-boot] $STATUS — $MP4"
if [ "$STATUS" = "pass" ]; then
	echo "[record-boot] save state preserved at $USERDIR/save_data.json (use record_first_mission.sh next)"
else
	echo "[record-boot] WARNING: $FAIL_REASON — last 10 [sanity] lines:" >&2
	grep '^\[sanity\]' "$LOG" | tail -10 >&2
fi
