#!/usr/bin/env bash
#
# PreToolUse(Bash) gate — wired up in .claude/settings.json.
#
# Blocks `git merge` / `gh pr merge` UNLESS `npm run sanity-check` has passed
# for the current HEAD. sanity_check.sh writes .sanity-pass (containing the HEAD
# sha) on success; this gate allows the merge only when that marker matches the
# current HEAD. Any other Bash command passes straight through.
#
# Reads the hook payload (JSON) on stdin. Exit 0 = allow, exit 2 = block (the
# message on stderr is shown back to Claude).
#
set -uo pipefail

cmd="$(cat | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

# Match a real merge INVOCATION only: `git merge` / `gh pr merge` at the start
# of the command or right after a separator (; && || |), followed by a space or
# end-of-string. This avoids tripping on the pattern when it appears as data —
# inside quotes, echo strings, comments, `git merge-base`, `git log --grep`, etc.
if ! printf '%s\n' "$cmd" | grep -Eq '(^|[;&|])[[:space:]]*(git[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+merge)([[:space:]]|$)'; then
	exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"

if [ -f "$root/.sanity-pass" ] && [ "$(cat "$root/.sanity-pass" 2>/dev/null)" = "$head" ]; then
	exit 0
fi

{
	echo "MERGE BLOCKED — run \`npm run sanity-check\` and confirm it passes before merging."
	echo "No green sanity-check is recorded for the current HEAD ($head)."
	echo "sanity_check.sh writes .sanity-pass on success; once it's green for this HEAD the merge is allowed."
} >&2
exit 2
