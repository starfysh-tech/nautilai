#!/usr/bin/env bash
# Build the post-compaction narrative for compact-recover.sh, detached:
#   recovery-narrative.sh <segment.jsonl> <out-file>
# <segment.jsonl> is compact-recover.sh's copy of the just-compacted segment;
# this script deletes it. prompt-recovery.sh injects <out-file> at the
# session's next prompt.
set -uo pipefail
trap 'rm -f "$1"' EXIT

narrative=$(bash "$(dirname "$0")/haiku-narrative.sh" "$1" 2>/dev/null) || exit 0

# Constraints first, so the cap below cuts Dead ends before Constraints. Text
# outside the three headings goes last; with none of them, nothing moves.
narrative=$(printf '%s\n' "$narrative" | awk '
  { sub(/\r$/, "") }
  /^## / {
    if ($0 == "## Constraints") k = "c"
    else if ($0 == "## Decisions") k = "d"
    else if ($0 == "## Dead ends") k = "e"
    else k = "o"
  }
  k == "" { k = "o" }
  k != "o" && /^[[:space:]]*$/ { next }
  { buf[k] = buf[k] $0 "\n" }
  END {
    n = split("c d e o", order, " ")
    for (i = 1; i <= n; i++) if (buf[order[i]] != "") { printf "%s%s", sep, buf[order[i]]; sep = "\n" }
  }
')

# Same budget as the compact-recover.sh injection: the context was just full.
cap=6000
if [ "${#narrative}" -gt "$cap" ]; then
  narrative="${narrative:0:$cap}
[… truncated — /handoff recover rebuilds the full record]"
fi
printf '%s\n' "$narrative" > "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"
