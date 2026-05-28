#!/usr/bin/env bash
#
# record_run — render the autopilot boot run to an mp4 for visual review.
#
# This box is headless, so we render under Xvfb (a virtual X display) using
# Godot's Movie Maker (--write-movie), which writes one frame per fixed-fps
# tick (deterministic, decoupled from wall-clock), then transcode AVI→mp4.
# Same preconditions as sanity_check.sh: fresh first-run player state + the
# local dist pack via the file://LOCAL_DIST mirror (offline). DEV-BOX ONLY.
#
# Output: $OUTDIR/sanity_run.mp4 (default /tmp/autoplay_review).
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
# Recordings land in the spec site's public/ (gitignored) so they show up in
# the /autopilot Recordings gallery, served by the Astro dev server.
OUTDIR="${OUTDIR:-$REPO/spec/public/recordings}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
AVI="$OUTDIR/sanity_run_$STAMP.avi"
MP4="$OUTDIR/sanity_run_$STAMP.mp4"
FPS="${FPS:-30}"
TIMEOUT="${REC_TIMEOUT:-180}"

MANIFEST_BAK="$(mktemp)"
cleanup() { [ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"; }
trap cleanup EXIT

[ -f "$PACK" ] || { echo "[record] ERROR: $PACK not found" >&2; exit 1; }
mkdir -p "$OUTDIR"
rm -f "$AVI" "$MP4"

# Fresh first-run player state (keep packs/ so boot is snappy — cache-hit).
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"

# Offline manifest pointing at the local pack.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON

echo "[record] rendering autopilot run under Xvfb → $AVI (fps=$FPS)"
PSZ_AUTOPILOT=1 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
	timeout "$TIMEOUT" "$GODOT" --write-movie "$AVI" --fixed-fps "$FPS" \
	--disable-vsync --audio-driver Dummy --path "$REPO"
RC=$?
echo "[record] godot rc=$RC"
[ -s "$AVI" ] || { echo "[record] ERROR: no AVI frames produced" >&2; exit 1; }

echo "[record] transcoding → $MP4"
ffmpeg -y -loglevel error -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$MP4" || {
	echo "[record] ffmpeg failed" >&2; exit 1; }
rm -f "$AVI"
ls -lh "$MP4"
echo "[record] done: $MP4"
