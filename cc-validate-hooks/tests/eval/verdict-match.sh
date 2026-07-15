#!/usr/bin/env bash
# Offline eval grader for the cc-validate-hooks core validator.
#
# Runs scripts/validate-hooks-core.py against every fixture and compares the
# core's ACTUAL verdict (error/warning sentinel counts, or a crash) to the gold
# label in expected-verdicts.tsv. Fully deterministic: no network, no model, no
# secrets — pure Python/bash over local fixtures.
#
# Verdict compared per fixture:
#   - expected_errors == "CRASH"  -> PASS iff the core exits nonzero.
#   - otherwise                   -> PASS iff the core exits 0, its __ERRORS__ /
#                                    __WARNINGS__ sentinels equal the expected
#                                    counts, AND (signature == "-" or the
#                                    signature substring appears in stdout).
#
# Output: one PASS/FAIL line per fixture, then a hard gate (all-must-pass -> 1/0)
# and a soft fraction (passed/total). Exits nonzero when below the pass
# threshold (default: all must pass).
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="${script_dir}/../../scripts/validate-hooks-core.py"
manifest="${script_dir}/expected-verdicts.tsv"
fixtures_dir="${script_dir}/fixtures"

# All fixtures must pass by default. Override with THRESHOLD=0.9 for a softer gate.
THRESHOLD="${THRESHOLD:-1.0}"

PYTHON="$(command -v python3 || command -v python || true)"
[[ -z "$PYTHON" ]] && { echo "verdict-match.sh: python3 (or python) not found in PATH" >&2; exit 2; }
[[ -f "$core" ]] || { echo "verdict-match.sh: core not found: $core" >&2; exit 2; }
[[ -f "$manifest" ]] || { echo "verdict-match.sh: manifest not found: $manifest" >&2; exit 2; }

total=0
passed=0

echo "## cc-validate-hooks core verdict match"
echo

# Read the TSV, skipping comment (#) and blank lines.
while IFS=$'\t' read -r fixture exp_err exp_warn signature description || [[ -n "$fixture" ]]; do
  [[ -z "$fixture" || "$fixture" == \#* ]] && continue

  path="${fixtures_dir}/${fixture}"
  total=$((total + 1))

  if [[ ! -f "$path" ]]; then
    printf 'FAIL  %-32s -- fixture file missing\n' "$fixture"
    continue
  fi

  out="$("$PYTHON" "$core" "$path" False 2>/dev/null)"
  ec=$?

  if [[ "$exp_err" == "CRASH" ]]; then
    if [[ "$ec" -ne 0 ]]; then
      printf 'PASS  %-32s -- crashed as expected (exit %s)\n' "$fixture" "$ec"
      passed=$((passed + 1))
    else
      printf 'FAIL  %-32s -- expected crash, but core exited 0\n' "$fixture"
    fi
    continue
  fi

  if [[ "$ec" -ne 0 ]]; then
    printf 'FAIL  %-32s -- core crashed unexpectedly (exit %s)\n' "$fixture" "$ec"
    continue
  fi

  act_err="$(printf '%s\n' "$out" | grep '^__ERRORS__:'   | cut -d: -f2)"
  act_warn="$(printf '%s\n' "$out" | grep '^__WARNINGS__:' | cut -d: -f2)"

  reason=""
  [[ "$act_err"  == "$exp_err"  ]] || reason+="errors ${act_err}!=${exp_err}; "
  [[ "$act_warn" == "$exp_warn" ]] || reason+="warnings ${act_warn}!=${exp_warn}; "
  if [[ "$signature" != "-" ]] && ! printf '%s' "$out" | grep -qF -- "$signature"; then
    reason+="signature not found: '${signature}'; "
  fi

  if [[ -z "$reason" ]]; then
    printf 'PASS  %-32s -- errors=%s warnings=%s\n' "$fixture" "$act_err" "$act_warn"
    passed=$((passed + 1))
  else
    printf 'FAIL  %-32s -- %s\n' "$fixture" "${reason%; }"
  fi
done < "$manifest"

echo
# Soft fraction + hard gate.
frac="$("$PYTHON" -c "print(f'{$passed/$total:.4f}')" 2>/dev/null || echo 0)"
if [[ "$passed" -eq "$total" ]]; then
  hard=1
else
  hard=0
fi

echo "soft: ${passed}/${total} (${frac})"
echo "hard: ${hard} (all-must-pass gate)"

# Exit nonzero when below threshold.
below="$("$PYTHON" -c "import sys; sys.exit(0 if $frac + 1e-9 >= $THRESHOLD else 1)"; echo $?)"
if [[ "$below" -ne 0 ]]; then
  echo "RESULT: FAIL (${frac} < threshold ${THRESHOLD})"
  exit 1
fi
echo "RESULT: PASS (>= threshold ${THRESHOLD})"
exit 0
