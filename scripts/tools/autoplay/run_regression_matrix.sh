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
#   finding_ogi       (sequential from post-AS_canon) — unlocks the endgame.
#   static_in_the_snow (sequential from post-FO) — side branch off FO.
#   --- core story endgame spine (each from the previous quest's post-save) ---
#   investigate_tower (from post-FO)
#   heretic           (from post-IT)
#   control_system    (from post-heretic)
#   the_broken_seal   (from post-CSY)
#   dark_castle       (from post-TBS) — credits-gating final quest.
#
# Chain integrity: each endgame quest resumes from its parent_quest's
# post-save so the guild counter surfaces it (see the
# feedback_test_chain_must_make_unlocks_reachable note). If an upstream
# quest fails, its post-save is NOT written, and the downstream phases
# skip with a warning rather than running from a stale state.
#
# Resume:  --from <quest_id>  to skip already-completed upstream phases.
#          Stages, in order: boot sr pp as doe fo static it heretic csy tbs dc
# Speed:   --speed N   set autopilot time_scale (default 3x; physics ticks
#                       scale with it so collision stays accurate). 3x is the
#                       only VALIDATED speed — higher is best-effort: at 6x the
#                       city/guild quest-accept flow loops forever and the
#                       engine crashed mid-quest. Warns past 3x.
#          --fast      alias for --speed 4 (modest smoke bump; still unvalidated).
# Output:  /tmp/quest_matrix_scratch/regression_report.json
#          /tmp/regression_matrix.log (full bash log)
#
# Use:
#   bash scripts/tools/autoplay/run_regression_matrix.sh
#   bash scripts/tools/autoplay/run_regression_matrix.sh --from doe
#   bash scripts/tools/autoplay/run_regression_matrix.sh --from it --fast
#   bash scripts/tools/autoplay/run_regression_matrix.sh --speed 5
#   bash scripts/tools/autoplay/run_regression_matrix.sh --report-only
#
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG=/tmp/regression_matrix.log
SCRATCH=/tmp/quest_matrix_scratch
REPORT="$SCRATCH/regression_report.json"
MATRIX_FAIL=0  # post-build state assertions (e.g. #344) flip this; exit reflects it
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
SELF_TEST=0
SPEED=""          # empty → autopilot's built-in default (3x)
RUN_START_ISO="$(date -u +%FT%TZ)"
while [ $# -gt 0 ]; do
  case "$1" in
    --from)         FROM="${2:-}"; shift 2 ;;
    --from=*)       FROM="${1#--from=}"; shift ;;
    --speed)        SPEED="${2:-}"; shift 2 ;;
    --speed=*)      SPEED="${1#--speed=}"; shift ;;
    --fast)         SPEED="4"; shift ;;
    --report-only)  REPORT_ONLY=1; shift ;;
    --self-test)    SELF_TEST=1; shift ;;
    *)              echo "unknown arg: $1" >&2; shift ;;
  esac
done

# Decide whether a failed quest attempt is a retryable intermittent flake
# (the ~3.6-unit exit-approach stuck-walk, or a timeout/hang) vs a real
# failure (logic [sanity] FAIL, parse/script error, other non-zero exit).
# Args: <sanity_log> <rc>. Returns 0 = retry, 1 = fail immediately. (#313)
# Defined at top level so run_godot uses it AND `--self-test` can check it.
_is_retryable_flake() {
  local sanity=$1 rc=$2
  # Timeout / hang (budget SIGTERM).
  [ "$rc" -eq 124 ] && return 0
  # Navigation stuck-walk stall: floor present but the walk primitive isn't
  # advancing toward an exit waypoint. The specific actionable failure line.
  if [ -f "$sanity" ] && grep -qF '[sanity] FAIL: walk stuck' "$sanity"; then
    return 0
  fi
  # Everything else (real [sanity] FAIL asserts, parse/script errors, other
  # non-zero exits, "did not reach DONE") is a genuine failure — fail fast.
  return 1
}

# `--self-test`: fixture-check the flake classifier and exit. Fast, pack-free —
# this is the CI-runnable regression guard for the retry gate (#313).
if [ "$SELF_TEST" -eq 1 ]; then
  _t_pass=0; _t_fail=0
  _expect() {  # <desc> <expected 0|1> <sanity_file> <rc>
    if _is_retryable_flake "$3" "$4"; then _got=0; else _got=1; fi
    if [ "$_got" -eq "$2" ]; then echo "  PASS: $1"; _t_pass=$((_t_pass+1));
    else echo "  FAIL: $1 (got $_got, want $2)"; _t_fail=$((_t_fail+1)); fi
  }
  _tmp=$(mktemp -d)
  printf '[sanity] FAIL: walk stuck at dist=3.63 in cell 4,3 (stage s06a_td1) — author waypoints\n' > "$_tmp/stuck.log"
  printf '[sanity] checkpoint: quest accepted\n[sanity] FAIL: quest objective mismatch\n' > "$_tmp/assert.log"
  printf '[sanity] checkpoint: title\nSCRIPT ERROR: Parse Error: boom\n' > "$_tmp/parse.log"
  printf '[sanity] DONE ok\n' > "$_tmp/ok.log"
  echo "── run_regression_matrix --self-test: _is_retryable_flake ──"
  _expect "stuck-walk (rc=1) → retry"                 0 "$_tmp/stuck.log" 1
  _expect "timeout (rc=124) → retry"                  0 "$_tmp/ok.log"    124
  _expect "stuck-walk also wins under rc=124"         0 "$_tmp/stuck.log" 124
  _expect "real [sanity] FAIL assert (rc=1) → no retry" 1 "$_tmp/assert.log" 1
  _expect "parse/script error (rc=1) → no retry"      1 "$_tmp/parse.log" 1
  _expect "clean-ish non-stuck rc=1 → no retry"       1 "$_tmp/ok.log"   1
  rm -rf "$_tmp"
  echo "── self-test: $_t_pass passed, $_t_fail failed ──"
  [ "$_t_fail" -eq 0 ] && exit 0 || exit 1
fi

# Build the env assignment passed to each godot run. Empty when SPEED is
# unset, so `env ... $SPEED_ENV ...` simply contributes no argument and the
# autopilot falls back to its own 3x default.
# dbus-run-session gives each godot launch a private session bus so its
# AccessKit layer can't SIGABRT (exit 134) when the box's ambient a11y bus is
# absent. Optional: run without it (and warn) if not installed, so a missing
# dep doesn't read as every phase "failing".
DBUS_WRAP=""
if command -v dbus-run-session >/dev/null 2>&1; then
  DBUS_WRAP="dbus-run-session --"
else
  echo "[regression] WARN: dbus-run-session not found — running without a private DBus session; godot may SIGABRT if no ambient a11y bus is present." >&2
fi

SPEED_ENV=""
if [ -n "$SPEED" ]; then
  # Validate before passing through: autopilot.gd does float($PSZ_AUTOPILOT_TIME_SCALE),
  # so a non-numeric value (e.g. "fast", "4x") would silently coerce toward 0 and
  # destabilize the run. Fail fast with a clear message instead.
  case "$SPEED" in
    *[!0-9.]* | *.*.* | .) echo "[regression] ERROR: --speed must be a positive number (got '$SPEED')" >&2; exit 2 ;;
  esac
  if [ "$(awk -v s="$SPEED" 'BEGIN{print (s+0>0)?1:0}')" != "1" ]; then
    echo "[regression] ERROR: --speed must be > 0 (got '$SPEED')" >&2; exit 2
  fi
  SPEED_ENV="PSZ_AUTOPILOT_TIME_SCALE=$SPEED"
  # 3x is the validated default. Higher is best-effort: at 6x the
  # city/guild quest-accept flow loops indefinitely (office<->counter)
  # and the engine crashed mid-quest (heretic). Warn past 3x.
  if [ "$(awk -v s="$SPEED" 'BEGIN{print (s+0>3)?1:0}')" = "1" ]; then
    echo "[regression] WARN: speed ${SPEED}x exceeds the validated 3x — full quest flow may loop or crash (6x is known-bad). Use for stage-pathfinding smoke only." >&2
  fi
fi

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
    # Per-quest wall-clock budget (happy-path + margin). Defaults to 1200s if a
    # caller doesn't pass one. A hang now fails in ~minutes, not the old flat 30.
    local timeout_s=${4:-1200}
    local stamp; stamp=$(date -u +%Y%m%d-%H%M%S)
    local avi="$OUTDIR/${tag}_${stamp}.avi"
    local mp4="$OUTDIR/${tag}_${stamp}.mp4"
    local sanity="$OUTDIR/${tag}_${stamp}.sanity.log"
    local json="$OUTDIR/${tag}_${stamp}.json"

    # Retry intermittent navigation flakes (the ~3.6-unit exit-approach
    # stuck-walk, and timeout/hangs) so a flake doesn't spuriously red the
    # gate (#313). Re-run from a clean copy of the staged userdir each attempt,
    # since a stuck run mutates the save. Real [sanity] asserts / parse errors
    # fail immediately. Tune attempts with QUEST_MAX_ATTEMPTS (default 3).
    local max_attempts=${QUEST_MAX_ATTEMPTS:-3}
    local seed=""
    if [ -n "$userdir" ] && [ -d "$userdir" ]; then
      seed=$(mktemp -d); cp -r "$userdir/." "$seed/" 2>/dev/null || true
    fi

    local attempt=1 rc=0 status="fail" fail_reason="" start_ts=0 end_ts=0
    while : ; do
      if [ "$attempt" -gt 1 ] && [ -n "$seed" ]; then
        rm -rf "$userdir"; mkdir -p "$userdir"; cp -r "$seed/." "$userdir/" 2>/dev/null || true
      fi
      echo "[regression] $tag start quest=${quest:-(SR default)} userdir=${userdir:-(default)} attempt=$attempt/$max_attempts speed=${SPEED:-3(default)} timeout=${timeout_s}s → $sanity"

      start_ts=$(date -u +%s)
      env \
        PSZ_AUTOPILOT=1 \
        PSZ_AUTOPILOT_PHASE=first-mission \
        PSZ_AUTOPILOT_NO_OBSTACLES=1 \
        PSZ_AUTOPILOT_NO_BOXES=1 \
        PSZ_AUTOPILOT_QUEST="$quest" \
        $SPEED_ENV \
        XDG_DATA_HOME="$userdir" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        $DBUS_WRAP \
        xvfb-run -a -s "-screen 0 640x360x24" \
        timeout "$timeout_s" "$GODOT" --write-movie "$avi" --fixed-fps 30 \
        --disable-vsync --audio-driver Dummy --path "$REPO" >"$sanity" 2>&1
      rc=$?
      end_ts=$(date -u +%s)

      status="fail"; fail_reason=""
      if [ "$rc" -eq 0 ] && grep -qF '[sanity] DONE ok' "$sanity"; then
        status="pass"
      elif [ "$rc" -eq 124 ]; then
        # `timeout` SIGTERMs at the budget → exit 124.
        fail_reason="timed out after ${timeout_s}s (budget) — hung or slower than expected"
      elif [ "$rc" -ne 0 ]; then
        fail_reason="godot exit $rc"
      else
        fail_reason="autopilot did not reach DONE checkpoint"
      fi

      if [ "$status" = "pass" ]; then
        [ "$attempt" -gt 1 ] && echo "[regression] $tag passed on attempt $attempt (earlier attempt was an intermittent flake)"
        break
      fi
      if [ "$attempt" -lt "$max_attempts" ] && _is_retryable_flake "$sanity" "$rc"; then
        echo "[regression] $tag flake on attempt $attempt/$max_attempts ($fail_reason) — retrying from clean save"
        attempt=$((attempt + 1)); continue
      fi
      break
    done
    [ -n "$seed" ] && rm -rf "$seed"

    cat > "$json" <<JSON
{
  "phase": "$tag",
  "status": "$status",
  "godot_exit": $rc,
  "attempts": $attempt,
  "captured_at": "$(date -u -d "@$start_ts" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": $((end_ts - start_ts)),
  "fail_reason": "$fail_reason",
  "checkpoints": $(grep -cE '^\[sanity\] checkpoint:' "$sanity" || echo 0)
}
JSON

    if [ -s "$avi" ]; then
      ffmpeg -y -loglevel error -i "$avi" -c:v libx264 -pix_fmt yuv420p -crf 28 -movflags +faststart "$mp4" 2>&1 && rm -f "$avi"
    fi

    echo "[regression] $tag $status (rc=$rc, $((end_ts - start_ts))s, attempt $attempt/$max_attempts) → $mp4"
  }

  stage_userdir() {
    local dest=$1
    local src=$2
    rm -rf "$dest"
    mkdir -p "$dest/godot/app_userdata"
    cp -r "$src" "$dest/godot/app_userdata/PSZ Godot"
  }

  # --- Resume guards ---
  # Execution order of the phases. `reached <stage>` returns 0 (run it) when
  # no --from was given, or when <stage> is at-or-after FROM in this order.
  PHASE_ORDER=(boot sr pp as doe fo static it heretic csy tbs dc shops)
  phase_index() {
    local name=$1 i=0
    for p in "${PHASE_ORDER[@]}"; do
      [ "$p" = "$name" ] && { echo "$i"; return; }
      i=$((i + 1))
    done
    echo -1
  }
  reached() {
    local stage=$1
    [ -z "$FROM" ] && return 0          # no --from → run everything
    local si fi
    si=$(phase_index "$stage")
    fi=$(phase_index "$FROM")
    if [ "$fi" -lt 0 ]; then
      echo "[regression] WARN: unknown --from '$FROM' — running all phases" >&2
      return 0
    fi
    [ "$fi" -le "$si" ]                 # run this phase iff FROM is at/before it
  }

  # run_chain_phase <tag> <quest_id> <parent_post> <child_post> <label> [timeout_s]
  # timeout_s is the per-quest wall-clock budget (default 900s), forwarded to
  # run_godot. Resume from the parent's post-save, run the quest, and snapshot the
  # child post-save ONLY if the quest passed. If the parent post-save is
  # missing (upstream failed/skipped), skip this phase with a warning so
  # the chain degrades gracefully instead of running from a stale state.
  run_chain_phase() {
    local tag=$1 quest=$2 parent_post=$3 child_post=$4 label=$5 timeout_s=${6:-900}
    if [ ! -d "$SCRATCH/$parent_post" ]; then
      echo ""; echo "=== $label ==="
      echo "[regression] SKIP $tag — $SCRATCH/$parent_post missing (upstream did not pass)"
      return 0
    fi
    echo ""; echo "=== $label ==="
    stage_userdir "$SCRATCH/$tag" "$SCRATCH/$parent_post"
    run_godot "$tag" "$quest" "$SCRATCH/$tag" "$timeout_s"
    local latest; latest=$(ls -t "$OUTDIR"/${tag}_*.json 2>/dev/null | head -1)
    if [ -n "$latest" ] && jq -e '.status == "pass"' "$latest" >/dev/null 2>&1; then
      echo "[regression] snapshotting $tag post-save → $SCRATCH/$child_post"
      rm -rf "$SCRATCH/$child_post"
      cp -r "$SCRATCH/$tag/godot/app_userdata/PSZ Godot" "$SCRATCH/$child_post"
    else
      # Invalidate any stale child snapshot from a prior run so the
      # downstream phase's `[ -d ]` parent check fails and it skips —
      # otherwise it would resume from an out-of-date save.
      echo "[regression] $tag did not pass — clearing stale $child_post so downstream phases skip"
      rm -rf "$SCRATCH/$child_post"
    fi
  }

  # Regenerate the global class cache before any from-source run. Without this, a
  # newly-added `class_name` script (e.g. an extracted module) isn't registered,
  # so any script referencing it fails to parse → the field scene silently fails
  # to load (gray screen) and the autopilot stalls reading an empty cell. Same
  # class of gotcha as needing a reimport after editing GLBs. Headless editor
  # import, ~30-60s; harmless on resumes.
  echo "[regression] reimport: regenerating class cache (so new class_name scripts resolve)…"
  REIMPORT_LOG="$OUTDIR/reimport_${RUN_START_ISO//:/-}.log"
  if timeout 300 "$GODOT" --headless --editor --quit --path "$REPO" >"$REIMPORT_LOG" 2>&1; then
    echo "[regression] reimport ok"
  else
    # Don't abort the whole run, but make it loud — a failed reimport means the
    # class cache may still be stale, which is exactly what causes silent
    # gray-screen phase failures downstream.
    echo "[regression] WARN: reimport FAILED (rc=$?) — class cache may be stale; see $REIMPORT_LOG" >&2
    grep -iE "error|script error|parse" "$REIMPORT_LOG" 2>/dev/null | tail -5 >&2 || true
  fi

  # === Phase 1: Boot ===
  if reached boot; then
    echo ""; echo "=== Phase 1: Boot ==="
    bash "$REPO/scripts/tools/autoplay/record_boot.sh"
  fi

  # === Phase 2: SR ===
  if reached sr; then
    echo ""; echo "=== Phase 2: SR (search_and_rescue) ==="
    REC_TIMEOUT=900 bash "$REPO/scripts/tools/autoplay/record_first_mission.sh"
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
    run_godot "pp_canon" "the_paru_pact" "$SCRATCH/pp-canon" 1100 &
    local_pid_pp1=$!
    sleep 2
    run_godot "pp_backtrack" "the_paru_pact_backtrack" "$SCRATCH/pp-backtrack" 1100 &
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
    run_godot "as_canon" "apothecary_supply" "$SCRATCH/as-canon" 1200 &
    local_pid_as1=$!
    sleep 2
    run_godot "as_moon" "apothecary_supply_moon_last" "$SCRATCH/as-moon" 1200 &
    local_pid_as2=$!
    sleep 2
    run_godot "as_sol" "apothecary_supply_sol_last" "$SCRATCH/as-sol" 1200 &
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
    run_godot "doe" "deep_ore_extraction" "$SCRATCH/doe" 1200
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
    run_godot "fo" "finding_ogi" "$SCRATCH/fo" 900
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
    run_godot "sis" "static_in_the_snow" "$SCRATCH/sis" 900
  fi

  # === Core story endgame spine (sequential; each from the prior post-save) ===
  # investigate_tower branches off finding_ogi (parent_quest=finding_ogi),
  # the same parent as static_in_the_snow — so it resumes from post-fo.
  if reached it; then
    run_chain_phase it      "investigate_tower" "post-fo"      "post-it"      "Phase 8: investigate_tower" 900
  fi
  if reached heretic; then
    run_chain_phase heretic "heretic"           "post-it"      "post-heretic" "Phase 9: heretic" 900
  fi
  if reached csy; then
    run_chain_phase csy     "control_system"    "post-heretic" "post-csy"     "Phase 10: control_system" 900
  fi
  if reached tbs; then
    run_chain_phase tbs     "the_broken_seal"   "post-csy"     "post-tbs"     "Phase 11: the_broken_seal" 900
  fi
  if reached dc; then
    run_chain_phase dc      "dark_castle"       "post-tbs"     "post-dc"      "Phase 12: dark_castle" 900
    # Post-build assertion for #344: clearing the story finale on Normal
    # must unlock Hard in the persisted save. The unit test pins the rule;
    # this proves the wiring fires in the running game (the #335 lesson).
    dc_save="$SCRATCH/post-dc/save_data.json"
    if [ -f "$dc_save" ]; then
      if jq -e '[.characters[]? | select(.!=null) | (.unlocked_difficulties // []) | any(. == "hard")] | any' "$dc_save" >/dev/null 2>&1; then
        echo "[regression] #344 OK — Hard unlocked in post-dc save"
      else
        echo "[regression] ::error:: #344 — post-dc save did NOT unlock Hard"
        MATRIX_FAIL=1
      fi
    fi
  fi

  # === Phase 13: Shops (city-economy smoke — issue #9) ===
  # The quest chain never opens a shop/storage screen — the surface that shipped
  # broken in #283/#245. This phase drives a fresh boot → principal debug-meseta
  # → item shop → DONE. Runs LAST and self-contained: it wipes the default save,
  # so it must not precede the save-chained quest phases.
  if reached shops; then
    echo ""; echo "=== Phase 13: Shops (shop/storage smoke) ==="
    bash "$REPO/scripts/tools/autoplay/record_shops.sh" || true
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
for tag in boot first_mission pp_canon pp_backtrack as_canon as_moon as_sol doe fo sis it heretic csy tbs dc shops; do
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

# Post-build state assertions (#344 etc.) are not phase sidecars — surface
# them in the exit code so a failed assertion is loud even when every phase
# passed its DONE-ok oracle.
if [ "$MATRIX_FAIL" -ne 0 ]; then
  echo "[regression] ::error:: post-build state assertion(s) FAILED — see #344 line above"
  exit 1
fi
