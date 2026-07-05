#!/usr/bin/env bash
# Extract a markdown "fact pack" of ground-truth facts from a Claude Code
# session transcript JSONL file. Unlike the (possibly compacted) context
# window, the transcript retains every tool call, result, and user message
# for the session, so this is used to ground a handoff document in what
# actually happened rather than what the model remembers happening.
set -euo pipefail

EXTRACTOR_VERSION="relay-extract v1"

if ! command -v jq >/dev/null 2>&1; then
  echo "extract-transcript.sh: jq is required but was not found in PATH" >&2
  exit 1
fi

before_last_compact=0
if [ "${1:-}" = "--before-last-compact" ]; then
  before_last_compact=1
  shift
fi

if [ $# -lt 1 ]; then
  echo "usage: extract-transcript.sh [--before-last-compact] <transcript.jsonl>" >&2
  exit 1
fi

transcript="$1"
if [ ! -f "$transcript" ]; then
  echo "extract-transcript.sh: transcript not found: ${transcript}" >&2
  exit 1
fi

# Transcripts can contain interrupted/garbage lines; a raw parse error inside
# any downstream jq call would kill the whole run under set -e. Pre-filter to
# valid JSON objects once and extract from that.
clean=$(mktemp)
trap 'rm -f "$clean"' EXIT
jq -cR 'fromjson? | select(type=="object")' "$transcript" > "$clean"

# --before-last-compact restricts extraction to the transcript as it was
# before the most recent auto-compaction, so recovery pulls only the detail
# that compaction actually summarized away rather than re-deriving context
# the current session already has.
scope="full"
if [ "$before_last_compact" -eq 1 ]; then
  # grep exits 1 on no match; under pipefail that would kill the script via
  # set -e, so || true treats "no compaction line found" as a normal outcome.
  boundary_line=$(grep -n '"isCompactSummary":true' "$clean" | tail -n 1 | cut -d: -f1 || true)
  if [ -n "$boundary_line" ]; then
    trimmed=$(mktemp)
    # Cover $trimmed in the trap for the window before mv; BSD head rejects
    # -n 0, so a boundary on line 1 truncates directly instead.
    trap 'rm -f "$clean" "$trimmed"' EXIT
    if [ "$boundary_line" -eq 1 ]; then
      : > "$trimmed"
    else
      head -n "$((boundary_line - 1))" "$clean" > "$trimmed"
    fi
    mv "$trimmed" "$clean"
    trap 'rm -f "$clean"' EXIT
    scope="pre-compaction"
  else
    echo "extract-transcript.sh: no compaction boundary found; using full transcript" >&2
  fi
fi

# Redacts secrets that may have been echoed into tool output or pasted by the
# user (API keys, tokens, private key blocks) before anything reaches stdout.
# Intentionally independent of .gitleaks.toml: gitleaks scans committed
# content with rules compiled into its binary; this scrubs live transcript
# text with no runtime dependency.
scrub() {
  awk '
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/ { print "[REDACTED]"; inkey=1; next }
    inkey {
      if ($0 ~ /-----END [A-Z ]*PRIVATE KEY-----/) inkey=0
      next
    }
    {
      line = $0
      gsub(/AKIA[0-9A-Z]{16}/, "[REDACTED]", line)
      gsub(/gh[pousr]_[A-Za-z0-9]{20,}/, "[REDACTED]", line)
      gsub(/sk-[A-Za-z0-9_-]{20,}/, "[REDACTED]", line)
      gsub(/xox[a-z]-[A-Za-z0-9-]{10,}/, "[REDACTED]", line)
      gsub(/Bearer [^ \t"]+/, "Bearer [REDACTED]", line)
      print line
    }
  '
}

{
  echo "## Files touched"
  echo
  files_json=$(jq -s '
    [ .[] | select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use")
      | select(.name=="Edit" or .name=="Write" or .name=="Read" or .name=="NotebookEdit")
      | {path: (.input.file_path // .input.notebook_path // "unknown"), op: .name} ]
    | group_by(.path)
    | map({
        path: .[0].path,
        total: length,
        edits: (map(select(.op=="Edit" or .op=="NotebookEdit")) | length),
        reads: (map(select(.op=="Read")) | length),
        writes: (map(select(.op=="Write")) | length)
      })
    | sort_by(-.total)
  ' "$clean")
  file_count=$(printf '%s\n' "$files_json" | jq 'length')
  if [ "$file_count" -eq 0 ]; then
    echo "_none_"
  else
    printf '%s\n' "$files_json" | jq -r '.[] |
      "- " + .path + " (" +
      ([
        (if .edits > 0 then "edits: " + (.edits|tostring) else empty end),
        (if .reads > 0 then "reads: " + (.reads|tostring) else empty end),
        (if .writes > 0 then "writes: " + (.writes|tostring) else empty end)
      ] | join(", ")) + ")"
    '
  fi
  echo

  echo "## Commands run"
  echo
  # One pass builds the full list; the count and the last-50 display both
  # derive from it, so the selector can't drift between two copies.
  cmd_list=$(jq -r '
    select(.type=="assistant") | .message.content[]?
    | select(.type=="tool_use" and .name=="Bash")
    | (if (.input.description // "") != "" then .input.description + ": " else "" end)
      + ((.input.command // "") | split("\n")[0])
    | if length > 120 then .[0:120] else . end
    | "- " + .
  ' "$clean")
  if [ -z "$cmd_list" ]; then
    echo "_none_"
  else
    total_cmds=$(printf '%s\n' "$cmd_list" | wc -l | tr -d ' ')
    if [ "$total_cmds" -gt 50 ]; then
      echo "(showing last 50 of ${total_cmds})"
      echo
    fi
    printf '%s\n' "$cmd_list" | tail -n 50
  fi
  echo

  echo "## Failures"
  echo
  fail_json=$(jq -c '
    select(.type=="user") | .message.content[]?
    | select(.type=="tool_result" and .is_error==true)
    | (if (.content|type)=="string" then .content
       elif (.content|type)=="object" then .content.text // ""
       else (.content // [] | map(.text // "") | join("\n"))
       end)
  ' "$clean")
  if [ -z "$fail_json" ]; then
    echo "_none_"
  else
    # Truncate first, then flatten newlines so each failure stays one bullet.
    printf '%s\n' "$fail_json" | jq -r '. as $s | (($s[0:200]) + (if ($s|length) > 200 then "…" else "" end)) | gsub("\n"; " ")' | while IFS= read -r errline; do
      printf -- '- %s\n' "${errline}"
    done
  fi
  echo

  echo "## User messages (verbatim)"
  echo
  # Numbering and the 1500-char cap happen inside this single jq pass — a
  # per-message decode loop would spawn one jq process per message, which
  # dominated runtime on large transcripts. Slurp keeps multi-line messages
  # as one numbered entry with newlines preserved.
  msgs_out=$(jq -rs '
    [ .[] | select(.type=="user")
      # Structural exclusions: isMeta flags harness-injected content (skill
      # prompts etc.); isCompactSummary flags compaction continuations the
      # user never typed. The string prefixes below cover injections that
      # carry no structural marker in real transcripts.
      | select(.isMeta != true)
      | select(.isCompactSummary != true)
      | .message.content as $c
      | (
          if ($c|type)=="string" then $c
          elif ($c|type)=="object" then $c.text // null
          elif ($c|type)=="array" then
            ($c | map(select(.type=="text")) | .[0].text // null)
          else null
          end
        ) as $text
      | select($text != null)
      | select(
          ($text | startswith("<command-") | not)
          and ($text | startswith("<local-command") | not)
          and ($text | startswith("<system-reminder") | not)
          and ($text | startswith("Base directory for this skill") | not)
          and ($text | startswith("Another Claude session sent a message:") | not)
        )
      | $text ]
    | to_entries
    | map(((.key + 1)|tostring) + ". "
        + (if (.value|length) > 1500 then .value[0:1500] + "… [truncated]" else .value end))
    | join("\n\n")
  ' "$clean")
  if [ -z "$msgs_out" ]; then
    echo "_none_"
  else
    printf '%s\n' "$msgs_out"
  fi
  echo

  echo "## Provenance"
  echo
  size_bytes=$(wc -c < "$transcript" | tr -d ' ')
  line_count=$(wc -l < "$transcript" | tr -d ' ')
  echo "- transcript: ${transcript}"
  echo "- size: ${size_bytes} bytes"
  echo "- lines: ${line_count}"
  # Only surface scope when --before-last-compact was requested: the default
  # (no flag) provenance section must stay byte-identical to preserve the
  # existing test suite's exact-output assertions.
  if [ "$before_last_compact" -eq 1 ]; then
    echo "- scope: ${scope}"
  fi
  echo "- extractor: ${EXTRACTOR_VERSION}"
} | scrub
