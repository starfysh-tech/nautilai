#!/usr/bin/env bash
# Hindsight eval: score a relay extractor's output on a real transcript cut at
# line K against what the rest of the session went on to use. "Needed" tokens
# are the distinctive tokens (paths, flags, identifiers, numbers with units,
# issue refs) present both before and after the cut. Prints aggregates only.
#
#   hindsight.sh split <transcript> <cut-line> <workdir>
#     writes <workdir>/prefix.jsonl and token sets; cut-line is the first
#     suffix line (for a compaction cut, the compact_boundary line).
#   hindsight.sh score <workdir> <output-file>
#     prints: needed  recall  top50  invented  bytes
set -euo pipefail

# Flatten user/assistant text, tool_use input values, and tool_result text.
# Drops compaction summaries, isMeta turns, and <system-reminder> blocks so
# the suffix can't "need" a token only because a summary or the harness
# copied it forward.
flatten() {
  jq -rR 'fromjson? | select(type=="object")
    | select(.type=="user" or .type=="assistant")
    | select(.isCompactSummary != true and .isMeta != true)
    | .message.content
    | if type=="string" then .
      else .[]? |
        if .type=="text" then .text
        elif .type=="tool_use" then [.input | .. | strings] | join(" ")
        elif .type=="tool_result" then
          (.content | if type=="string" then . elif type=="array" then map(.text? // "") | join("\n") else "" end)
        else empty end
      end
    | gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "")' "$@"
}

tokens() {
  grep -oE '[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.(sh|md|json|jsonl|ts|tsx|js|py|swift|kt|toml|yml|yaml|html|css|sql|txt)\b|--[a-z][a-z0-9-]{2,}|\b[A-Z][A-Z0-9]*_[A-Z0-9_]{2,}\b|\b[a-z][a-z0-9]*_[a-z0-9_]+\b|\b[a-z]+[A-Z][A-Za-z0-9]+\b|\b[0-9]+(\.[0-9]+)?(ms|s|KB|MB|GB|%|px)\b|#[0-9]{2,}' || true
}

case "${1:-}" in
  split)
    transcript="$2" cut="$3" w="$4"
    mkdir -p "$w"
    head -n "$((cut - 1))" "$transcript" > "$w/prefix.jsonl"
    tail -n "+$cut" "$transcript" > "$w/suffix.jsonl"
    flatten "$w/prefix.jsonl" | tokens | sort -u > "$w/prefix.tok"
    flatten "$w/suffix.jsonl" | tokens | sort | uniq -c | sort -rn > "$w/suffix.cnt"
    awk '{print $2}' "$w/suffix.cnt" | sort -u > "$w/suffix.tok"
    comm -12 "$w/prefix.tok" "$w/suffix.tok" > "$w/needed.tok"
    # Top 50 needed tokens by how often the suffix uses them.
    awk 'NR==FNR {n[$1]=1; next} ($2 in n) {print $2}' "$w/needed.tok" "$w/suffix.cnt" | head -n 50 | sort -u > "$w/top50.tok"
    rm -f "$w/suffix.jsonl"
    ;;
  score)
    w="$2" out="$3"
    o=$(mktemp); trap 'rm -f "$o"' EXIT
    tokens < "$out" | sort -u > "$o"
    n=$(wc -l < "$w/needed.tok" | tr -d ' ')
    hit=$(comm -12 "$w/needed.tok" "$o" | wc -l | tr -d ' ')
    t=$(wc -l < "$w/top50.tok" | tr -d ' ')
    thit=$(comm -12 "$w/top50.tok" "$o" | wc -l | tr -d ' ')
    inv=$(comm -23 "$o" "$w/prefix.tok" | wc -l | tr -d ' ')
    bytes=$(wc -c < "$out" | tr -d ' ')
    awk -v n="$n" -v h="$hit" -v t="$t" -v th="$thit" -v i="$inv" -v b="$bytes" \
      'BEGIN { printf "%d\t%.3f\t%.3f\t%d\t%d\n", n, (n ? h/n : 0), (t ? th/t : 0), i, b }'
    ;;
  *)
    echo "usage: hindsight.sh split <transcript> <cut-line> <workdir> | score <workdir> <output-file>" >&2
    exit 1
    ;;
esac
