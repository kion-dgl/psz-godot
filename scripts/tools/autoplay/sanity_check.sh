#!/usr/bin/env bash
#
# sanity-check — drive the REAL game from a fresh first-run state and assert the
# boot → asset-mount → controller-config → title flow from the logs.
#
# Run:  npm run sanity-check     (or:  scripts/tools/autoplay/sanity_check.sh)
#
# DEV-BOX ONLY. Clobbers user:// player state on purpose (the dev box is a
# disposable test environment). It also temporarily repoints assets_manifest.json
# at the LOCAL dist/assets.pck (via bootstrap's file://LOCAL_DIST mirror) so the
# asset phase is offline + fast instead of waiting on Arweave, and restores the
# manifest on exit.
#
# The flow is driven by the Autopilot autoload (scripts/autoloads/autopilot.gd),
# activated via PSZ_AUTOPILOT=1, which injects synthetic input and prints
# `[sanity] …` checkpoints. We assert on those + bootstrap's `[bootstrap] …`
# lines. Extend by adding scenes to the autopilot and checks here.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/kion/.local/bin/godot)}"
USERDIR="$HOME/.local/share/godot/app_userdata/PSZ Godot"
MANIFEST="$REPO/assets_manifest.json"
PACK="$REPO/dist/assets.pck"
TIMEOUT="${SANITY_TIMEOUT:-600}"

MANIFEST_BAK="$(mktemp)"
LOG="$(mktemp)"
cleanup() {
	[ -f "$MANIFEST_BAK" ] && cp "$MANIFEST_BAK" "$MANIFEST" && rm -f "$MANIFEST_BAK"
	rm -f "$LOG"
}
trap cleanup EXIT

if [ ! -f "$PACK" ]; then
	echo "[sanity-check] ERROR: $PACK not found — build/publish a pack first." >&2
	exit 1
fi

# 1) Fresh player state. Keep packs/ so the local pack stays cached between runs
#    (first run copies it from dist — the "download" — later runs cache-hit).
echo "[sanity-check] resetting player state (input_config.json, save_data.json)…"
mkdir -p "$USERDIR"
rm -f "$USERDIR/input_config.json" "$USERDIR/save_data.json"

# 2) Repoint the manifest at the local pack so bootstrap copies from disk, not
#    Arweave. sha256/size are read from the actual file so it always verifies.
PACK_SHA="$(sha256sum "$PACK" | awk '{print $1}')"
PACK_SIZE="$(stat -c %s "$PACK" 2>/dev/null || stat -f %z "$PACK")"  # GNU / BSD(macOS)
cp "$MANIFEST" "$MANIFEST_BAK"
cat > "$MANIFEST" <<JSON
{
  "version": "sanity",
  "godot_version": "4.5",
  "pack": {
    "sha256": "$PACK_SHA",
    "size": $PACK_SIZE,
    "urls": ["file://LOCAL_DIST/assets.pck"]
  }
}
JSON

# 3) Drive the real game under autopilot, capture stdout+stderr.
# SANITY_MENU_CARRY=1 additionally runs the #426 carried-over-menu probe
# (Start Menu opened in the office, carried across the office→counter
# transition, interact at the guild NPC must be consumed by the menu).
MENU_CARRY="${SANITY_MENU_CARRY:-0}"
echo "[sanity-check] launching game under autopilot (timeout ${TIMEOUT}s, menu-carry=${MENU_CARRY})…"
PSZ_AUTOPILOT=1 PSZ_AUTOPILOT_MENU_CARRY="$MENU_CARRY" \
	timeout "$TIMEOUT" "$GODOT" --headless --path "$REPO" >"$LOG" 2>&1
RC=$?

echo "── game log (bootstrap / sanity) ──"
grep -E "^\[(bootstrap|sanity)\]" "$LOG" | sed 's/^/    /'
echo "───────────────────────────────────"

# 4) Assert the checkpoint sequence.
PASS=0
FAIL=0
check() {  # label needle
	if grep -qF -- "$2" "$LOG"; then
		echo "  PASS: $1"; PASS=$((PASS + 1))
	else
		echo "  FAIL: $1 (missing: '$2')"; FAIL=$((FAIL + 1))
	fi
}

check "splash / bootstrap started"           "[bootstrap] psz-godot"
check "assets mounted (download or cache)"    "[bootstrap] mounted"
check "first-run → controller-config screen"  "routing to input_select"
check "autopilot drove controller config"     "[sanity] input_select: injecting keyboard"
check "reached title"                          "[sanity] checkpoint: title"
check "reached character select"               "[sanity] checkpoint: character_select"
check "reached character create"               "[sanity] checkpoint: character_create"
check "entered character name"                 "[sanity] entering name:"
check "reached city_office"                    "[sanity] checkpoint: city_office"
check "reached city_counter"                   "[sanity] checkpoint: city_counter"
if [ "$MENU_CARRY" = "1" ]; then
	check "menu carried across transition (#426)"  "[sanity] menu-carry: Start Menu opened in office"
	check "carried menu blocked interact (#426)"   "[sanity] checkpoint: start-menu-carry-blocks-interact"
fi
check "guild_counter opened"                   "[sanity] checkpoint: guild_counter"
check "quest accepted"                         "[sanity] guild_counter: quest accepted"
# city_warp was retired by #449 (teleporter merged into the counter map) —
# the warp pad interaction below is the replacement checkpoint.
check "warp_teleporter opened"                 "[sanity] checkpoint: warp_teleporter"
check "valley_field entered"                   "[sanity] checkpoint: valley_field entered"
# Step progress is logged via the autopilot's cell-load plan lines
# ("[sanity] cell-load … plan label='<label>' do=[…] exit='…'"). We assert
# on the plan label, which carries the same cell/step identity the old
# "step N/24 (<label>)" lines did before that logging was refactored.
check "step (A 0,2 start)"                     "plan label='A 0,2 start'"
check "step (A 2,1 return, open gate)"         "plan label='A 2,1 (return, open gate)'"
check "step (A 2,2 switch)"                    "plan label='A 2,2 (switch)'"
check "step (A 2,4 end, warp east)"            "plan label='A 2,4 (end, warp east)'"
check "step (E 0,0 transition, warp north)"    "plan label='E 0,0 (transition, warp north)'"
check "step (B 0,2 start)"                     "plan label='B 0,2 start'"
check "step (B 1,2 return, open gate)"         "plan label='B 1,2 (return, open gate)'"
check "step (B 3,1 return, open gate)"         "plan label='B 3,1 (return, open gate)'"
check "step (B 3,0 final, quest complete)"     "plan label='B 3,0 (final, quest complete)'"
check "quest completed"                        "[sanity] checkpoint: quest_completed"
check "Principal did not complete quest (#354)" "[sanity] checkpoint: Principal did NOT complete the quest"
check "reported at guild counter (#354)"       "[sanity] checkpoint: quest reported at guild counter"
check "autopilot finished cleanly"             "[sanity] DONE ok"

echo
if [ "$FAIL" -eq 0 ] && [ "$RC" -eq 0 ]; then
	# Record the HEAD this passed for — the merge gate (scripts/tools/autoplay/
	# merge_gate.sh) reads .sanity-pass to decide whether a merge may proceed.
	git -C "$REPO" rev-parse HEAD > "$REPO/.sanity-pass" 2>/dev/null || true
	echo "══ SANITY CHECK PASSED ($PASS checks, godot rc=$RC) ══"
	exit 0
else
	echo "══ SANITY CHECK FAILED ($PASS passed, $FAIL failed, godot rc=$RC) ══"
	echo "   full log retained nowhere (temp); re-run with SANITY_TIMEOUT=300 if it timed out." >&2
	exit 1
fi
