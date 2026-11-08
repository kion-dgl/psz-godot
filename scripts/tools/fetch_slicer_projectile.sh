#!/bin/sh
# Fetch the alternate Ein Slicer mesh used by the isolated prototype.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
rel=assets/weapons/wslc01/wslc01/wslc01_3_o
mkdir -p "$root/$rel"
for ext in glb png; do
  curl -fSL "https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev/$rel/wslc01_3_o.$ext" -o "$root/$rel/wslc01_3_o.$ext"
done
printf '%s\n' 'Import the project with Godot before launching.'
