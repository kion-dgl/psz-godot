#!/usr/bin/env bash
#
# shop_smoke — drive the shop/storage screens under autopilot and assert they
# open + behave. Complements sanity_check.sh (which drives the quest flow but
# never touches a shop). Catches flow/load regressions in the city economy
# screens — the surface that shipped broken in #283 (ShopBase) and #284.
#
# Run:  npm run shop-smoke   (or:  scripts/tools/autoplay/shop_smoke.sh)
#
# DEV-BOX ONLY. Clobbers user:// player state and temporarily repoints
# assets_manifest.json at the local dist/assets.pck (restored on exit).
#
# Activated by PSZ_AUTOPILOT_SHOPS=1: after the office intro the autopilot
# detours through the principal (debug meseta) and the shop/storage screens
# instead of accepting a quest. See scripts/autoloads/autopilot.gd + issue #9.
#
# NOTE: this runs the game headless from source (editor context), so it catches
# screen-load / flow regressions — NOT the Android-export-specific resolution
# bug from #283 (that needs an exported-build smoke; see #284).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
TIMEOUT="${SHOP_SMOKE_TIMEOUT:-300}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() { [ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"; rm -f "$LOG"; }
trap cleanup EXIT

if [ ! -f "$PACK" ]; then
	echo "[shop-smoke] ERROR: $PACK not found — build/publish a pack first." >&2
	exit 1
fi

echo "[shop-smoke] resetting player state…"
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"

PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK")"
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{ "version": "shop-smoke", "godot_version": "4.5", "pack": { "sha256": "$PACK_SHA", "size": $PACK_SIZE, "urls": ["file://$PACK"] } }
JSON

echo "[shop-smoke] launching game under autopilot (PSZ_AUTOPILOT_SHOPS=1, timeout ${TIMEOUT}s)…"
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_SHOPS=1 timeout "$TIMEOUT" "$GODOT" --headless --path "$REPO" >"$LOG" 2>&1
RC=$?

echo "── game log (bootstrap / sanity) ──"
grep -E "^\[(bootstrap|sanity)\]" "$LOG" | sed 's/^/    /'
echo "───────────────────────────────────"

PASS=0
FAIL=0
check() {  # label needle
	if grep -qF -- "$2" "$LOG"; then echo "  PASS: $1"; PASS=$((PASS + 1))
	else echo "  FAIL: $1 (missing: '$2')"; FAIL=$((FAIL + 1)); fi
}

check "reached city_office"               "[sanity] checkpoint: city_office"
check "entered shop-smoke detour"         "[sanity] office intro complete → shop/storage smoke"
check "principal debug meseta granted"    "[sanity] checkpoint: principal debug meseta granted"
check "item shop opened"                  "[sanity] checkpoint: item_shop opened"
check "item shop purchase registered"     "[sanity] checkpoint: item_shop bought"
check "weapon shop opened"                "[sanity] checkpoint: weapon_shop opened"
check "equipment screen opened"           "[sanity] checkpoint: equipment opened"
check "equipment equipped a weapon"       "[sanity] checkpoint: equipment equipped weapon"
check "frame: all same-stat copies listed" "[sanity] checkpoint: frame-dup all 3 copies listed as equippable"
check "frame: non-first instance equips"  "[sanity] checkpoint: frame-dup equipped non-first instance"
check "frame: suffixed gives full stats"  "[sanity] checkpoint: frame-dup suffixed frame full stats"
check "frame change clears all units"     "[sanity] checkpoint: frame-change cleared all units"
check "storage screen opened"             "[sanity] checkpoint: storage opened"
check "storage deposited meseta"          "[sanity] checkpoint: storage deposited meseta"
check "storage deposited an item"         "[sanity] checkpoint: storage deposited item"
check "storage withdrew the item"         "[sanity] checkpoint: storage withdrew item"
check "storage withdrew meseta"           "[sanity] checkpoint: storage withdrew meseta"
check "storage round-trip complete"       "[sanity] checkpoint: storage round-trip"
check "start menu opened (in city)"       "[sanity] checkpoint: start_menu opened"
check "start menu closed"                 "[sanity] checkpoint: start_menu closed"
check "autopilot finished cleanly"        "[sanity] DONE ok"

# Any explicit [sanity] FAIL line is a hard failure.
if grep -qF "[sanity] FAIL" "$LOG"; then
	echo "  FAIL: autopilot emitted a [sanity] FAIL line"; FAIL=$((FAIL + 1))
	grep -F "[sanity] FAIL" "$LOG" | sed 's/^/      /'
fi

echo "══ SHOP SMOKE: $PASS passed, $FAIL failed (godot rc=$RC) ══"
[ "$FAIL" -eq 0 ] || exit 1
