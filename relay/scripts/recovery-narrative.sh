#!/usr/bin/env bash
# Build the post-compaction narrative for compact-recover.sh, detached:
#   recovery-narrative.sh <transcript> <out-file>
# prompt-recovery.sh injects <out-file> at the session's next prompt.
set -uo pipefail

narrative=$(bash "$(dirname "$0")/haiku-narrative.sh" "$1" 2>/dev/null) || exit 0
# Same budget as the compact-recover.sh injection: the context was just full.
cap=6000
if [ "${#narrative}" -gt "$cap" ]; then
  narrative="${narrative:0:$cap}
[… truncated — /handoff recover rebuilds the full record]"
fi
printf '%s\n' "$narrative" > "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
