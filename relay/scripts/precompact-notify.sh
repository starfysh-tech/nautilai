#!/usr/bin/env bash
# PreCompact hook: before auto-compaction, tell the summarizer to keep what
# compaction usually drops. PreCompact's systemMessage reaches the summary
# prompt; the recovery itself runs from SessionStart(source=compact), once
# compaction has actually happened.
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

printf '%s\n' '{"systemMessage": "When you write the summary, keep these verbatim in a section titled \"Preserved by relay\": every requirement or limit the user stated, with its exact numbers and names; each decision with the reason given for it; and each approach that was tried and abandoned, with why."}'
emitted=1
