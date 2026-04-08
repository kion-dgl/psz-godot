#!/bin/bash
SRC_BASE="$HOME/Github/psz-asset-viewer"
DST_BASE="$HOME/Github/psz-godot/assets/enemies"

# entry: <enemy_name>:<main_model>:<extra_models>:<anim_prefix>
ENEMIES=(
  "swordman:b_062:b_062_sw:b062"
  "swordman_b:b_162:b_162_sw:b062"
  "swordman_rare:b_262:b_262_sw:b062"
  "swordman_rare_b:b_362:b_362_sw:b062"
  "boss_octopus:z_002:z_002_st z_002_tt:z_002"
  "boss_robot:z_003:z_003n z_003u:z003"
)

bake_one() {
  local name=$1 base=$2 extras=$3 anim_prefix=$4
  local temp="$SRC_BASE/temp/$name"
  cd "$temp" || return 1
  
  # Build base file list (model + sub models + texture)
  local base_files=("$base.nsbmd")
  for e in $extras; do
    [ -f "$e.nsbmd" ] && base_files+=("$e.nsbmd")
  done
  [ -f "$base.nsbtx" ] && base_files+=("$base.nsbtx")
  
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
    echo "  ✅ → $name.glb (${#good_anims[@]} anims)"
  else
    echo "  ❌ no $base.glb in $out"
  fi
}

for entry in "${ENEMIES[@]}"; do
  IFS=':' read -r name base extras anim_prefix <<< "$entry"
  bake_one "$name" "$base" "$extras" "$anim_prefix"
done
