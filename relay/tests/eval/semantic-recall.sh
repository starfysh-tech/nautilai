#!/usr/bin/env bash
# MANUAL EVAL — not run in CI. This is the shipping gate for the Haiku
# narrative layer (relay Phase 2): it measures whether narrative.sh recovers
# semantic facts that live only in assistant text turns, which the baseline
# jq fact-pack extractor (relay/scripts/extract-transcript.sh) structurally
# cannot see (it only reads tool_use/tool_result/user-text turns). Baseline
# recall on assistant-turn facts is expected to be ~0 by construction; that's
# the point of comparison, not a bug in the baseline.
#
# Run manually: bash relay/tests/eval/semantic-recall.sh
# Requires jq. Calls relay/scripts/haiku-narrative.sh, which makes a live
# model call — do not wire this into any CI workflow.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "semantic-recall.sh: jq is required but was not found in PATH" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
fixture="${script_dir}/fixtures/semantic.jsonl"
facts_tsv="${script_dir}/facts.tsv"
extractor="${script_dir}/../../scripts/extract-transcript.sh"
narrator="${script_dir}/../../scripts/haiku-narrative.sh"

if [ ! -f "$fixture" ]; then
  echo "semantic-recall.sh: fixture not found: ${fixture}" >&2
  exit 1
fi
if [ ! -f "$facts_tsv" ]; then
  echo "semantic-recall.sh: facts file not found: ${facts_tsv}" >&2
  exit 1
fi
if [ ! -x "$extractor" ]; then
  echo "semantic-recall.sh: baseline extractor not found or not executable: ${extractor}" >&2
  exit 1
fi

baseline_out=""
narrative_out=""
narrative_err=""
trap 'rm -f "$baseline_out" "$narrative_out" "$narrative_err"' EXIT
baseline_out=$(mktemp)
narrative_out=$(mktemp)
narrative_err=$(mktemp)

"$extractor" "$fixture" > "$baseline_out"

narrative_available=1
if [ ! -x "$narrator" ]; then
  narrative_available=0
  echo "NARRATIVE: unavailable (relay/scripts/haiku-narrative.sh not found)"
else
  narr_rc=0
  "$narrator" "$fixture" > "$narrative_out" 2>"$narrative_err" || narr_rc=$?
  if [ "$narr_rc" -eq 3 ]; then
    narrative_available=0
    echo "NARRATIVE: unavailable (haiku-narrative.sh degraded, exit 3)" >&2
    cat "$narrative_err" >&2 || true
  elif [ "$narr_rc" -ne 0 ]; then
    echo "semantic-recall.sh: haiku-narrative.sh failed unexpectedly (exit ${narr_rc})" >&2
    cat "$narrative_err" >&2 || true
    exit 1
  fi
fi

# Case-insensitive whole-word/whole-phrase match (fixed string, word-boundary).
# Word-boundary matters: without it "NAT" would false-hit inside "narrative" or
# "saturate", and short tokens like "429" or "2x" would match as substrings of
# unrelated numbers. This also means a keyword only matches its own inflection
# ("skews" won't match a paraphrase's "skew" or vice versa) — an honest miss,
# not a bug; facts.tsv picks the form that's actually in the fixture.
present() {
  # $1 = haystack file, $2 = needle
  grep -qiFw -- "$2" "$1"
}

# Per-class counters: total, baseline-recovered, narrative-recovered.
decision_total=0; decision_base=0; decision_narr=0
deadend_total=0; deadend_base=0; deadend_narr=0
cu_total=0; cu_base=0; cu_narr=0
ca_total=0; ca_base=0; ca_narr=0

echo
echo "## Per-fact scoring"
echo
printf '%-5s %-20s %-8s %-8s\n' "id" "class" "baseline" "narrative"

while IFS=$'\t' read -r id class kw1 kw2 summary; do
  [ -z "$id" ] && continue

  base_hit=0
  if present "$baseline_out" "$kw1" && present "$baseline_out" "$kw2"; then
    base_hit=1
  fi

  narr_hit=0
  narr_label="n/a"
  if [ "$narrative_available" -eq 1 ]; then
    narr_label="miss"
    if present "$narrative_out" "$kw1" && present "$narrative_out" "$kw2"; then
      narr_hit=1
      narr_label="hit"
    fi
  fi

  base_label="miss"
  [ "$base_hit" -eq 1 ] && base_label="hit"

  printf '%-5s %-20s %-8s %-8s\n' "$id" "$class" "$base_label" "$narr_label"

  case "$class" in
    decision)
      decision_total=$((decision_total + 1))
      decision_base=$((decision_base + base_hit))
      decision_narr=$((decision_narr + narr_hit))
      ;;
    deadend)
      deadend_total=$((deadend_total + 1))
      deadend_base=$((deadend_base + base_hit))
      deadend_narr=$((deadend_narr + narr_hit))
      ;;
    constraint-user)
      cu_total=$((cu_total + 1))
      cu_base=$((cu_base + base_hit))
      cu_narr=$((cu_narr + narr_hit))
      ;;
    constraint-assistant)
      ca_total=$((ca_total + 1))
      ca_base=$((ca_base + base_hit))
      ca_narr=$((ca_narr + narr_hit))
      ;;
    *)
      echo "semantic-recall.sh: unknown fact class '${class}' for id ${id}" >&2
      exit 1
      ;;
  esac
done < "$facts_tsv"

fmt_narr() {
  # $1 = recovered, $2 = total
  if [ "$narrative_available" -eq 1 ]; then
    printf '%d/%d' "$1" "$2"
  else
    printf 'N/A'
  fi
}

echo
echo "## Per-class recall (baseline vs narrative)"
echo
printf '%-22s %-10s %-10s\n' "class" "baseline" "narrative"
printf '%-22s %-10s %-10s\n' "decision" "${decision_base}/${decision_total}" "$(fmt_narr "$decision_narr" "$decision_total")"
printf '%-22s %-10s %-10s\n' "deadend" "${deadend_base}/${deadend_total}" "$(fmt_narr "$deadend_narr" "$deadend_total")"
printf '%-22s %-10s %-10s\n' "constraint-user" "${cu_base}/${cu_total}" "$(fmt_narr "$cu_narr" "$cu_total")"
printf '%-22s %-10s %-10s\n' "constraint-assistant" "${ca_base}/${ca_total}" "$(fmt_narr "$ca_narr" "$ca_total")"

overall_total=$((decision_total + deadend_total + cu_total + ca_total))
overall_base=$((decision_base + deadend_base + cu_base + ca_base))
overall_narr=$((decision_narr + deadend_narr + cu_narr + ca_narr))

base_pct=$(( overall_total > 0 ? overall_base * 100 / overall_total : 0 ))
echo
echo "## Overall recall"
echo
echo "baseline:  ${overall_base}/${overall_total} (${base_pct}%)"
if [ "$narrative_available" -eq 1 ]; then
  narr_pct=$(( overall_total > 0 ? overall_narr * 100 / overall_total : 0 ))
  echo "narrative: ${overall_narr}/${overall_total} (${narr_pct}%)"
else
  echo "narrative: N/A (unavailable)"
fi

# Shipping gate: assistant-turn-only facts (decision + deadend +
# constraint-assistant) are the ones the baseline structurally cannot see.
# PASS requires narrative to recover >= 80% of those 12 facts (>= 10/12).
gate_total=$((decision_total + deadend_total + ca_total))
gate_narr=$((decision_narr + deadend_narr + ca_narr))

echo
if [ "$narrative_available" -eq 0 ]; then
  echo "GATE: SKIPPED — narrative unavailable, baseline-only mode"
  exit 0
fi

gate_threshold=$(( (gate_total * 80 + 99) / 100 ))  # ceil(80% of gate_total)
echo "gate: assistant-turn facts (decision+deadend+constraint-assistant) = ${gate_narr}/${gate_total} recovered by narrative (need >= ${gate_threshold})"
if [ "$gate_narr" -ge "$gate_threshold" ]; then
  echo "GATE: PASS"
  exit 0
else
  echo "GATE: FAIL"
  exit 1
fi
