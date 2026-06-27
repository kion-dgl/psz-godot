#!/usr/bin/env bash
# Build the spec Astro app and deploy it to the psz.onl droplet — the public
# playtest site (landing + docs + /api/report). MANUAL deploy, no CD: run this
# after merging site changes, the same hands-on way packs ship (publish_do.ts).
#
# The Godot web build at /play deploys SEPARATELY via deploy_web_do.sh (it's a
# standalone /srv/play static mount), so a site deploy never reships the game.
#
# Config via env (droplet defaults):
#   DO_PACK_SSH  = root@159.223.133.93   (same target/key as the pack host)
#   DO_SITE_DIR  = /srv/site
#
# See auto-memory play-site-psz-onl for the full architecture.
set -euo pipefail

SSH="${DO_PACK_SSH:-root@159.223.133.93}"
SITE_DIR="${DO_SITE_DIR:-/srv/site}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT/spec"
echo "→ building spec…"
npm run build

echo "→ rsync dist → $SSH:$SITE_DIR (excluding client/game — game deploys separately)…"
rsync -az --delete --exclude='client/game/' dist/ "$SSH:$SITE_DIR/dist/"
rsync -az package.json package-lock.json "$SSH:$SITE_DIR/"

echo "→ npm ci --omit=dev on box + restart psz-site…"
ssh "$SSH" "cd '$SITE_DIR' && rm -rf node_modules && npm ci --omit=dev >/dev/null 2>&1 && systemctl restart psz-site && sleep 2 && systemctl is-active psz-site"

echo "✓ deployed → https://psz.onl"
