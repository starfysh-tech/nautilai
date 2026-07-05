#!/usr/bin/env bash
# SessionStart hook: if a relay handoff doc is pending for this project,
# inject it as additionalContext so a fresh session picks up where the last
# one left off. Never fails the session: an EXIT trap guarantees `{}` is
# printed unless we reach the success path, so `set -e` and any unhandled
# error just falls through to fail-open instead of blocking session start.
set -euo pipefail

emitted=0
marker_dir=""

# Retention sweep: deletes consumed/expired/broken/recovered/claimed/compacted
# markers and timestamped *.md docs older than RELAY_RETENTION_DAYS (default
# 14; 0 disables the sweep entirely). Runs from the EXIT trap, i.e. strictly
# after the injection payload (if any) has already been printed above — it
# can never delay or affect the pickup outcome, only tidy up afterward. Every
# failure mode (bad env value, unwritable dir, no dir at all) falls open by
# returning 0 rather than touching output or exit status. `pending` is never
# a match for either glob set, so it's structurally untouched regardless of
# age. -maxdepth 1 + -mtime +N are POSIX-portable across BSD and GNU find, so
# no dual-syntax branch is needed here (unlike the stat call above).
sweep_retention() {
  dir="$1"
  [ -n "$dir" ] && [ -d "$dir" ] || return 0

  days="${RELAY_RETENTION_DAYS:-14}"
  case "$days" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$days" -gt 0 ] || return 0

  find "$dir" -maxdepth 1 -type f \( \
    -name 'consumed-*' -o -name 'expired-*' -o -name 'broken-*' \
    -o -name 'recovered-*' -o -name 'claimed-*' -o -name 'compacted-*' \
  \) -mtime "+${days}" -exec rm -f {} + 2>/dev/null

  find "$dir" -maxdepth 1 -type f -name '*.md' -mtime "+${days}" \
    -exec rm -f {} + 2>/dev/null

  return 0
}

on_exit() {
  ( sweep_retention "$marker_dir" ) 2>/dev/null || true
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

# Atomically claim the marker before reading it: mv is atomic, so of two
# concurrent session starts only one wins the rename and injects — the loser
# exits quietly instead of double-injecting the same doc.
claimed="${marker_dir}/claimed-${epoch}-$$"
mv "$marker" "$claimed" 2>/dev/null || exit 0

# Expire stale markers (>30 min old) rather than inject a doc from a session
# that's long gone. GNU first: on Linux `stat -f` is FILESYSTEM stat and
# SUCCEEDS with a mount point (not an error), which silently poisons the
# fallback chain — whereas BSD `stat -c` errors cleanly into the fallback.
# Numeric guard so a wrong-but-successful stat can never reach the arithmetic.
mtime=$(stat -c '%Y' "$claimed" 2>/dev/null || stat -f '%m' "$claimed" 2>/dev/null || echo 0)
case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
if [ "$mtime" -gt 0 ] && [ $((epoch - mtime)) -gt 1800 ]; then
  # touch: mv preserves the stale mtime, and the retention sweep counts from
  # mtime — without a reset, an already-old marker's audit record would be
  # swept in the same pass that created it.
  mv -f "$claimed" "${marker_dir}/expired-${epoch}"
  touch "${marker_dir}/expired-${epoch}" 2>/dev/null || true
  exit 0
fi

doc_path=$(cat "$claimed")
if [ -z "$doc_path" ] || [ ! -f "$doc_path" ]; then
  mv -f "$claimed" "${marker_dir}/broken-${epoch}"
  touch "${marker_dir}/broken-${epoch}" 2>/dev/null || true
  exit 0
fi

doc_contents=$(cat "$doc_path")

prefix='A handoff document from the previous session was found and is included below. Treat it as the authoritative starting context.

'

context=$(jq -n --arg prefix "$prefix" --arg doc "$doc_contents" '$prefix + $doc')
output=$(jq -n --argjson ctx "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}')

# Consume-once: the claimed marker becomes consumed only after the payload
# is built, so a failure above leaves a claimed-* file as the audit trail.
mv -f "$claimed" "${marker_dir}/consumed-${epoch}"
touch "${marker_dir}/consumed-${epoch}" 2>/dev/null || true

printf '%s\n' "$output"
emitted=1
