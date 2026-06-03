#!/usr/bin/env bash
# Full autopilot regression harness.
#
# Runs every plan-driven quest in manifest dependency order, snapshotting the
# post-quest save after each completion so the next quest in the chain has a
# valid starting state. Each quest emits a JSON sidecar (see run_quest_matrix.sh)
# we aggregate into a final regression_report.json.
#
# Quests covered (in order):
#   Boot              (via record_boot.sh)
#   SR                (via record_first_mission.sh, hardcoded steps — refactor control)
#   PP canon + backtrack  (parallel from post-SR)
#   AS canon + moon + sol (parallel from post-PP_canon)
#   DOE               (sequential from post-AS_canon)
#   static_in_the_snow (sequential from post-DOE) — currently unreachable from
#                       post-DOE save without finishing FO first, so this slot
#                       will fail at the guild counter until FO lands. Kept in
#                       the chain so the report flags it.
#   finding_ogi       (sequential from post-static, or from post-AS canon if
#                       static unreachable) — the work target.
#
# Resume:  --from <quest_id>  to skip already-completed upstream phases.
# Output:  /tmp/quest_matrix_scratch/regression_report.json
#          /tmp/regression_matrix.log (full bash log)
#
# Use:
#   bash scripts/tools/autoplay/run_regression_matrix.sh
#   bash scripts/tools/autoplay/run_regression_matrix.sh --from doe
#   bash scripts/tools/autoplay/run_regression_matrix.sh --report-only
#
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG=/tmp/regression_matrix.log
SCRATCH=/tmp/quest_matrix_scratch
REPORT="$SCRATCH/regression_report.json"
GODOT="/home/kion/.local/bin/godot"
OUTDIR="$REPO/spec/public/recordings"
PACK="$REPO/dist/assets.pck"
GODOT_DEFAULT_USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"

mkdir -p "$SCRATCH"

PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"

# Per-quest config: id, label, upstream save dir, tag prefix (for sidecar/mp4 names).
# Order matters — earlier quests must finish before later ones run.
# The PP and AS variants are handled separately because they run in parallel.

# --- Parse args ---
FROM=""
REPORT_ONLY=0
RUN_START_ISO="$(date -u +%FT%TZ)"
case "${1:-}" in
  --from)         FROM="${2:-}" ;;
  --from=*)       FROM="${1#--from=}" ;;
  --report-only)  REPORT_ONLY=1 ;;
esac

# When report-only, skip everything and just aggregate existing sidecars.
if [ "$REPORT_ONLY" -ne 1 ]; then
  exec >"$LOG" 2>&1
  echo "=== regression matrix start $RUN_START_ISO from=${FROM:-(beginning)} ==="

  # Local-pack manifest setup (same pattern as run_quest_matrix.sh)
  MANIFEST_BAK="$(mktemp)"
  cp "$REPO/assets_manifest.json" "$MANIFEST_BAK"
  cat > "$REPO/assets_manifest.json" <<JSON
{ "version": "sanity", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://LOCAL_DIST/assets.pck"] } }
JSON
  trap '[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$REPO/assets_manifest.json" && rm -f "$MANIFEST_BAK"; echo "[regression] manifest restored"' EXIT

  # --- run_godot: same shape as run_quest_matrix.sh's helper ---
  run_godot() {
    local tag=$1
    local quest=$2
    local userdir=$3
    local stamp; stamp=$(date -u +%Y%m%d-%H%M%S)
    local avi="$OUTDIR/${tag}_${stamp}.avi"
    local mp4="$OUTDIR/${tag}_${stamp}.mp4"
    local sanity="$OUTDIR/${tag}_${stamp}.sanity.log"
    local json="$OUTDIR/${tag}_${stamp}.json"

    echo "[regression] $tag start quest=${quest:-(SR default)} userdir=${userdir:-(default)} → $sanity"

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
      timeout 1800 "$GODOT" --write-movie "$avi" --fixed-fps 30 \
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

    echo "[regression] $tag $status (rc=$rc, $((end_ts - start_ts))s) → $mp4"
  }

  stage_userdir() {
    local dest=$1
    local src=$2
    rm -rf "$dest"
    mkdir -p "$dest/godot/app_userdata"
    cp -r "$src" "$dest/godot/app_userdata/PSZ Godot"
  }

  # --- Resume guards ---
  reached() {
    # reached <stage> returns 0 if FROM is unset or alphabetically <= stage
    # so we can use a string compare as a "this phase or later" gate.
    local stage=$1
    case "$stage:$FROM" in
      *":")                       return 0 ;;  # no --from → run everything
      "boot:boot")                return 0 ;;
      "sr:boot"|"sr:sr")          return 0 ;;
      "pp:boot"|"pp:sr"|"pp:pp")  return 0 ;;
      "as:boot"|"as:sr"|"as:pp"|"as:as") return 0 ;;
      "doe:boot"|"doe:sr"|"doe:pp"|"doe:as"|"doe:doe") return 0 ;;
      "fo:boot"|"fo:sr"|"fo:pp"|"fo:as"|"fo:doe"|"fo:fo") return 0 ;;
      "static:"*) return 0 ;;  # static is always last; honour any --from
    esac
    return 1
  }

  # === Phase 1: Boot ===
  if reached boot; then
    echo ""; echo "=== Phase 1: Boot ==="
    bash "$REPO/scripts/tools/autoplay/record_boot.sh"
  fi

  # === Phase 2: SR ===
  if reached sr; then
    echo ""; echo "=== Phase 2: SR (search_and_rescue) ==="
    bash "$REPO/scripts/tools/autoplay/record_first_mission.sh"
    echo "[regression] snapshotting post-SR save → $SCRATCH/post-sr"
    rm -rf "$SCRATCH/post-sr"
    cp -r "$GODOT_DEFAULT_USERDIR" "$SCRATCH/post-sr"
  fi

  # === Phase 3: PP canon + PP backtrack (parallel) ===
  if reached pp; then
    [ -d "$SCRATCH/post-sr" ] || { echo "[regression] ERROR: $SCRATCH/post-sr missing for PP"; exit 2; }
    echo ""; echo "=== Phase 3: PP canon + PP backtrack ==="
    stage_userdir "$SCRATCH/pp-canon" "$SCRATCH/post-sr"
    stage_userdir "$SCRATCH/pp-backtrack" "$SCRATCH/post-sr"
    run_godot "pp_canon" "the_paru_pact" "$SCRATCH/pp-canon" &
    local_pid_pp1=$!
    sleep 2
    run_godot "pp_backtrack" "the_paru_pact_backtrack" "$SCRATCH/pp-backtrack" &
    local_pid_pp2=$!
    wait $local_pid_pp1 $local_pid_pp2
    echo "[regression] snapshotting post-PP_canon save → $SCRATCH/post-pp"
    rm -rf "$SCRATCH/post-pp"
    cp -r "$SCRATCH/pp-canon/godot/app_userdata/PSZ Godot" "$SCRATCH/post-pp"
  fi

  # === Phase 4: AS canon + AS moon + AS sol (parallel) ===
  if reached as; then
    [ -d "$SCRATCH/post-pp" ] || { echo "[regression] ERROR: $SCRATCH/post-pp missing for AS"; exit 2; }
    echo ""; echo "=== Phase 4: AS canon + AS moon + AS sol ==="
    stage_userdir "$SCRATCH/as-canon" "$SCRATCH/post-pp"
    stage_userdir "$SCRATCH/as-moon"  "$SCRATCH/post-pp"
    stage_userdir "$SCRATCH/as-sol"   "$SCRATCH/post-pp"
    run_godot "as_canon" "apothecary_supply" "$SCRATCH/as-canon" &
    local_pid_as1=$!
    sleep 2
    run_godot "as_moon" "apothecary_supply_moon_last" "$SCRATCH/as-moon" &
    local_pid_as2=$!
    sleep 2
    run_godot "as_sol" "apothecary_supply_sol_last" "$SCRATCH/as-sol" &
    local_pid_as3=$!
    wait $local_pid_as1 $local_pid_as2 $local_pid_as3
    echo "[regression] snapshotting post-AS_canon save → $SCRATCH/post-as"
    rm -rf "$SCRATCH/post-as"
    cp -r "$SCRATCH/as-canon/godot/app_userdata/PSZ Godot" "$SCRATCH/post-as"
  fi

  # === Phase 5: DOE (sequential) ===
  if reached doe; then
    [ -d "$SCRATCH/post-as" ] || { echo "[regression] ERROR: $SCRATCH/post-as missing for DOE"; exit 2; }
    echo ""; echo "=== Phase 5: DOE (deep_ore_extraction) ==="
    stage_userdir "$SCRATCH/doe" "$SCRATCH/post-as"
    run_godot "doe" "deep_ore_extraction" "$SCRATCH/doe"
    echo "[regression] snapshotting post-DOE save → $SCRATCH/post-doe"
    rm -rf "$SCRATCH/post-doe"
    cp -r "$SCRATCH/doe/godot/app_userdata/PSZ Godot" "$SCRATCH/post-doe"
  fi

  # === Phase 6: static_in_the_snow (sequential) ===
  # === Phase 6: finding_ogi (sequential, unlocks SIS) ===
  if reached fo; then
    # FO is unlocked directly after AS per the manifest graph. Snapshot
    # the post-FO save so Phase 7 can resume from a state where SIS is
    # actually selectable at the guild counter.
    [ -d "$SCRATCH/post-as" ] || { echo "[regression] ERROR: $SCRATCH/post-as missing for FO"; exit 2; }
    echo ""; echo "=== Phase 6: finding_ogi ==="
    stage_userdir "$SCRATCH/fo" "$SCRATCH/post-as"
    run_godot "fo" "finding_ogi" "$SCRATCH/fo"
    LATEST_FO=$(ls -t "$OUTDIR"/fo_*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_FO" ] && jq -e '.status == "pass"' "$LATEST_FO" >/dev/null 2>&1; then
      echo "[regression] snapshotting post-FO save → $SCRATCH/post-fo"
      rm -rf "$SCRATCH/post-fo"
      cp -r "$SCRATCH/fo/godot/app_userdata/PSZ Godot" "$SCRATCH/post-fo"
    fi
  fi

  # === Phase 7: static_in_the_snow (sequential, after FO unlocks it) ===
  if reached static; then
    # Prefer the post-FO save (where SIS is unlocked). Fall back to
    # post-DOE if FO didn't snapshot — that path still exercises the
    # "guild won't let me accept" failure mode, with a per-quest
    # timeout so the matrix doesn't sit for 30 minutes.
    SIS_SRC="$SCRATCH/post-fo"
    if [ ! -d "$SIS_SRC" ]; then
      SIS_SRC="$SCRATCH/post-doe"
      echo "[regression] WARN: post-fo missing — SIS will run from post-doe and is expected to fail"
    fi
    [ -d "$SIS_SRC" ] || { echo "[regression] ERROR: no save state available for SIS"; exit 2; }
    echo ""; echo "=== Phase 7: static_in_the_snow ==="
    stage_userdir "$SCRATCH/sis" "$SIS_SRC"
    run_godot "sis" "static_in_the_snow" "$SCRATCH/sis"
  fi

  echo ""; echo "=== regression matrix done $(date -u +%FT%TZ) ==="
fi

# --- Aggregate sidecars into regression_report.json ---
# Pick the most recent sidecar per tag from this run window so a partial
# rerun replaces the older entry.
echo ""
echo "[regression] building $REPORT"
TMPREPORT="$(mktemp)"
echo '{"started_at":"'"$RUN_START_ISO"'","quests":[' > "$TMPREPORT"
FIRST=1
for tag in boot first_mission pp_canon pp_backtrack as_canon as_moon as_sol doe fo sis; do
  # Newest sidecar JSON for this tag prefix
  latest=$(ls -t "$OUTDIR"/${tag}_*.json 2>/dev/null | head -1)
  if [ -z "$latest" ]; then continue; fi
  if [ "$FIRST" -ne 1 ]; then echo ',' >> "$TMPREPORT"; fi
  FIRST=0
  cat "$latest" >> "$TMPREPORT"
done
echo ']}' >> "$TMPREPORT"
# Pretty-print
jq '.' "$TMPREPORT" > "$REPORT" 2>/dev/null || cp "$TMPREPORT" "$REPORT"
rm -f "$TMPREPORT"

echo "[regression] report: $REPORT"
cat "$REPORT" | jq -r '.quests[] | "  \(.phase): \(.status)  (\(.duration_sec)s)"' 2>/dev/null || cat "$REPORT"
