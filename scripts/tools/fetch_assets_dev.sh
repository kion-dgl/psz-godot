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
PARALLEL=16
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
    # PSZ weapons live in the sibling psz-sketch checkout; on CI and most
    # dev boxes the sibling isn't present, so skip silently via the
    # __SKIP__ sentinel (download_one returns 0, not a failure).
    assets/weapons/*)
      if [ -d "../psz-sketch/public/weapons" ]; then
        echo "../psz-sketch/public/weapons/${key#assets/weapons/}"
      else
        echo "__SKIP__"
      fi
      ;;
    assets/*) echo "assets/${key#assets/}" ;;
    *) echo "" ;;
  esac
}

export -f dest_for_key

download_one() {
  local line="$1"
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
  # Retry a couple times for flaky gateways.
  local attempts=0
  while ! curl -fsS -A "psz-godot-dev-fetch/1.0" -o "$dest" "$BASE/$key_enc"; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 3 ]]; then
      echo "  ! failed: $key" >&2
      return 1
    fi
    sleep 2
  done
}

export -f download_one
export BASE FORCE

echo "→ downloading (parallel=$PARALLEL, skipping matching md5s)..."
# Use xargs for parallel dispatch; `bash -c` wrapper so we can call the
# exported function.
FAIL_LOG=$(mktemp)
trap 'rm -f "$TREE_FILE" "$WORK" "$FAIL_LOG"' EXIT

< "$WORK" xargs -I {} -P "$PARALLEL" bash -c '
  line="{}"
  download_one "$line" || echo "$line" >> "'"$FAIL_LOG"'"
'

FAILS=$(wc -l < "$FAIL_LOG" | tr -d ' ')
if [[ "$FAILS" -ne 0 ]]; then
  echo "✗ $FAILS file(s) failed to download; re-run to retry" >&2
  exit 1
fi

echo "✓ local trees in sync ($FILE_COUNT files: /assets/ + web/public/assets/psobb_sfx/)"
