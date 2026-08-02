#!/usr/bin/env bash
#
# record_free_roam — drive a FREE-ROAM field end-to-end and assert it clears.
#
# Boots fresh (title → create → office), then PSZ_AUTOPILOT_FIELD enters the
# area's free field (not a quest) and walks the whole thing: area A → transition
# → area B (incl. the key detour + key gate) → boss arena → kill → DONE. This is
# the free-roam counterpart to record_first_mission.sh, covering the free-roam-
# only paths the quest matrix can't reach (entry spawns, goal pads, section
# warps, key detours). Exits non-zero unless the run prints `[sanity] DONE ok`.
#
# Env: FIELD_AREA (default gurhacia).
# Output: $OUTDIR/freeroam_<area>_<ts>.mp4 + .sanity.log
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
AREA="${FIELD_AREA:-gurhacia}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/freeroam_${AREA}_$STAMP.avi"
MP4="$OUTDIR/freeroam_${AREA}_$STAMP.mp4"
SANITY="$OUTDIR/freeroam_${AREA}_$STAMP.sanity.log"
FPS="${FPS:-30}"
TIMEOUT="${REC_TIMEOUT:-420}"

[ -f "$PACK" ] || { echo "[record-freeroam] ERROR: $PACK not found (build the local pack first)" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

MANIFEST_BAK="$(mktemp)"
cp "$MANIFEST" "$MANIFEST_BAK"
trap '[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"' EXIT
cat > "$MANIFEST" <<JSON
{ "version": "freeroam", "godot_version": "4.5", "pack": { "sha256": "$(sha256sum "$PACK" | cut -d' ' -f1)", "size": $(stat -c %s "$PACK"), "urls": ["file://$PACK"] } }
JSON

# Fresh first-run state so the boot flow runs into free-roam.
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"

echo "[record-freeroam] driving free-roam field area=$AREA → $SANITY"
env PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_FIELD="$AREA" LIBGL_ALWAYS_SOFTWARE=1 \
	timeout "$TIMEOUT" xvfb-run -a -s "-screen 0 640x360x24" \
	"$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO" >"$SANITY" 2>&1
RC=$?
echo "[record-freeroam] godot rc=$RC"

if [ -s "$AVI" ]; then
	ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$MP4" 2>/dev/null && rm -f "$AVI" || true
fi

if grep -qF '[sanity] DONE ok' "$SANITY"; then
	echo "[record-freeroam] PASS — free-roam $AREA cleared to the boss (DONE ok)"
	exit 0
fi
echo "[record-freeroam] FAIL — free-roam $AREA did not reach DONE ok. Tail:" >&2
grep -E '\[sanity\] (FAIL|stuck-walk|WARN)' "$SANITY" | tail -5 >&2 || true
exit 1
