#!/usr/bin/env bash
# Print the absolute path of the current session's transcript JSONL to stdout.
#
# Resolution order:
#   1. $CLAUDE_CODE_SESSION_ID or $CLAUDE_SESSION_ID -> exact transcript file.
#   2. Fallback: newest-mtime *.jsonl in the project's transcript directory
#      (a guess — printed as a warning to stderr).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "resolve-session.sh: jq is required but was not found in PATH" >&2
  exit 1
fi

# Project slug: $PWD with every '/' and '.' replaced by '-'.
# (Mirrors how Claude Code derives ~/.claude/projects/<slug>/ from cwd.)
project_slug() {
  printf '%s' "$1" | tr '/.' '-'
}

slug=$(project_slug "$PWD")
project_dir="$HOME/.claude/projects/${slug}"

session_id="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"

if [ -n "$session_id" ]; then
  candidate="${project_dir}/${session_id}.jsonl"
  if [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
  echo "resolve-session.sh: session id set (${session_id}) but ${candidate} does not exist; falling back to mtime guess" >&2
fi

if [ ! -d "$project_dir" ]; then
  echo "resolve-session.sh: no transcript directory found at ${project_dir}" >&2
  exit 1
fi

newest=""
newest_mtime=-1
for f in "${project_dir}"/*.jsonl; do
  [ -e "$f" ] || continue
  # macOS/BSD stat and GNU stat use different flags; try both.
  mtime=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null || echo -1)
  if [ "$mtime" -gt "$newest_mtime" ]; then
    newest_mtime="$mtime"
    newest="$f"
  fi
done

if [ -z "$newest" ]; then
  echo "resolve-session.sh: no *.jsonl transcripts found in ${project_dir}" >&2
  exit 1
fi

echo "resolve-session.sh: no session id in env; guessing newest-mtime transcript: ${newest}" >&2
printf '%s\n' "$newest"
