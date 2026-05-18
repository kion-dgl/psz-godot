#!/usr/bin/env bash
# Probe asset paths added/modified in this PR against the R2 public URL.
# Catches the "added a new asset, forgot to run sync-tree" case — the same
# class of bug verify-assets catches for the Arweave .pck.
#
# Usage (CI):
#   BASE_SHA=$(git merge-base origin/main HEAD) HEAD_SHA=HEAD \
#     scripts/tools/check_r2_mirror.sh
#
# Environment:
#   R2_BASE     Public R2 URL (default = the same one CI's `web` job uses)
#   BASE_SHA    Diff base (default origin/main)
#   HEAD_SHA    Diff head (default HEAD)
#   PARALLEL    Concurrent probes (default 8)
#
# Exit codes:
#   0 — all probed paths return 200, OR no asset paths changed in diff
#   1 — at least one probed path 404s (sync-tree not run)
#   2 — bad invocation / unexpected environment

set -euo pipefail

R2_BASE="${R2_BASE:-https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev}"
BASE_SHA="${BASE_SHA:-origin/main}"
HEAD_SHA="${HEAD_SHA:-HEAD}"
PARALLEL="${PARALLEL:-8}"

for bin in git curl jq xargs; do
  command -v "$bin" >/dev/null 2>&1 || { echo "need $bin in PATH" >&2; exit 2; }
done

# Subtrees that don't go to R2 — keep in sync with scripts/publish/sync_tree.ts
# (VENDORED_SKIPS + RESTRICTED_REL_PREFIXES) and scripts/tools/fetch_assets_dev.sh.
EXCLUDE_RE='^(assets/(kenney_input-prompts|kenney_nature-pack|npcs/cowgirl)/)|\.(import|uid)$'

# Build the list of paths added or modified in the PR diff. Two trees go to R2:
#   assets/*                        → key = assets/...
#   web/public/assets/psobb_sfx/*   → key = assets/psobb_sfx/...
# (The weapons/ tree lives in psz-sketch, not this repo, so no entries here.)
mapfile -t raw < <(
  git diff --name-only --diff-filter=AM "$BASE_SHA" "$HEAD_SHA" \
    -- 'assets/*' 'web/public/assets/psobb_sfx/*' 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" \
    || true
)

# Rewrite each diff path into its R2 key. assets/* stays as-is; the psobb_sfx
# subtree is rooted under assets/psobb_sfx/ on R2.
paths=()
for p in "${raw[@]}"; do
  if [[ "$p" == web/public/assets/psobb_sfx/* ]]; then
    paths+=("assets/psobb_sfx/${p#web/public/assets/psobb_sfx/}")
  else
    paths+=("$p")
  fi
done

if [ "${#paths[@]}" -eq 0 ]; then
  echo "→ no asset paths added/modified between $BASE_SHA and $HEAD_SHA — nothing to probe"
  exit 0
fi

echo "→ probing ${#paths[@]} asset path(s) against $R2_BASE..."

FAILURES=$(mktemp)
trap 'rm -f "$FAILURES"' EXIT

probe() {
  local path="$1"
  # URL-encode each segment to match sync_tree.ts upload key behavior.
  local enc
  enc=$(jq -rn --arg s "$path" '$s | split("/") | map(@uri) | join("/")')
  # Don't use curl -f: it makes 4xx print to stderr AND short-circuits the
  # -w status code we want to capture. We classify the code ourselves.
  local code
  code=$(curl -sSI --max-time 10 --retry 2 --retry-delay 2 \
              -o /dev/null -w "%{http_code}" \
              "$R2_BASE/$enc" 2>/dev/null || echo "000")
  if [ "$code" != "200" ]; then
    echo "$code $path" >> "$FAILURES"
  fi
}
export -f probe
export R2_BASE FAILURES

printf '%s\n' "${paths[@]}" | xargs -I {} -P "$PARALLEL" bash -c 'probe "$@"' _ {}

if [ -s "$FAILURES" ]; then
  echo
  echo "✗ The following paths are referenced in this PR but missing from R2:"
  sort -u "$FAILURES" | sed 's/^/   /'
  echo
  echo "Fix: from a checkout with R2 creds in .env, run"
  echo "   cd scripts/publish && npm run sync-tree"
  echo "Don't commit anything — sync-tree uploads to R2 directly."
  echo "CI will re-probe on the next push."
  exit 1
fi

echo "✓ all probed paths resolve on R2"
