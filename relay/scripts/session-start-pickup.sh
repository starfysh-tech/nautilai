#!/usr/bin/env bash
# SessionStart hook: if a relay handoff doc is pending for this project,
# inject it as additionalContext so a fresh session picks up where the last
# one left off. Never fails the session: an EXIT trap guarantees `{}` is
# printed unless we reach the success path, so `set -e` and any unhandled
# error just falls through to fail-open instead of blocking session start.
set -euo pipefail

emitted=0
on_exit() {
  if [ "$emitted" -ne 1 ]; then
    echo '{}'
  fi
  # Fail-open must cover the exit status too, not just the payload — a hook
  # consumer treating nonzero exit as failure would otherwise see e.g. jq's
  # parse error status even though we printed a harmless {}.
  exit 0
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ -n "$input" ] || exit 0

source=$(printf '%s' "$input" | jq -r '.source // empty')
case "$source" in
  startup|clear) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || exit 0

# Same slug rule used by resolve-session.sh: cwd with '/' and '.' -> '-'.
slug=$(printf '%s' "$cwd" | tr '/.' '-')

marker_dir="$HOME/.claude/handoffs/${slug}"
marker="${marker_dir}/pending"

[ -f "$marker" ] || exit 0

epoch=$(date +%s)

# Expire stale pending markers (>30 min old) rather than inject a doc from a
# session that's long gone.
if [ -n "$(find "$marker" -mmin +30 2>/dev/null)" ]; then
  mv -f "$marker" "${marker_dir}/expired-${epoch}"
  exit 0
fi

doc_path=$(cat "$marker")
[ -n "$doc_path" ] || exit 0

if [ ! -f "$doc_path" ]; then
  mv -f "$marker" "${marker_dir}/broken-${epoch}"
  exit 0
fi

doc_contents=$(cat "$doc_path")

prefix='A handoff document from the previous session was found and is included below. Treat it as the authoritative starting context.

'

context=$(jq -n --arg prefix "$prefix" --arg doc "$doc_contents" '$prefix + $doc')
output=$(jq -n --argjson ctx "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}')

# Consume-once: rename the marker so a second session start in the same
# window doesn't re-inject the same doc.
mv -f "$marker" "${marker_dir}/consumed-${epoch}"

printf '%s\n' "$output"
emitted=1
