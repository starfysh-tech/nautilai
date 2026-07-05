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

if [ $# -lt 1 ]; then
  echo "usage: extract-transcript.sh <transcript.jsonl>" >&2
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

# Redacts secrets that may have been echoed into tool output or pasted by the
# user (API keys, tokens, private key blocks) before anything reaches stdout.
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
  files_json=$(jq -c '
    select(.type=="assistant") | .message.content[]?
    | select(.type=="tool_use")
    | select(.name=="Edit" or .name=="Write" or .name=="Read" or .name=="NotebookEdit")
    | {path: (.input.file_path // .input.notebook_path // "unknown"), op: .name}
  ' "$clean" | jq -s '
    group_by(.path)
    | map({
        path: .[0].path,
        total: length,
        edits: (map(select(.op=="Edit" or .op=="NotebookEdit")) | length),
        reads: (map(select(.op=="Read")) | length),
        writes: (map(select(.op=="Write")) | length)
      })
    | sort_by(-.total)
  ')
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
  total_cmds=$(jq -s '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash")] | length' "$clean")
  if [ "$total_cmds" -eq 0 ]; then
    echo "_none_"
  else
    if [ "$total_cmds" -gt 50 ]; then
      echo "(showing last 50 of ${total_cmds})"
      echo
    fi
    jq -r '
      select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use" and .name=="Bash")
      | (if (.input.description // "") != "" then .input.description + ": " else "" end)
        + ((.input.command // "") | split("\n")[0])
      | if length > 120 then .[0:120] else . end
      | "- " + .
    ' "$clean" | tail -n 50
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
  msgs_json=$(jq -c '
    select(.type=="user")
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
    | $text
  ' "$clean")
  if [ -z "$msgs_json" ]; then
    echo "_none_"
  else
    # Iterate the JSON-encoded lines (one per message) and decode per message,
    # so a message containing newlines stays a single numbered entry and the
    # 1500-char cap applies to the whole message, not each line of it.
    n=0
    while IFS= read -r jmsg; do
      [ -n "$jmsg" ] || continue
      n=$((n + 1))
      msg=$(printf '%s' "$jmsg" | jq -r '.')
      if [ "${#msg}" -gt 1500 ]; then
        msg="${msg:0:1500}… [truncated]"
      fi
      printf '%s. %s\n\n' "$n" "$msg"
    done <<< "$msgs_json"
  fi
  echo

  echo "## Provenance"
  echo
  size_bytes=$(wc -c < "$transcript" | tr -d ' ')
  line_count=$(wc -l < "$transcript" | tr -d ' ')
  echo "- transcript: ${transcript}"
  echo "- size: ${size_bytes} bytes"
  echo "- lines: ${line_count}"
  echo "- extractor: ${EXTRACTOR_VERSION}"
} | scrub
