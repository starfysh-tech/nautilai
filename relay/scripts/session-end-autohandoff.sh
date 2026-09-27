#!/usr/bin/env bash
# SessionEnd hook: with RELAY_AUTO_HANDOFF=on, a /clear that was not preceded
# by /handoff still leaves a handoff for the next session. Claude Code kills a
# plugin's SessionEnd hook after about 1.5s, so this only records the
# builder's pid in a generating-<pid> marker and starts auto-handoff.sh in its
# own session (perl setsid: a plain `&` or nohup child dies with the hook).
set -euo pipefail
trap 'exit 0' EXIT

[ -z "${RELAY_NESTED:-}" ] || exit 0
[ "${RELAY_AUTO_HANDOFF:-}" = on ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.reason // empty')" = clear ] || exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -f "$transcript" ] && [ -n "$cwd" ] || exit 0

here=$(dirname "$0")
marker_dir=$(bash "$here/handoff-dir.sh" "$cwd")
# A pending marker here means the user ran /handoff before this /clear.
[ ! -e "${marker_dir}/pending" ] || exit 0

mkdir -p "$marker_dir"
generating="${marker_dir}/generating-$$"
: > "$generating"
perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' \
  bash "$here/auto-handoff.sh" "$transcript" "$marker_dir" "$generating" \
  </dev/null >"${marker_dir}/auto-handoff.log" 2>&1 &
# exec keeps the pid, so this is the builder's; pickup waits while it lives.
printf '%s\n' "$!" > "$generating"
