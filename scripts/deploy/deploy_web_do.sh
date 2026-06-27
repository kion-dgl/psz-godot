#!/usr/bin/env bash
# Build the Godot Web export and deploy it to psz.onl/play — a standalone static
# mount at /srv/play on the droplet, independent of the spec site deploy. Run
# this after a game change; the spec app never needs rebuilding for it.
#
# Builds in a throwaway git worktree of the CURRENT branch's committed HEAD, so
# the gitignored local asset set is NOT bundled — the artifact stays small (~93MB:
# wasm + game pck), and the 264MB asset pack is a runtime download from
# pck.psz.onl (whose Caddy block already sends Access-Control-Allow-Origin *).
# Commit game changes before running — uncommitted edits are not deployed.
#
# Config via env (droplet defaults):
#   DO_PACK_SSH  = root@159.223.133.93
#   DO_GAME_DIR  = /srv/game   (Caddy serves it at psz.onl/game; the /play page embeds it)
#
# See auto-memory play-site-psz-onl.
set -euo pipefail

SSH="${DO_PACK_SSH:-root@159.223.133.93}"
GAME_DIR="${DO_GAME_DIR:-/srv/game}"
PRESET="${WEB_PRESET:-Web}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
WT="$(mktemp -d)/psz-web"

echo "→ clean worktree build from '$BRANCH' (committed HEAD)…"
git -C "$ROOT" worktree add --detach "$WT" "$BRANCH"
trap 'git -C "$ROOT" worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$(dirname "$WT")"' EXIT

mkdir -p "$WT/build/web"
godot --headless --path "$WT" --import >/dev/null 2>&1 || true
godot --headless --path "$WT" --export-release "$PRESET" "$WT/build/web/index.html"

echo "→ rsync game build → $SSH:$GAME_DIR…"
rsync -az --delete "$WT/build/web/" "$SSH:$GAME_DIR/"

echo "✓ deployed → https://psz.onl/play"
