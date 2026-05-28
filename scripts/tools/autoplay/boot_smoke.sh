#!/usr/bin/env bash
#
# Boot-flow smoke tests — drives the REAL bootstrap on a dev box and asserts
# the routing decision (first-time player → controller-config screen; returning
# player → straight to title).
#
# DEV-BOX ONLY. This clobbers user:// state (input_config.json) on purpose —
# the dev box is a disposable test environment. It also temporarily swaps the
# tracked assets_manifest.json for an empty one (so bootstrap dev-modes past the
# asset phase instead of waiting on Arweave) and restores it on exit.
#
# Run:  scripts/tools/autoplay/boot_smoke.sh
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
CFG="$USERDIR/input_config.json"
MANIFEST="$REPO/assets_manifest.json"
BOOT_TIMEOUT=15

PASS=0
FAIL=0
MANIFEST_BAK="$(mktemp)"

cleanup() {
	# Always restore the real manifest, even on failure/Ctrl-C.
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
}
trap cleanup EXIT

mkdir -p "$USERDIR"

# Swap in an empty manifest → bootstrap reads it as "no pack" → dev-mode →
# reaches _goto_title in ~1.2s with no download. Restored by cleanup().
cp "$MANIFEST" "$MANIFEST_BAK"
echo '{}' > "$MANIFEST"

run_boot() {
	# Runs the project's main scene (bootstrap.tscn) headless; kill after the
	# routing decision has printed (bootstrap keeps the title scene running).
	timeout "$BOOT_TIMEOUT" "$GODOT" --headless --path "$REPO" 2>&1
}

assert_contains() {   # haystack needle label
	if grep -qF -- "$2" <<<"$1"; then
		echo "  PASS: $3"; PASS=$((PASS + 1))
	else
		echo "  FAIL: $3 (missing: '$2')"; FAIL=$((FAIL + 1))
	fi
}

assert_absent() {     # haystack needle label
	if grep -qF -- "$2" <<<"$1"; then
		echo "  FAIL: $3 (unexpected: '$2')"; FAIL=$((FAIL + 1))
	else
		echo "  PASS: $3"; PASS=$((PASS + 1))
	fi
}

echo "══ Boot-flow smoke tests ══"
echo "  godot:    $GODOT"
echo "  userdir:  $USERDIR"
echo

echo "── First-time player: no input_config.json ──"
rm -f "$CFG"
OUT="$(run_boot)"
grep -E "^\[bootstrap\]" <<<"$OUT" | sed 's/^/    /'
assert_contains "$OUT" "routing to input_select" "first run → controller-config screen appears"
assert_absent  "$OUT" "routing to title"          "first run → does NOT skip to title"
echo

echo "── Returning player: input_config.json present ──"
cat > "$CFG" <<'JSON'
{"device":"keyboard","controller_type":"xbox","face_mapping":{"south":0,"east":1,"west":2,"north":3},"accept_position":"south","cancel_position":"east","scheme":"keyboard"}
JSON
OUT="$(run_boot)"
grep -E "^\[bootstrap\]" <<<"$OUT" | sed 's/^/    /'
assert_contains "$OUT" "routing to title"          "returning → straight to title"
assert_absent  "$OUT" "routing to input_select"    "returning → no controller-config screen"
echo

echo "══ RESULTS: $PASS passed, $FAIL failed ══"
[ "$FAIL" -eq 0 ]
