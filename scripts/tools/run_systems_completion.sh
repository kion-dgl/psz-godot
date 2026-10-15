#!/usr/bin/env bash
# Isolated live route + separate-process persistence. Reject script errors even
# when an interrupted GDScript coroutine prints a later successful checkpoint.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe_dir="${PSZ_COMPLETION_OUTPUT:-$(mktemp -d /tmp/psz-completion.XXXXXX)}"
mkdir -p "$probe_dir"
export XDG_DATA_HOME="$probe_dir/userdata"
export PSZ_PROBE_PACK="${PSZ_PROBE_PACK:-$repo_dir/dist/assets.pck}"
for phase in route restart; do
  export PSZ_COMPLETION_RESTART=0
  if [ "$phase" = restart ]; then export PSZ_COMPLETION_RESTART=1; fi
  timeout 240 godot --headless --path "$repo_dir" res://scripts/tools/systems_completion_probe.tscn > "$probe_dir/$phase.log" 2>&1
  if rg -n 'SCRIPT ERROR|\[systems\] FAIL|Warning treated as error' "$probe_dir/$phase.log"; then exit 1; fi
  if [ "$phase" = route ]; then
    rg -q '\[systems\] DONE ok' "$probe_dir/$phase.log"
  else
    rg -q 'PASS: upgrades and consumed doll persist across process restart' "$probe_dir/$phase.log"
  fi
  rg '\[systems\] (PASS|DONE)' "$probe_dir/$phase.log"
done
printf 'Evidence: %s\n' "$probe_dir"
