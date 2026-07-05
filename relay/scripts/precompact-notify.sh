#!/usr/bin/env bash
# PreCompact hook: when auto-compaction is about to run, surface a warning
# and drop a marker so the user can later run '/handoff recover' to rebuild
# the pre-compaction detail from the transcript before it's summarized away.
# Only fires for trigger=="auto" — manual compaction was the user's own
# choice, so there's nothing lost that needs recovering.
set -euo pipefail

emitted=0
on_exit() {
  if [ "$emitted" -ne 1 ]; then
    echo '{}'
  fi
  # PreCompact can block compaction via exit 2 — this hook must never do
  # that, so fail-open forces exit 0 no matter what went wrong above.
  exit 0
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -n "$input" ] || exit 0

trigger=$(printf '%s' "$input" | jq -r '.trigger // empty')
[ "$trigger" = "auto" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || exit 0

transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$transcript_path" ] || exit 0

# Same slug rule used by session-start-pickup.sh: cwd with '/' and '.' -> '-'.
slug=$(printf '%s' "$cwd" | tr '/.' '-')

marker_dir="$HOME/.claude/handoffs/${slug}"
mkdir -p "$marker_dir"

epoch=$(date +%s)
printf '%s\n' "$transcript_path" > "${marker_dir}/compacted-${epoch}"

output=$(jq -n '{systemMessage: "Auto-compact ran — pre-compaction detail was summarized away. Run '\''/handoff recover'\'' to rebuild decisions, dead ends, and early constraints from the transcript."}')

printf '%s\n' "$output"
emitted=1
