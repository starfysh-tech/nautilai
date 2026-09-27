#!/usr/bin/env bash
# SessionStart(source=compact) hook: after an AUTO compaction, re-inject the
# messages the user wrote before the boundary; the summary is the step that
# drops early requirements. Never touches `pending`, which belongs to the
# /clear handoff flow. Fails open: prints `{}` unless the injection is emitted.
set -euo pipefail

emitted=0
trap '[ "$emitted" -eq 1 ] || echo "{}"; exit 0' EXIT

[ -z "${RELAY_NESTED:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -f "$transcript" ] && [ -n "$cwd" ] || exit 0

trigger=$(grep '"compact_boundary"' "$transcript" | tail -n 1 \
  | jq -r '.compactMetadata.trigger // empty' 2>/dev/null || true)
[ "$trigger" = auto ] || exit 0

here=$(dirname "$0")
marker_dir=$(bash "$here/handoff-dir.sh" "$cwd")
mkdir -p "$marker_dir"
printf '%s\n' "$transcript" > "${marker_dir}/compacted-$(date +%s)"

msgs=$(bash "$here/extract-transcript.sh" --before-last-compact --user-messages "$transcript" 2>/dev/null)
[ -n "$(printf '%s' "$msgs" | tr -d '[:space:]')" ] || exit 0

# Auto-compaction fired because the context was full; a large injection
# would push it straight back toward the threshold.
cap=6000
if [ "${#msgs}" -gt "$cap" ]; then
  msgs="${msgs:0:$cap}
[… truncated — /handoff recover rebuilds the full pre-compaction record]"
fi

prefix="Auto-compaction just summarized this conversation. Below are the messages the user wrote before it, verbatim from the transcript. Treat the requirements in them as still in force unless a later message changed them. /handoff recover rebuilds decisions and dead ends from the same transcript.

"
jq -n --arg ctx "${prefix}${msgs}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
emitted=1
