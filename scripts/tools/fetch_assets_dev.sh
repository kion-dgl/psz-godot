#!/usr/bin/env bash
# Populate /assets/ from the R2 public CDN. No credentials required — reads
# the tree manifest published by scripts/publish/sync_tree.ts and downloads
# each file in parallel.
#
# Run from the repo root:
#   scripts/tools/fetch_assets_dev.sh
#
# Flags:
#   --base <url>      Override the public base URL (defaults to the one the
#                     publisher uploaded; override useful for custom domain).
#   --parallel <N>    Concurrent downloads (default 16).
#   --force           Re-download even if local md5 matches.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DEFAULT_BASE="https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev"
BASE="$DEFAULT_BASE"
PARALLEL=8
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

for bin in curl jq md5sum xargs; do
  command -v "$bin" >/dev/null 2>&1 || { echo "need $bin in PATH" >&2; exit 2; }
done

TREE_URL="$BASE/assets_tree.json"
TREE_FILE="$(mktemp)"
trap 'rm -f "$TREE_FILE"' EXIT

echo "→ fetching tree manifest from $TREE_URL"
curl -fsSL -A "psz-godot-dev-fetch/1.0" -o "$TREE_FILE" "$TREE_URL"
FILE_COUNT=$(jq '.files | length' "$TREE_FILE")
echo "  $FILE_COUNT files in manifest"

mkdir -p assets

# Emit "key<TAB>urlencoded_key<TAB>md5<TAB>size" for each entry so the
# worker can parse it. URL-encode each path segment (split on /) so names
# with spaces or "&" (e.g. "Keyboard & Mouse/Default/..." under
# kenney_input-prompts) resolve correctly against the R2 public URL.
WORK="$(mktemp)"
trap 'rm -f "$TREE_FILE" "$WORK"' EXIT
jq -r '.files[] | "\(.key)\t\(.key | split("/") | map(@uri) | join("/"))\t\(.md5)\t\(.size)"' "$TREE_FILE" > "$WORK"

# Map each R2 key prefix to the local directory it should be extracted into.
# Keep in sync with scripts/publish/sync_tree.ts SYNC_ROOTS and
# web/src/utils/assets.ts CDN_PREFIXES.
dest_for_key() {
  local key="$1"
  case "$key" in
    assets/psobb_sfx/*) echo "web/public/assets/psobb_sfx/${key#assets/psobb_sfx/}" ;;
    # PSZ weapons used to live in the sibling psz-sketch checkout. They're
    # now in-tree under assets/weapons/w*/, so they fall through the
    # generic assets/* mapping below — no sibling-clone special case.
    assets/*) echo "assets/${key#assets/}" ;;
    *) echo "" ;;
  esac
}

export -f dest_for_key

download_one() {
  local line="$1"
  [[ -z "$line" ]] && return 0
  local key key_enc md5 size
  IFS=$'\t' read -r key key_enc md5 size <<< "$line"
  local dest
  dest=$(dest_for_key "$key")
  if [[ "$dest" == "__SKIP__" ]]; then
    return 0
  fi
  if [[ -z "$dest" ]]; then
    echo "  ! unmapped prefix: $key" >&2
    return 1
  fi
  if [[ "$FORCE" -eq 0 && -f "$dest" ]]; then
    local got
    got=$(md5sum "$dest" | awk '{print $1}')
    if [[ "$got" == "$md5" ]]; then
      return 0
    fi
  fi
  mkdir -p "$(dirname "$dest")"
  # curl --retry-all-errors (7.71+) retries on any transient failure including
  # 429 rate-limits, with exponential backoff. Cloudflare R2 rate-limits
  # aggressive parallel fetches, so we need backoff here, not just an outer
  # attempt loop.
  local attempts=0
  while ! curl -fsS --retry 6 --retry-delay 2 --retry-all-errors \
       -A "psz-godot-dev-fetch/1.0" -o "$dest" "$BASE/$key_enc"; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 3 ]]; then
      echo "  ! failed: $key" >&2
      return 1
    fi
    sleep 5
  done
}

export -f download_one
export BASE FORCE

echo "→ downloading (parallel=$PARALLEL, skipping matching md5s)..."
# Use xargs for parallel dispatch; `bash -c` wrapper so we can call the
# exported function.
#
# NUL-delimited dispatch (`tr '\n' '\0' | xargs -0 -n 1`) instead of `-I {}`.
# BSD xargs (macOS) caps the per-invocation command size when substituting
# `-I {}`, and the long inline `bash -c` script plus a manifest line blew past
# it ("command line cannot be assembled, too long"), so almost nothing
# downloaded. `-0 -n 1` passes each line as a single argv entry (no template
# substitution, no per-line size limit) and is supported identically by both
# BSD and GNU xargs — no extra tooling required on macOS. The trailing `_`
# becomes $0 for the wrapper so the manifest line is $1.
FAIL_LOG=$(mktemp)
trap 'rm -f "$TREE_FILE" "$WORK" "$FAIL_LOG"' EXIT

< "$WORK" tr '\n' '\0' | xargs -0 -P "$PARALLEL" -n 1 bash -c '
  download_one "$1" || echo "$1" >> "'"$FAIL_LOG"'"
' _

FAILS=$(wc -l < "$FAIL_LOG" | tr -d ' ')
if [[ "$FAILS" -ne 0 ]]; then
  echo "✗ $FAILS file(s) failed to download; re-run to retry" >&2
  exit 1
fi

echo "✓ local trees in sync ($FILE_COUNT files: /assets/ + web/public/assets/psobb_sfx/)"
