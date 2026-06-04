#!/usr/bin/env bash
# Phase 2 validation: diff the solver's emitted steps[] against the steps
# the OLD autopilot (pre-refactor) actually produced at runtime.
#
# For each baseline quest:
#   1. Read its latest sanity log under spec/public/recordings/<tag>_*.sanity.log
#   2. Extract `[autopilot]   #N cell=...` lines as the OLD step sequence
#   3. Read data/quest_plans/<id>.json and pull out sections[].steps[] as
#      the NEW step sequence
#   4. Diff label + do[] + exit + target per step
#
# Differences in `portal_id` are noted but tolerated — the OLD autopilot
# couldn't resolve portal IDs (plans lacked cells[].portals); the NEW
# solver populates them, which is an upgrade. This script ignores
# portal_id differences.
#
# Exit code: 0 if all baseline quests match (modulo portal_id), 1 otherwise.

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO"

declare -A QUEST_TAG_MAP=(
  [the_paru_pact]=pp_canon
  [the_paru_pact_backtrack]=pp_backtrack
  [apothecary_supply]=as_canon
  [apothecary_supply_moon_last]=as_moon
  [apothecary_supply_sol_last]=as_sol
  [deep_ore_extraction]=doe
  [static_in_the_snow]=static_test
  [finding_ogi]=fogi
)

FAIL=0
for quest_id in "${!QUEST_TAG_MAP[@]}"; do
  tag="${QUEST_TAG_MAP[$quest_id]}"
  # Latest matching sanity log
  log=$(ls -t spec/public/recordings/${tag}_*.sanity.log 2>/dev/null | head -1)
  plan=data/quest_plans/${quest_id}.json

  if [ -z "$log" ]; then
    echo "[$quest_id] no sanity log found for tag=$tag — skipping"
    continue
  fi
  if [ ! -f "$plan" ]; then
    echo "[$quest_id] no plan file — skipping"
    continue
  fi

  # Extract OLD steps from sanity log:
  # format: [autopilot]   #N cell=... label='...' do=[...] exit='...' target='...'
  old_steps=$(grep -E '^\[autopilot\]   #' "$log" | sed -E "
    s/^\[autopilot\]   #[0-9]+ cell=[^ ]+ label='([^']*)' do=(\[[^]]*\]) exit='([^']*)' target='([^']*)' portal_id='[^']*'$/{\"label\":\"\1\",\"do\":\2,\"exit\":\"\3\",\"target\":\"\4\"}/
  " | jq -s '.')

  # Extract NEW steps from plan: flatten sections[].steps[]
  new_steps=$(jq '[.sections[].steps[] | {label, do, exit, target}]' "$plan" 2>/dev/null)

  if [ -z "$new_steps" ] || [ "$new_steps" = "null" ]; then
    echo "[$quest_id] plan has no steps[] — regenerate plan first"
    FAIL=1
    continue
  fi

  old_count=$(echo "$old_steps" | jq 'length')
  new_count=$(echo "$new_steps" | jq 'length')

  if [ "$old_count" != "$new_count" ]; then
    echo "[$quest_id] ✗ count mismatch: OLD=$old_count NEW=$new_count"
    FAIL=1
    continue
  fi

  # Per-step semantic diff
  diff_out=$(diff <(echo "$old_steps" | jq -S '.') <(echo "$new_steps" | jq -S '.') 2>/dev/null || true)
  if [ -z "$diff_out" ]; then
    echo "[$quest_id] ✓ pass ($new_count steps match)"
  else
    echo "[$quest_id] ✗ semantic diff:"
    echo "$diff_out" | head -20
    FAIL=1
  fi
done

if [ $FAIL -ne 0 ]; then
  echo ""
  echo "VERDICT: at least one quest's TS-emitted steps drift from old-autopilot runtime output"
  exit 1
fi
echo ""
echo "VERDICT: all checked quests match"
