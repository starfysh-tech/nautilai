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
    # Connection-string creds keep their scheme (so the fact "there was a
    # postgres URL here" survives) but redact the user:pass@ segment. gsub()
    # has no capture-group backreferences in POSIX/BSD awk, so this walks
    # matches with match()/RSTART/RLENGTH and rebuilds the line by hand
    # instead of relying on a gawk-only 4-arg gsub.
    function redact_conn(line,    matched, colonpos, scheme) {
      while (match(line, /(postgres|postgresql|mysql|mongodb|redis|amqp|https|http):\/\/[^:@\/ ]+:[^@\/ ]+@/)) {
        matched = substr(line, RSTART, RLENGTH)
        colonpos = index(matched, "://")
        scheme = substr(matched, 1, colonpos - 1)
        line = substr(line, 1, RSTART - 1) scheme "://[REDACTED]@" substr(line, RSTART + RLENGTH)
      }
      return line
    }
    # .env-style KEY=value lines where the key name looks secret-ish
    # (case-insensitive secret/token/passwd/password/api_key, matched with
    # per-letter bracket classes since BSD awk has no IGNORECASE) and the
    # value is at least 8 chars. Rebuilds by consuming the matched span off
    # the front of "line" each iteration (rather than rescanning the whole
    # line from the start) because the redacted key name still contains the
    # trigger keyword — rescanning from position 1 would match the
    # just-redacted "KEY=[REDACTED]" again forever.
    function redact_envsecret(line,    re, result, matched, eqpos, name) {
      re = "[A-Za-z0-9_]*([Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Aa][Pp][Ii]_?[Kk][Ee][Yy])[A-Za-z0-9_]*=[^ \t]{8,}"
      result = ""
      while (match(line, re)) {
        matched = substr(line, RSTART, RLENGTH)
        eqpos = index(matched, "=")
        name = substr(matched, 1, eqpos)
        result = result substr(line, 1, RSTART - 1) name "[REDACTED]"
        line = substr(line, RSTART + RLENGTH)
      }
      return result line
    }
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
      gsub(/AIza[0-9A-Za-z_-]{35}/, "[REDACTED]", line)
      gsub(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}/, "[REDACTED]", line)
      gsub(/hooks\.slack\.com\/services\/[A-Za-z0-9\/]+/, "hooks.slack.com/services/[REDACTED]", line)
      gsub(/Bearer [^ \t"]+/, "Bearer [REDACTED]", line)
      gsub(/Authorization: Basic [A-Za-z0-9+\/=]+/, "Authorization: Basic [REDACTED]", line)
      # GCP service-account "private_key" JSON fields keep their newlines
      # JSON-escaped (literal backslash-n, not real newlines) when the whole
      # credentials blob is pasted as one line of chat text — the BEGIN/END
      # state machine above only fires across real newline-delimited awk
      # records, so this is a separate single-line gsub for the \n-escaped
      # form. "\\n" in this ERE matches the two literal characters backslash
      # and n, not a newline.
      gsub(/-----BEGIN [A-Z ]*PRIVATE KEY-----(\\n[^\\]*)*\\n-----END [A-Z ]*PRIVATE KEY-----(\\n)?/, "[REDACTED]", line)
      line = redact_conn(line)
      line = redact_envsecret(line)
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
      # user never typed. These are the primary defense. The filters below
      # are a heuristic secondary defense for injections that carry no
      # structural marker: a message opening with a hyphenated-tag XML
      # opener (e.g. <command-message>, <local-command-stdout>,
      # <system-reminder>, <task-notification>, <bash-stdout>,
      # <teammate-message ...>) is almost certainly a harness wrapper, not
      # user prose. Gated on the hyphen specifically: a survey of ~5,200 real
      # user messages across 91 project transcripts found every
      # harness-injected "<tag>" opener uses a hyphenated name, while the
      # only real user messages starting with "<" (pasted HTML, log lines
      # like "<100k rows") never do — so requiring a hyphen adds zero
      # observed false positives, whereas matching any lowercase tag (e.g.
      # bare "<div>") would wrongly exclude genuine pasted markup. Known
      # miss: a hyphenated custom HTML element (e.g. "<my-component>") would
      # also be excluded, but none appeared in the survey. The two literal
      # string prefixes have no tag-shaped marker, so they stay as
      # exact-prefix checks.
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
          ($text | test("^<[a-z][a-z0-9]*-[a-z0-9-]*[ >]") | not)
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
