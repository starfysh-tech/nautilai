#!/usr/bin/env bash
# MANUAL live validation — NOT CI. Runs relay's extractors against REAL session
# transcripts (read-only) and makes live Haiku calls, so it needs the `claude`
# CLI and costs tokens. Issue #60.
#
# Usage: live-validate.sh <transcript.jsonl> [<transcript.jsonl> ...]
#   MAX_TRANSCRIPTS=N   cap how many are processed (default 5)
#
# Output is METRICS ONLY — counts, booleans, timings. It never prints transcript
# content: pass real transcripts as args; the operator keeps the paths, the
# committed harness and any ledger record only shapes and aggregate numbers.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EXTRACT="$HERE/../../scripts/extract-transcript.sh"
NARRATE="$HERE/../../scripts/haiku-narrative.sh"
MAX="${MAX_TRANSCRIPTS:-5}"

if [ "$#" -eq 0 ]; then
  echo "usage: live-validate.sh <transcript.jsonl> [more...]" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

now_s() { date +%s; }

printf '%-26s %8s %3s %4s | %5s %5s %4s %5s %4s | %-9s %5s %4s\n' \
  SHAPE BYTES CMP SUBS FILES CMDS FAIL USERS RDCT NARRATIVE SECS HEAD

count=0
for t in "$@"; do
  [ "$count" -ge "$MAX" ] && break
  [ -f "$t" ] || { echo "skip (not found): metrics-only, path withheld" >&2; continue; }
  count=$((count + 1))

  bytes=$(wc -c < "$t" | tr -d ' ')
  cmp=$(grep -c '"isCompactSummary":true' "$t" 2>/dev/null); cmp=${cmp:-0}
  d=$(dirname "$t"); id=$(basename "$t" .jsonl); subs=0
  [ -d "$d/$id/subagents" ] && subs=$(ls "$d/$id/subagents"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')

  # Fact pack — count items per section, never emit the content itself.
  fp=$(bash "$EXTRACT" "$t" 2>/dev/null)
  counts=$(printf '%s\n' "$fp" | awk '
    /^## Files touched/       {s="F"; next}
    /^## Commands run/        {s="C"; next}
    /^## Failures/            {s="X"; next}
    /^## User messages/       {s="U"; next}
    /^## Provenance/          {s="P"; next}
    s=="F" && /^- /           {f++}
    s=="C" && /^- /           {c++}
    s=="X" && /^- /           {x++}
    s=="U" && /^[0-9]+\. /     {u++}
    END{printf "%d %d %d %d", f, c, x, u}')
  read -r nf nc nx nu <<EOF
$counts
EOF
  rdct=$(printf '%s\n' "$fp" | grep -o '\[REDACTED\]' | wc -l | tr -d ' ')

  # Narrative — timed live call; capture exit + heading count, no content.
  ns=$(now_s)
  nout=$(bash "$NARRATE" "$t" 2>/dev/null); nexit=$?
  ne=$(now_s); secs=$((ne - ns))
  heads=$(printf '%s\n' "$nout" | grep -c '^## ')
  if [ "$nexit" -eq 0 ]; then nstat="ok"; else nstat="degrade:$nexit"; fi

  # Shape label derived only from metrics (size band / compaction / subagents).
  band="sm"; [ "$bytes" -gt 1000000 ] && band="md"; [ "$bytes" -gt 8000000 ] && band="lg"; [ "$bytes" -gt 18000000 ] && band="xl"
  shape="$band"; [ "$cmp" -ge 1 ] && shape="$shape/cmp$cmp"; [ "$subs" -ge 20 ] && shape="$shape/agents"

  printf '%-26s %8d %3d %4d | %5d %5d %4d %5d %4d | %-9s %5d %4d\n' \
    "$shape" "$bytes" "$cmp" "$subs" "$nf" "$nc" "$nx" "$nu" "$rdct" "$nstat" "$secs" "$heads"
done

echo
echo "processed: $count (MAX_TRANSCRIPTS=$MAX)"
