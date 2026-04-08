#!/bin/bash
SRC_BASE="$HOME/Github/psz-asset-viewer"
DST_BASE="$HOME/Github/psz-godot/assets/enemies"

# entry: <enemy_name>:<main_model>:<extra_models>:<anim_prefix>:<texture_files>
# texture_files is a space-separated list of .nsbtx files (relative to temp/<name>/).
# Some bosses store textures in sub-model .nsbtx (e.g. boss_robot's z_003n.nsbtx),
# not the main model's name. If empty, falls back to <main_model>.nsbtx.
ENEMIES=(
  "swordman:b_062:b_062_sw:b062:b_062.nsbtx"
  "swordman_b:b_162:b_162_sw:b062:b_162.nsbtx"
  "swordman_rare:b_262:b_262_sw:b062:b_262.nsbtx"
  "swordman_rare_b:b_362:b_362_sw:b062:b_362.nsbtx"
  "boss_octopus:z_002:z_002_st z_002_tt:z_002:z_002.nsbtx"
  "boss_robot:z_003:z_003n z_003u:z003:z_003n.nsbtx"
  "boss_mother:z_004:z_004_kao_a z_004_kao_b:z_004:z_004.nsbtx"
)

bake_one() {
  local name=$1 base=$2 extras=$3 anim_prefix=$4 textures=$5
  local temp="$SRC_BASE/temp/$name"
  cd "$temp" || return 1

  # Build base file list (model + sub models + texture(s))
  local base_files=("$base.nsbmd")
  for e in $extras; do
    [ -f "$e.nsbmd" ] && base_files+=("$e.nsbmd")
  done
  for t in $textures; do
    [ -f "$t" ] && base_files+=("$t")
  done
  
  # Find candidate anim files (skip ef_/ff_ effects)
  local anim_files=()
  for f in ${anim_prefix}_*.nsbca; do
    [ -f "$f" ] || continue
    case "$f" in ef_*|ff_*) continue;; esac
    anim_files+=("$f")
  done
  
  # Test each anim individually, keep the ones that don't crash
  local good_anims=()
  for a in "${anim_files[@]}"; do
    rm -rf /tmp/_bake_test
    if apicula convert "${base_files[@]}" "$a" -o /tmp/_bake_test -f glb --overwrite --all-animations 2>&1 | grep -q "panicked"; then
      :
    else
      good_anims+=("$a")
    fi
  done
  
  echo "=== $name: ${#good_anims[@]}/${#anim_files[@]} anims usable ==="
  
  local out="/tmp/baked_$name"
  rm -rf "$out"
  apicula convert "${base_files[@]}" "${good_anims[@]}" -o "$out" -f glb --overwrite --all-animations 2>&1 | tail -2
  
  if [ -f "$out/$base.glb" ]; then
    cp "$out/$base.glb" "$DST_BASE/$name/$name.glb"
    # Copy any extracted PNG textures alongside the GLB
    for png in "$out"/*.png; do
      [ -f "$png" ] && cp "$png" "$DST_BASE/$name/"
    done
    echo "  ✅ → $name.glb (${#good_anims[@]} anims)"
  else
    echo "  ❌ no $base.glb in $out"
  fi
}

for entry in "${ENEMIES[@]}"; do
  IFS=':' read -r name base extras anim_prefix textures <<< "$entry"
  bake_one "$name" "$base" "$extras" "$anim_prefix" "$textures"
done
