#!/usr/bin/env bash
# Self-check: verify relay's environmental assumptions (see ../SCHEMA.md)
# hold in THIS environment. Read-only, no model calls, bash 3.2 + jq only.
# Ask a bug reporter to run this first — its output is the fastest way to
# tell "relay is broken" from "this environment doesn't match what relay
# assumed."
set -uo pipefail

# One global trap, registered before any temp file exists (set -u safe via
# empty init), so an interrupt anywhere can't leak clean or the write probe.
clean=""
probe=""
trap 'rm -f "$clean" "$probe"' EXIT

any_fail=0
line() {
  status="$1"; shift
  printf '%-5s %s\n' "$status" "$*"
  [ "$status" = "FAIL" ] && any_fail=1
  return 0
}

# --- jq present -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  line ok "jq present ($(jq --version 2>/dev/null))"
else
  line FAIL "jq not found in PATH -- every relay script requires it"
fi

# --- claude CLI present (warn-only: narrative degrades gracefully without it)
if command -v claude >/dev/null 2>&1; then
  line ok "claude CLI present -- narrative pack (haiku-narrative.sh) can run"
else
  line warn "claude CLI not found -- narrative pack will degrade (exit 3); fact pack still works"
fi

# --- project slug / transcript directory ------------------------------------
slug=$(printf '%s' "$PWD" | tr '/.' '-')
project_dir="$HOME/.claude/projects/${slug}"
if [ -d "$project_dir" ]; then
  line ok "transcript directory exists: ${project_dir}"
else
  line FAIL "transcript directory not found: ${project_dir} -- slug rule may not match this cwd/platform (see SCHEMA.md)"
fi

# --- session env var ---------------------------------------------------------
session_id="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
if [ -n "$session_id" ]; then
  candidate="${project_dir}/${session_id}.jsonl"
  if [ -f "$candidate" ]; then
    line ok "session env var set and matches a transcript: ${session_id}"
  else
    line warn "session env var set (${session_id}) but no matching transcript file -- will fall back to mtime guess"
  fi
else
  line warn "no CLAUDE_CODE_SESSION_ID/CLAUDE_SESSION_ID set -- resolve-session.sh will guess the newest-mtime transcript"
fi

# --- newest transcript parses as JSONL with expected line shapes ------------
newest=""
if [ -d "$project_dir" ]; then
  newest_mtime=-1
  for f in "${project_dir}"/*.jsonl; do
    [ -e "$f" ] || continue
    # GNU first — see resolve-session.sh: GNU `stat -f` succeeds with fs info.
    mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo -1)
    case "$mtime" in ''|*[!0-9]*) mtime=-1 ;; esac
    if [ "$mtime" -gt "$newest_mtime" ]; then
      newest_mtime="$mtime"
      newest="$f"
    fi
  done
fi

if [ -z "$newest" ]; then
  line warn "no *.jsonl transcripts found in ${project_dir} -- nothing to extract from yet"
elif ! command -v jq >/dev/null 2>&1; then
  line warn "skipping transcript parse check -- jq unavailable"
else
  clean=$(mktemp)
  if jq -cR 'fromjson? | select(type=="object")' "$newest" > "$clean" 2>/dev/null; then
    line_count=$(wc -l < "$clean" | tr -d ' ')
    if [ "$line_count" -eq 0 ]; then
      line FAIL "newest transcript (${newest}) produced 0 valid JSON object lines"
    else
      has_type=$(jq -r 'select(.type != null) | .type' "$clean" | head -1)
      if [ -z "$has_type" ]; then
        line FAIL "newest transcript has no lines with a 'type' field"
      else
        line ok "newest transcript parses as JSONL (${line_count} lines, has 'type' field)"
      fi

      recognizable=$(jq -r '
        select(.type=="user" or .type=="assistant")
        | .message.content as $c
        | if ($c|type)=="string" then "text"
          elif ($c|type)=="object" and ($c.text != null) then "text"
          elif ($c|type)=="array" and (($c | map(select(.type=="text" or .type=="tool_use")) | length) > 0) then "text"
          else empty
          end
      ' "$clean" | head -1)
      if [ -n "$recognizable" ]; then
        line ok "found at least one user/assistant line with recognizable message.content"
      else
        line warn "no user/assistant line with recognizable message.content shape (string/object.text/array-of-blocks) -- extractors may see empty output"
      fi
    fi
  else
    line FAIL "newest transcript (${newest}) failed to parse as JSONL"
  fi
  rm -f "$clean"
fi

# --- handoffs dir writable ---------------------------------------------------
handoff_dir="$HOME/.claude/handoffs/${slug}"
mkdir -p "$handoff_dir" 2>/dev/null || true
probe="${handoff_dir}/.doctor-probe-$$"
if : > "$probe" 2>/dev/null; then
  rm -f "$probe"
  line ok "handoffs directory writable: ${handoff_dir}"
else
  line FAIL "handoffs directory not writable: ${handoff_dir} -- pickup/recovery markers can't be written"
fi

[ "$any_fail" -eq 0 ] && exit 0 || exit 1
