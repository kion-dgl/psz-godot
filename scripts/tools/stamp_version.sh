#!/usr/bin/env bash
#
# stamp_version.sh — compute the auto-incrementing build number and stamp it
# into the three version sources (VERSION, project.godot config/version,
# export_presets.cfg version/name + Android version/code).
#
# The committed values are the literal placeholder "dev" — no PR ever bumps
# them, so version merge conflicts are structurally impossible (the old
# per-PR semver bump made every pair of open PRs conflict). CI runs this
# right before every export:
#
#   build = OFFSET + first-parent commit count on HEAD
#
# First-parent counts one commit per merge to main, so the number advances
# +1 per landed PR — monotonic and unique. OFFSET=95 aligns the numbering
# with the retired semver line: main at v0.39.0 had fp-count 305 → build 400
# (0.40.0 "flattened", per the versioning decision of 2026-07-03).
#
# Android version/code gets the same integer, so every release's versionCode
# increases and APK upgrades always install over older builds.
#
# Usage: stamp_version.sh [suffix]
#   suffix — optional, appended to the display string only (never to
#            version/code), e.g. "-pr472.abc1234" for PR playtest builds.
# Prints the stamped version string on stdout.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OFFSET=95
COUNT=$(git -C "$REPO" rev-list --count --first-parent HEAD)
BUILD=$((OFFSET + COUNT))
V="${BUILD}${1:-}"

printf '%s' "$V" > "$REPO/VERSION"
sed -i "s|^config/version=.*|config/version=\"$V\"|" "$REPO/project.godot"
sed -i "s|^version/name=.*|version/name=\"$V\"|" "$REPO/export_presets.cfg"
sed -i "s|^version/code=.*|version/code=$BUILD|" "$REPO/export_presets.cfg"

echo "$V"
