#!/usr/bin/env bash
# PreCompact hook: record where compaction cuts the transcript, and before
# auto-compaction tell the summarizer to keep what compaction usually drops.
# PreCompact's systemMessage reaches the summary prompt; the recovery itself
# runs from SessionStart(source=compact), which reads the cut written here
# because the new compact_boundary line is not yet in the transcript then.
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
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

# Written for every trigger: a PreCompact(auto) that no compaction follows
# must be overwritten by the next PreCompact, or a later manual compaction
# would recover against the stale auto cut.
if [ -n "$session_id" ] && [ -f "$transcript" ]; then
  recovery_dir="$HOME/.claude/handoffs/.recovery"
  cut_tmp="$recovery_dir/${session_id}.cut.tmp.$$"
  {
    lines=$(wc -l < "$transcript" | tr -d ' ') \
      && mkdir -p "$recovery_dir" \
      && printf '%s %s\n' "${trigger:-none}" "$lines" > "$cut_tmp" \
      && mv -f "$cut_tmp" "$recovery_dir/${session_id}.cut"
  } 2>/dev/null || rm -f "$cut_tmp"
fi

[ "$trigger" = "auto" ] || exit 0

printf '%s\n' '{"systemMessage": "When you write the summary, keep these verbatim in a section titled \"Preserved by relay\": every requirement or limit the user stated, with its exact numbers and names; each decision with the reason given for it; and each approach that was tried and abandoned, with why."}'
emitted=1
