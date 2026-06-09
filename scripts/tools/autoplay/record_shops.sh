#!/usr/bin/env bash
#
# record_shops — record the SHOP/STORAGE smoke phase of the autopilot as its
# own mp4 + JSON sidecar, so the city-economy screens are part of the
# regression matrix (they're the surface that shipped broken in #283/#245 and
# that the quest chain never opens). See issue #9.
#
# Drives a fresh first-run boot → character create → Principal's Office, then
# (PSZ_AUTOPILOT_SHOPS=1) detours — after onboarding, before the first quest —
# through the principal debug-meseta grant, the item + weapon shops, and the
# PsoStartMenu (opened in the city), instead of accepting a quest, ending on DONE.
#
# Self-contained + terminal: it wipes the default save like record_boot.sh, so
# run it as the LAST matrix phase (or standalone) — it does NOT chain a save
# into the quest phases.
#
# Output: $OUTDIR/shops_<timestamp>.mp4 + .json (default spec/public/recordings/).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/shops_$STAMP.avi"
MP4="$OUTDIR/shops_$STAMP.mp4"
FPS="${FPS:-30}"
RES="${RES:-640x360}"
# boot → create → office intro → principal meseta → item shop → DONE. Longer
# than plain boot; ~240s of headroom under --write-movie.
TIMEOUT="${REC_TIMEOUT:-240}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record-shops] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

# 1) Fresh first-run player state.
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"
echo "[record-shops] wiped save_data.json + input_config.json"

# 2) Offline manifest pointing at the local pack.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

# 3) Render under Xvfb. PSZ_AUTOPILOT_SHOPS=1 enables the shop detour; phase
#    defaults to "all" (full boot) so the office-intro → shops branch fires.
echo "[record-shops] rendering → $AVI (shops smoke, $RES @ ${FPS}fps, timeout=${TIMEOUT}s)"
START_TS="$(date -u +%s)"
DBUS_WRAP=""
if command -v dbus-run-session >/dev/null 2>&1; then
	DBUS_WRAP="dbus-run-session --"
else
	echo "[record-shops] WARN: dbus-run-session not found — godot may SIGABRT without an a11y bus." >&2
fi
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_SHOPS=1 LIBGL_ALWAYS_SOFTWARE=1 \
	$DBUS_WRAP \
	xvfb-run -a -s "-screen 0 ${RES}x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$LOG" 2>&1
RC=$?
END_TS="$(date -u +%s)"
echo "[record-shops] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record-shops] ERROR: no AVI frames produced" >&2; exit 1; }

# 4) Pass/fail + sidecar JSON (same shape the matrix report reads).
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
JSON="$OUTDIR/shops_$STAMP.json"
cat > "$JSON" <<EOF
{
  "phase": "shops",
  "status": "$STATUS",
  "godot_exit": $RC,
  "captured_at": "$(date -u -d "@$START_TS" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((END_TS - START_TS)),
  "fail_reason": "$FAIL_REASON_JSON",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$LOG" || echo 0)
}
EOF

echo "[record-shops] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" || {
	echo "[record-shops] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4" "$JSON"
echo "[record-shops] $STATUS — $MP4"
if [ "$STATUS" != "pass" ]; then
	echo "[record-shops] WARNING: $FAIL_REASON — last 12 [sanity] lines:" >&2
	grep '^\[sanity\]' "$LOG" | tail -12 >&2
fi
[ "$STATUS" = "pass" ]
