#!/usr/bin/env bash
# Multi-quest matrix: Boot → SR → [PP_canon | PP_backtrack] → [AS_canon | AS_moon | AS_sol]
# Sequential phases for the linear save-state dependencies, parallel phases for
# variants that share the same upstream save.
#
# Per-branch isolation via XDG_DATA_HOME — Godot reads its user_data_dir from
# $XDG_DATA_HOME/godot/app_userdata/PSZ Godot/ when set, defaulting to
# ~/.local/share otherwise. Each parallel branch gets its own scratch dir
# with a copy of the upstream save so the godot processes don't fight over
# the same save_data.json.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG=/tmp/quest_matrix.log
exec >"$LOG" 2>&1

GODOT="/home/kion/.local/bin/godot"
OUTDIR="$REPO/spec/public/recordings"
PACK="$REPO/dist/assets.pck"
GODOT_DEFAULT_USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
SCRATCH=/tmp/quest_matrix_scratch
mkdir -p "$SCRATCH"

PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"

# Set up the local-pack manifest once; each godot reads it
MANIFEST_BAK="$(mktemp)"
cp "$REPO/assets_manifest.json" "$MANIFEST_BAK"
cat > "$REPO/assets_manifest.json" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON
trap '[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$REPO/assets_manifest.json" && rm -f "$MANIFEST_BAK"' EXIT

# Run a godot autopilot phase. $1 = phase tag (used for output filename),
# $2 = optional PSZ_AUTOPILOT_QUEST (empty = default search_and_rescue),
# $3 = userdir (XDG_DATA_HOME root, "" for default location).
run_godot() {
  local tag=$1
  local quest=$2
  local userdir=$3
  local stamp; stamp=$(date -u +%Y%m%d-%H%M%S)
  local avi="$OUTDIR/${tag}_${stamp}.avi"
  local mp4="$OUTDIR/${tag}_${stamp}.mp4"
  local sanity="$OUTDIR/${tag}_${stamp}.sanity.log"
  local json="$OUTDIR/${tag}_${stamp}.json"

  echo "[matrix] $tag start quest=${quest:-(SR default)} userdir=${userdir:-(default)} → $sanity"

  # Bash treats variable-expanded `VAR=value` as a command name, not an
  # assignment, so use explicit `env` to pass the per-branch overrides.
  # Empty values are harmless: PSZ_AUTOPILOT_QUEST="" defaults to the
  # hardcoded search_and_rescue path, and XDG_DATA_HOME="" makes Godot
  # fall back to $HOME/.local/share per XDG spec.
  local start_ts; start_ts=$(date -u +%s)
  env \
    PSZ_AUTOPILOT=1 \
    PSZ_AUTOPILOT_PHASE=first-mission \
    PSZ_AUTOPILOT_NO_OBSTACLES=1 \
    PSZ_AUTOPILOT_NO_BOXES=1 \
    PSZ_AUTOPILOT_QUEST="$quest" \
    XDG_DATA_HOME="$userdir" \
    LIBGL_ALWAYS_SOFTWARE=1 \
    xvfb-run -a -s "-screen 0 640x360x24" \
    timeout 1500 "$GODOT" --write-movie "$avi" --fixed-fps 30 \
    --disable-vsync --audio-driver Dummy --path "$REPO" >"$sanity" 2>&1
  local rc=$?
  local end_ts; end_ts=$(date -u +%s)

  local status="fail"; local fail_reason=""
  if [ "$rc" -eq 0 ] && grep -qF '[sanity] DONE ok' "$sanity"; then
    status="pass"
  elif [ "$rc" -ne 0 ]; then
    fail_reason="godot exit $rc"
  else
    fail_reason="autopilot did not reach DONE checkpoint"
  fi

  cat > "$json" <<JSON
{
  "phase": "$tag",
  "status": "$status",
  "godot_exit": $rc,
  "captured_at": "$(date -u -d "@$start_ts" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((end_ts - start_ts)),
  "fail_reason": "$fail_reason",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$sanity" || echo 0)
}
JSON

  if [ -s "$avi" ]; then
    ffmpeg -y -loglevel error -i "$avi" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$mp4" 2>&1 && rm -f "$avi"
  fi

  echo "[matrix] $tag $status (rc=$rc, $((end_ts - start_ts))s) → $mp4"
}

# Stage a scratch userdir with a copy of the post-phase save state.
# $1 = scratch dir path, $2 = source PSZ Godot userdir to copy.
stage_userdir() {
  local dest=$1
  local src=$2
  rm -rf "$dest"
  mkdir -p "$dest/godot/app_userdata"
  cp -r "$src" "$dest/godot/app_userdata/PSZ Godot"
}

# Resume support — skip already-completed upstream phases when iterating on
# downstream variants. Pass `--from <phase>` where phase is one of:
#   sr  (default) — run everything from Boot
#   pp            — skip Boot+SR, expect $SCRATCH/post-sr to exist
#   as            — skip Boot+SR+PP, expect $SCRATCH/post-pp to exist
# The post-SR and post-PP snapshots are written automatically by the
# matrix on a full run, so iterate-from-AS works any time the previous run
# made it past Phase 3.
FROM="sr"
case "${1:-}" in
  --from)
    FROM="${2:-sr}"
    ;;
  --from=*)
    FROM="${1#--from=}"
    ;;
esac

echo "=== matrix start $(date -u +%FT%TZ) from=$FROM ==="

if [ "$FROM" = "sr" ]; then
  # === Phase 1: Boot (default userdir, wipes the save) ===
  echo ""; echo "=== Phase 1: Boot ==="
  bash "$REPO/scripts/tools/autoplay/record_boot.sh"

  # === Phase 2: SR (default userdir, builds the save SR+PP need) ===
  echo ""; echo "=== Phase 2: SR ==="
  bash "$REPO/scripts/tools/autoplay/record_first_mission.sh"

  # Snapshot post-SR for the two parallel PP branches
  echo ""; echo "[matrix] snapshotting post-SR save → $SCRATCH/post-sr"
  rm -rf "$SCRATCH/post-sr"
  cp -r "$GODOT_DEFAULT_USERDIR" "$SCRATCH/post-sr"
elif [ "$FROM" = "pp" ]; then
  echo ""; echo "=== SKIP Phase 1 + 2: --from=pp (expects $SCRATCH/post-sr) ==="
  [ -d "$SCRATCH/post-sr" ] || { echo "ERROR: $SCRATCH/post-sr missing — run a full matrix first to seed it"; exit 2; }
elif [ "$FROM" = "as" ]; then
  echo ""; echo "=== SKIP Phase 1, 2, 3: --from=as (expects $SCRATCH/post-pp) ==="
  [ -d "$SCRATCH/post-pp" ] || { echo "ERROR: $SCRATCH/post-pp missing — run a full matrix first to seed it"; exit 2; }
else
  echo "ERROR: --from must be sr|pp|as (got '$FROM')"; exit 2
fi

if [ "$FROM" != "as" ]; then
  # === Phase 3: PP canon || PP backtrack (parallel) ===
  echo ""; echo "=== Phase 3: PP canonical + PP backtrack (parallel) ==="
  stage_userdir "$SCRATCH/pp-canon" "$SCRATCH/post-sr"
  stage_userdir "$SCRATCH/pp-backtrack" "$SCRATCH/post-sr"

  run_godot "pp_canon" "the_paru_pact" "$SCRATCH/pp-canon" &
  PID_PP1=$!
  sleep 2
  run_godot "pp_backtrack" "the_paru_pact_backtrack" "$SCRATCH/pp-backtrack" &
  PID_PP2=$!

  wait $PID_PP1 $PID_PP2
  echo "[matrix] Phase 3 done — PP_canon + PP_backtrack both finished"

  # === Phase 4: snapshot canonical PP save for AS branches ===
  echo ""; echo "[matrix] snapshotting post-PP_canon save → $SCRATCH/post-pp"
  rm -rf "$SCRATCH/post-pp"
  cp -r "$SCRATCH/pp-canon/godot/app_userdata/PSZ Godot" "$SCRATCH/post-pp"
else
  echo ""; echo "=== SKIP Phase 3 + 4: --from=as (reusing $SCRATCH/post-pp) ==="
fi

# === Phase 5: AS canon || AS moon_last || AS sol_last (parallel) ===
echo ""; echo "=== Phase 5: AS canonical + AS moon_last + AS sol_last (parallel) ==="
stage_userdir "$SCRATCH/as-canon" "$SCRATCH/post-pp"
stage_userdir "$SCRATCH/as-moon" "$SCRATCH/post-pp"
stage_userdir "$SCRATCH/as-sol" "$SCRATCH/post-pp"

run_godot "as_canon" "apothecary_supply" "$SCRATCH/as-canon" &
PID_AS1=$!
sleep 2
run_godot "as_moon" "apothecary_supply_moon_last" "$SCRATCH/as-moon" &
PID_AS2=$!
sleep 2
run_godot "as_sol" "apothecary_supply_sol_last" "$SCRATCH/as-sol" &
PID_AS3=$!

wait $PID_AS1 $PID_AS2 $PID_AS3
echo "[matrix] Phase 5 done — all 3 AS variants finished"

echo ""; echo "=== matrix done $(date -u +%FT%TZ) ==="
