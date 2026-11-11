#!/bin/zsh
set -e
cd "$(dirname "$0")/../.."
exec python3 scripts/tools/run_ranger_aim.py "$@"
