#!/usr/bin/env bash
# Offline eval for the phi-scan DETERMINISTIC scanner (phi-scan/scripts/phi_check.py).
# AI-triage sits on top of the scanner and is OUT OF SCOPE here — no model is called.
#
# What it measures:
#   RECALL (HARD GATE) — of the planted, detectable-class PHI items in the
#     "positive" fixtures, how many the deterministic regex layer detects. Names
#     and MRNs are NOT regex-detectable (SKILL.md), so they live in an
#     "expected-miss" fixture and never count against recall.
#   PRECISION / false positives (INFORMATIONAL) — findings on "negative"
#     (PHI-adjacent) fixtures. Triage owns precision, so this is NOT gated.
#
# Why the odd invocation: phi_check.py SKIPS any path containing "/tests/"
# (should_skip_file) and classifies anything under "/fixtures/" as test data
# (is_test_data). Both would zero out this eval if we scanned the fixtures in
# place. So we copy each fixture to a neutral temp dir and pass
# --include-test-data, which measures the detection regex in isolation from the
# downstream test-data filter (that filter correctly suppressing synthetic data
# is its job, not what we're grading here).
#
# Everything is offline: pure python3 + bash against local fixtures. No network,
# no API, no secrets.
#
# Exit: 0 if the recall hard gate passes, 1 otherwise.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
scanner="${script_dir}/../../scripts/phi_check.py"
fixtures_dir="${script_dir}/fixtures"
gold_tsv="${script_dir}/gold.tsv"

# Recall hard-gate threshold as a percentage (100 = every planted item must be detected).
RECALL_THRESHOLD="${RECALL_THRESHOLD:-100}"

# Identifier labels the deterministic layer CLAIMS to detect. Only these count
# toward recall. (Names/MRNs are absent by design — the scanner has no such class.)
DETECTABLE="ssn email phone ip_v4 date_us date_iso zip_5 zip_5(restricted)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "recall-precision.sh: python3 is required but was not found in PATH" >&2
  exit 1
fi
if [ ! -f "$scanner" ]; then
  echo "recall-precision.sh: scanner not found: ${scanner}" >&2
  exit 1
fi
if [ ! -f "$gold_tsv" ]; then
  echo "recall-precision.sh: gold manifest not found: ${gold_tsv}" >&2
  exit 1
fi

is_detectable() {
  local c="$1"
  for d in $DETECTABLE; do
    [ "$c" = "$d" ] && return 0
  done
  return 1
}

# Neutral scan dir outside any /tests/ or /fixtures/ path segment.
workdir=""
trap 'if [ -n "$workdir" ]; then rm -rf "$workdir"; fi' EXIT
workdir="$(mktemp -d "${TMPDIR:-/tmp}/phi-eval.XXXXXX")"

# --- Load gold into parallel arrays -----------------------------------------
# role_of[fixture]=role ; exp["fixture|class"]=count
declare -A role_of
declare -A exp
fixtures_order=()

while IFS=$'\t' read -r fixture role class count _; do
  [ -z "${fixture:-}" ] && continue
  case "$fixture" in \#*) continue;; esac
  if [ -z "${role_of[$fixture]:-}" ]; then
    role_of[$fixture]="$role"
    fixtures_order+=("$fixture")
  fi
  if [ "$class" != "_none_" ]; then
    exp["${fixture}|${class}"]="$count"
  fi
done < "$gold_tsv"

# --- Per-fixture scoring ----------------------------------------------------
pass_count=0
total_fixtures=0
recall_total=0
recall_detected=0
fp_total=0        # false positives on negative fixtures
tp_total=0        # true positives = detected planted items on positive fixtures

echo "# phi-scan deterministic scanner — recall / precision eval"
echo
printf '%-32s %-14s %s\n' "fixture" "role" "result"
printf '%-32s %-14s %s\n' "-------" "----" "------"

for fixture in "${fixtures_order[@]}"; do
  total_fixtures=$((total_fixtures + 1))
  role="${role_of[$fixture]}"
  src="${fixtures_dir}/${fixture}"
  if [ ! -f "$src" ]; then
    printf '%-32s %-14s %s\n' "$fixture" "$role" "FAIL (fixture file missing)"
    continue
  fi
  cp -f "$src" "${workdir}/${fixture}"

  # Run scanner; exit 1 (PHI found) is expected, so guard it.
  out="$(cd "$workdir" && python3 "$scanner" "$fixture" --include-test-data 2>/dev/null || true)"

  # Extract one identifier label per finding line:
  #   "  12:3 [PHI] zip_5(restricted): 03601"  ->  "zip_5(restricted)"
  observed_labels="$(printf '%s\n' "$out" \
    | grep -oE '\[(PHI|TEST)\] [a-z0-9_()]+:' \
    | sed -E 's/^\[(PHI|TEST)\] //; s/:$//' || true)"

  # Count observed per class.
  declare -A obs=()
  if [ -n "$observed_labels" ]; then
    while read -r c; do
      [ -z "$c" ] && continue
      obs["$c"]=$(( ${obs["$c"]:-0} + 1 ))
    done <<< "$observed_labels"
  fi

  # Union of expected and observed classes for this fixture.
  declare -A seen=()
  classes=()
  for key in "${!exp[@]}"; do
    case "$key" in
      "${fixture}|"*)
        c="${key#"${fixture}"|}"
        if [ -z "${seen[$c]:-}" ]; then seen[$c]=1; classes+=("$c"); fi
        ;;
    esac
  done
  for c in "${!obs[@]}"; do
    if [ -z "${seen[$c]:-}" ]; then seen[$c]=1; classes+=("$c"); fi
  done

  fixture_ok=1
  detail=""
  for c in "${classes[@]}"; do
    e=${exp["${fixture}|${c}"]:-0}
    o=${obs["$c"]:-0}
    [ "$e" -ne "$o" ] && fixture_ok=0
    detail="${detail} ${c}=${o}/${e}"

    # Recall bookkeeping: positive fixtures, detectable classes only.
    if [ "$role" = "positive" ] && is_detectable "$c"; then
      recall_total=$((recall_total + e))
      hit=$e; [ "$o" -lt "$e" ] && hit=$o
      recall_detected=$((recall_detected + hit))
      tp_total=$((tp_total + hit))
    fi
    # Precision bookkeeping: any finding on a negative fixture is a false positive.
    if [ "$role" = "negative" ]; then
      fp_total=$((fp_total + o))
    fi
  done

  if [ "$fixture_ok" -eq 1 ]; then
    pass_count=$((pass_count + 1))
    printf '%-32s %-14s %s\n' "$fixture" "$role" "PASS  [${detail# }]"
  else
    printf '%-32s %-14s %s\n' "$fixture" "$role" "FAIL  [${detail# }]  (observed != gold)"
  fi

  unset obs seen classes
done

# --- Aggregates -------------------------------------------------------------
recall_pct=$(( recall_total > 0 ? recall_detected * 100 / recall_total : 0 ))
den=$(( tp_total + fp_total ))
prec_pct=$(( den > 0 ? tp_total * 100 / den : 0 ))

echo
echo "## Recall (HARD GATE) — detectable-class planted items"
echo "detected ${recall_detected}/${recall_total} (${recall_pct}%), threshold ${RECALL_THRESHOLD}%"
echo
echo "## Precision (INFORMATIONAL — triage owns precision, not gated)"
echo "true positives ${tp_total}, false positives on negative fixtures ${fp_total}, precision ${prec_pct}%"
echo

# Soft fraction: how many fixtures matched their recorded gold exactly.
echo "## Aggregate"
echo "soft: ${pass_count}/${total_fixtures} fixtures match recorded gold"

# Hard gate: recall must meet threshold (all-must-pass -> 1/0).
if [ "$recall_pct" -ge "$RECALL_THRESHOLD" ]; then
  echo "hard: 1 (recall gate PASS)"
  echo
  echo "GATE: PASS"
  exit 0
else
  echo "hard: 0 (recall gate FAIL)"
  echo
  echo "GATE: FAIL"
  exit 1
fi
