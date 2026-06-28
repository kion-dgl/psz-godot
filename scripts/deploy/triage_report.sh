#!/usr/bin/env bash
# Triage a live bug report on the psz.onl droplet: set its status and/or link a
# GitHub issue, in place in /srv/reports/<id>/report.json. CLI-over-SSH by
# design — reports are world-READABLE (the public /reports list) but not
# world-writable, so there is no public mutation endpoint to abuse.
#
# The reports pages are SSR (prerender = false) and read REPORTS_DIR at request
# time, so an edit shows up immediately — no site redeploy needed.
#
# Usage:
#   scripts/deploy/triage_report.sh <id> [--status open|resolved|wontfix] [--issue <number>]
#
# Examples:
#   triage_report.sh 2026-06-28T02-01-06-528Z-6caf99ff --status resolved --issue 415
#   triage_report.sh 2026-06-28T01-57-04-369Z-42201fa9 --status wontfix  --issue 417
#   triage_report.sh 2026-06-28T01-58-18-903Z-608541e5 --issue 416         # link only, leave status
#
# Status meanings: open (default, absent) · resolved (fixed) · wontfix (closed
# as won't-do). The <id> is the report's directory name (the URL slug at
# /reports/<id>).
#
# Config (droplet defaults — same target/key as the pack + site deploy):
#   DO_PACK_SSH    = root@159.223.133.93
#   DO_REPORTS_DIR = /srv/reports
set -euo pipefail

SSH="${DO_PACK_SSH:-root@159.223.133.93}"
REPORTS_DIR="${DO_REPORTS_DIR:-/srv/reports}"

ID=""; STATUS=""; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) STATUS="${2:-}"; shift 2;;
    --issue)  ISSUE="${2:-}";  shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    -*) echo "unknown flag: $1" >&2; exit 2;;
    *)  ID="$1"; shift;;
  esac
done

[[ -n "$ID" ]] || { echo "usage: triage_report.sh <id> [--status open|resolved|wontfix] [--issue N]" >&2; exit 2; }
[[ -n "$STATUS" || -n "$ISSUE" ]] || { echo "nothing to do: pass --status and/or --issue" >&2; exit 2; }
# Validate inputs locally so we never ship junk into the JSON (and the values
# are safe to embed in the remote command — enum + digits only).
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad id (allowed: A-Za-z0-9._-): $ID" >&2; exit 2; }
if [[ -n "$STATUS" && ! "$STATUS" =~ ^(open|resolved|wontfix)$ ]]; then
  echo "--status must be one of: open resolved wontfix" >&2; exit 2
fi
if [[ -n "$ISSUE" && ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "--issue must be a number (the GitHub issue #)" >&2; exit 2
fi

echo "→ triaging $ID on $SSH:$REPORTS_DIR …"
# Merge keys into report.json on the droplet. python3 (present on the droplet)
# does an atomic read-modify-write; values arrive as env on the remote process.
ssh "$SSH" "REP_DIR='$REPORTS_DIR' REP_ID='$ID' REP_STATUS='$STATUS' REP_ISSUE='$ISSUE' python3 - " <<'PY'
import json, os, sys
from datetime import datetime, timezone

path = os.path.join(os.environ["REP_DIR"], os.environ["REP_ID"], "report.json")
if not os.path.isfile(path):
    sys.exit("no such report: " + path)

with open(path) as f:
    report = json.load(f)

status = os.environ.get("REP_STATUS") or ""
issue = os.environ.get("REP_ISSUE") or ""
if status:
    report["status"] = status
if issue:
    report["issue"] = int(issue)
report["triaged_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(report, f, indent=2)
os.replace(tmp, path)

print("✓ %s → status=%s issue=%s" % (
    os.environ["REP_ID"], report.get("status", "open"), report.get("issue", "—")))
PY
echo "✓ done — live at https://psz.onl/reports/$ID (no redeploy needed)"
