#!/usr/bin/env bash
# Build a release-signed Android APK locally and stamp a monotonically-
# incrementing build number into BuildInfo so the title screen renders
# `0.27.5-local3`, `0.27.5-local4`, etc. Counter persists in
# `~/.psz-local-build-counter` so it survives across runs and across
# checkouts of the repo.
#
# Why a counter (rather than git SHA): the user wants to verify "did my
# latest APK actually install?" by comparing the on-screen number against
# what they just built. SHA doesn't change between builds with no source
# edits; the counter does, which is what makes the install-verify check
# work even when re-shipping the same code to debug a transport problem.
#
# Restores BuildInfo via `git checkout --` after export so `git status`
# stays clean — the bumped value never gets committed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

COUNTER_FILE="${PSZ_LOCAL_BUILD_COUNTER:-$HOME/.psz-local-build-counter}"
INFO_FILE="scripts/autoloads/build_info.gd"
KEYSTORE_BUNDLE="${PSZ_KEYSTORE_BUNDLE:-$HOME/psz-godot-keystore-bundle}"
APK_OUT="${1:-build/android/psz-godot-local.apk}"

# Bump counter
N=$(($(cat "$COUNTER_FILE" 2>/dev/null || echo 0) + 1))
echo "$N" > "$COUNTER_FILE"
echo "[local_build_apk] build counter → $N"

# Read the original value (works whether file is tracked or untracked,
# unlike `git checkout --`). Restore via sed on EXIT no matter how the
# export terminates so the working tree always returns to the source-
# of-truth value (0 if pristine, anything else if dev intentionally set it).
ORIG_VALUE=$(grep -oP '^const LOCAL_BUILD: int = \K\d+' "$INFO_FILE" || echo 0)
restore_info() {
	sed -i "s/^const LOCAL_BUILD: int = .*/const LOCAL_BUILD: int = $ORIG_VALUE/" "$INFO_FILE"
}
trap restore_info EXIT

# Stamp into BuildInfo
sed -i "s/^const LOCAL_BUILD: int = .*/const LOCAL_BUILD: int = $N/" "$INFO_FILE"

# Look up keystore passphrase
PASS=$(grep '^PASSPHRASE:' "$KEYSTORE_BUNDLE/BUNDLE_README.txt" | awk '{print $2}')
if [ -z "$PASS" ]; then
	echo "[local_build_apk] ERROR: couldn't read PASSPHRASE from $KEYSTORE_BUNDLE/BUNDLE_README.txt" >&2
	exit 1
fi

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE_BUNDLE/psz-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="psz-release"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PASS"

mkdir -p "$(dirname "$APK_OUT")"
godot --headless --path . --export-release "Android" "$APK_OUT"
echo "[local_build_apk] built $APK_OUT (build #$N)"
